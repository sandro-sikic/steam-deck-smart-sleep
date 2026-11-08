#!/bin/bash
# steam-deck-smart-sleep.sh
#
# This script is intended to run on a Steam Deck (or other
# Linux system with an RTC) as a systemd "system-sleep" hook.
#
# When the machine is about to suspend the system (sleep/hibernate),
# systemd will invoke this script with two arguments: $1 is "pre" and
# $2 is the sleep type (e.g. "suspend", "hibernate", "hybrid-sleep").
# At that point we calculate a wakeup time WAKE_DELAY seconds in the future
# and programme the RTC accordingly.  We persist the target time in
# a temporary file so that on resume we can tell whether we actually
# woke because the timer expired or because the user intervened.
#
# After coming back from sleep systemd calls the script again with
# argument "post".  In that case we compare the current time against
# the stored wake time:
#   * if the clock has already passed the scheduled value we assume
#     the machine woke up via the RTC alarm; if still charging we
#     reschedule the alarm and go back to sleep, otherwise we request
#     a clean shutdown via systemctl.
#   * if the system came back early we simply clear the alarm so it
#     won't fire later and remove the marker file.
#
# The delay is read from smart-sleep.conf, which lives next to the installed
# copy of this script (default 180 minutes when the file is missing or invalid).
#
# The hook never fails the suspend: every problem is logged and the device
# simply falls back to normal sleep behaviour.
#
# To install, copy this file to /usr/lib/systemd/system-sleep/ or
# /etc/systemd/system-sleep/ and ensure it is executable.  It runs as
# root during suspend/resume.

# No `set -e`: a hook that aborts half way would leave a stale marker or
# alarm behind, so every step handles its own failure.
set -uo pipefail

# Seconds after suspend at which the RTC alarm fires when the config file is
# missing or invalid.  The real setting is WAKE_DELAY_MINUTES in the config.
DEFAULT_WAKE_DELAY=10800

# the largest delay the config may ask for (one week), in minutes
MAX_WAKE_MINUTES=10080

# the log is rotated (once) when it grows past this many bytes
MAX_LOG_BYTES=1048576

# Paths and commands can be overridden through the environment (the test
# suite does this); the defaults are the real system locations.
LOGFILE="${SDSS_LOGFILE:-/var/log/steam-deck-smart-sleep.log}"
TMPMARK="${SDSS_MARKER:-/run/rtc_shutdown_wake}"   # tmpfs, removed on reboot
RTCWAKE="${SDSS_RTCWAKE:-/usr/bin/rtcwake}"
RTC_WAKEALARM="${SDSS_RTC_WAKEALARM:-/sys/class/rtc/rtc0/wakealarm}"
SYSTEMCTL="${SDSS_SYSTEMCTL:-/usr/bin/systemctl}"
POWER_SUPPLY_DIR="${SDSS_POWER_SUPPLY_DIR:-/sys/class/power_supply}"

# helper for appending timestamped messages to log
log_msg() {
    local msg="$*" size
    size=$(stat -c %s "$LOGFILE" 2>/dev/null || echo 0)
    if [ "$size" -gt "$MAX_LOG_BYTES" ]; then
        mv -f "$LOGFILE" "$LOGFILE.1" 2>/dev/null || true
    fi
    printf '%s %s\n' "$(date --iso-8601=seconds)" "$msg" >> "$LOGFILE" 2>/dev/null || true
}

now_epoch() {
    date +%s
}

# Path of the config file: next to the real (symlink-resolved) script, i.e.
# in ~/steam-deck-smart-sleep, unless SDSS_CONFIG says otherwise.
config_file() {
    if [ -n "${SDSS_CONFIG:-}" ]; then
        echo "$SDSS_CONFIG"
    else
        local self
        self=$(readlink -f "${BASH_SOURCE[0]}")
        echo "$(dirname "$self")/smart-sleep.conf"
    fi
}

# Echo the WAKE_DELAY_MINUTES value of the config (the last one wins), or
# nothing.  The file is parsed, never sourced: it sits in a user-writable
# directory and this hook runs as root.
read_config_minutes() {
    local file line minutes="" lines=()
    file=$(config_file)
    [ -r "$file" ] || return 0
    mapfile -t lines < "$file"
    for line in "${lines[@]}"; do
        if [[ "$line" =~ ^WAKE_DELAY_MINUTES=([0-9]+)[[:space:]]*$ ]]; then
            minutes="${BASH_REMATCH[1]}"
        fi
    done
    echo "$minutes"
}

# Echo the delay in seconds: the configured minutes when valid, otherwise the
# default (logging why when a config file exists but is unusable).
effective_delay() {
    local file minutes
    file=$(config_file)
    if [ ! -e "$file" ]; then
        echo "$DEFAULT_WAKE_DELAY"
        return 0
    fi
    minutes=$(read_config_minutes)
    if [ -n "$minutes" ] && [ $((10#$minutes)) -ge 1 ] && [ $((10#$minutes)) -le "$MAX_WAKE_MINUTES" ]; then
        echo $((10#$minutes * 60))
    else
        log_msg "no valid WAKE_DELAY_MINUTES (1-$MAX_WAKE_MINUTES) in $file; using $((DEFAULT_WAKE_DELAY / 60)) minutes"
        echo "$DEFAULT_WAKE_DELAY"
    fi
}

clear_alarm() {
    if [ -x "$RTCWAKE" ]; then
        "$RTCWAKE" -m disable >/dev/null 2>&1 || log_msg "rtcwake -m disable failed"
    else
        echo 0 > "$RTC_WAKEALARM" 2>/dev/null || log_msg "could not clear $RTC_WAKEALARM"
    fi
    log_msg "cleared RTC alarm"
}

# Programme the RTC alarm and record the target time.  Returns non-zero (and
# leaves no marker behind) if the alarm could not be set.
schedule_alarm() {
    if [ ! -x "$RTCWAKE" ]; then
        log_msg "rtcwake not found at $RTCWAKE"
        return 1
    fi

    local delay when
    delay=$(effective_delay)
    when=$(( $(now_epoch) + delay ))

    # The marker goes first so an alarm is never armed without one.
    if ! echo "$when" > "$TMPMARK" 2>/dev/null; then
        log_msg "could not write marker $TMPMARK"
        return 1
    fi

    # "-m no" only sets the alarm; systemd performs the actual sleep.
    # Disable first so a stale alarm cannot survive a failed re-arm.
    "$RTCWAKE" -m disable >/dev/null 2>&1 || true
    if ! "$RTCWAKE" -m no -t "$when" >/dev/null 2>&1; then
        rm -f "$TMPMARK"
        log_msg "rtcwake failed to set the alarm"
        return 1
    fi

    log_msg "scheduled wakeup at $when (delay=$delay)"
}

# Returns 0 (true) if the device is currently connected to AC power / charging.
is_charging() {
    # Check for AC adapter online status (covers most common sysfs layouts)
    local ac
    for ac in "$POWER_SUPPLY_DIR"/AC*/online \
              "$POWER_SUPPLY_DIR"/ADP*/online \
              "$POWER_SUPPLY_DIR"/ACAD*/online; do
        [ -f "$ac" ] || continue
        [ "$(cat "$ac" 2>/dev/null)" = "1" ] && return 0
    done
    # Fallback: check battery charging status
    local bat status
    for bat in "$POWER_SUPPLY_DIR"/BAT*/status; do
        [ -f "$bat" ] || continue
        status=$(cat "$bat" 2>/dev/null)
        [[ "$status" == "Charging" || "$status" == "Full" ]] && return 0
    done
    return 1
}

# Run a systemctl action without waiting: the hook runs while sleep.target is
# still being torn down, and a blocking call from in here can deadlock.
systemctl_nowait() {
    local out
    out=$("$SYSTEMCTL" --no-block "$1" 2>&1) || log_msg "systemctl $1 failed: $out"
}

handle_pre() {
    log_msg "handling pre-sleep"
    # Never block the suspend: without an alarm the device just sleeps normally.
    schedule_alarm || log_msg "no alarm set; the device will not auto-shutdown this cycle"
    return 0
}

handle_post() {
    log_msg "handling post-sleep"
    if [ ! -f "$TMPMARK" ]; then
        log_msg "no marker file; nothing to do"
        return 0
    fi

    local scheduled now
    scheduled=$(cat "$TMPMARK" 2>/dev/null || true)
    rm -f "$TMPMARK"

    if ! [[ "$scheduled" =~ ^[0-9]+$ ]]; then
        log_msg "invalid marker contents '$scheduled'; cancelling alarm"
        clear_alarm
        return 0
    fi

    now=$(now_epoch)
    log_msg "wake time was $scheduled, now is $now"

    if [ "$now" -lt "$scheduled" ]; then
        # woke early; cancel the alarm so it doesn't fire later
        log_msg "woke early, cancelling alarm"
        clear_alarm
        return 0
    fi

    # timer elapsed while we were asleep
    log_msg "timer elapsed, checking charging status"
    if is_charging; then
        # Still on AC power – reschedule and go back to sleep.  If the alarm
        # cannot be set we stay awake rather than sleep with no way to wake.
        log_msg "device is charging; rescheduling alarm and returning to sleep"
        if schedule_alarm; then
            systemctl_nowait suspend
        else
            log_msg "could not reschedule; staying awake"
        fi
    else
        # Not charging – initiate a clean shutdown
        log_msg "device is not charging; initiating shutdown sequence"
        systemctl_nowait poweroff
    fi
}

main() {
    case "${1:-}" in
        pre)
            handle_pre
            ;;
        post)
            handle_post
            ;;
        *)
            echo "Usage: $0 {pre|post}" >&2
            return 1
            ;;
    esac
}

# Only run when executed, so the tests can source the functions.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
