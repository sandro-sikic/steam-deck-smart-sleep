#!/bin/bash
# steam-deck-smart-sleep.sh
#
# This script is intended to run on a Steam Deck (or other
# Linux system with an RTC) as a systemd "system-sleep" hook.
#
# When the machine is about to suspend the system (sleep/hibernate),
# systemd will invoke this script with the first argument "pre".
# At that point we calculate a wakeup time 30 seconds in the future
# and programme the RTC accordingly.  We persist the target time in
# a temporary file so that on resume we can tell whether we actually
# woke because the timer expired or because the user intervened.
#
# After coming back from sleep systemd calls the script again with
# argument "post".  In that case we compare the current time against
# the stored wake time:
#   * if the clock has already passed the scheduled value we assume
#     the machine woke up via the RTC alarm and immediately request a
#     clean shutdown via systemctl.
#   * if the system came back early we simply clear the alarm so it
#     won't fire later and remove the marker file.
#
# To install, copy this file to /usr/lib/systemd/system-sleep/ or
# /etc/systemd/system-sleep/ and ensure it is executable.  It runs as
# root during suspend/resume.

set -euo pipefail

# path for log file; root should be able to write here
LOGFILE="/var/log/steam-deck-smart-sleep.log"

# how many seconds after suspend to schedule the RTC alarm
# value embedded by the installer at install time
WAKE_DELAY=30

# helper for appending timestamped messages to log
log_msg() {
    local msg="$*"
    printf '%s %s\n' "$(date --iso-8601=seconds)" "$msg" >> "$LOGFILE" 2>/dev/null || true
}

TMPMARK="/run/rtc_shutdown_wake"   # tmpfs, removed on reboot
RTCWAKE="/sys/class/rtc/rtc0/wakealarm"

schedule_alarm() {
    # clear any existing value first
    echo 0 > "$RTCWAKE"

    # compute the epoch timestamp WAKE_DELAY seconds from now
    local when
    when=$(date +%s --date="+$WAKE_DELAY seconds")
    echo "$when" > "$TMPMARK"

    log_msg "scheduled wakeup at $when (delay=$WAKE_DELAY)"

    # program the RTC (use -t to write absolute time)
    # rtcwake with "no" mode only sets the alarm, it does not
    # actually suspend the machine; systemd will handle the actual
    # sleep.
    # ensure rtcwake is available at expected location
    if [ ! -x "/usr/bin/rtcwake" ]; then
        log_msg "rtcwake not found at /usr/bin/rtcwake"
        echo "rtcwake not found at /usr/bin/rtcwake" >&2
        return 1
    fi
    /usr/bin/rtcwake -m no -t "$when" >/dev/null 2>&1
}

clear_alarm() {
    echo 0 > "$RTCWAKE" || true
    log_msg "cleared RTC alarm"
}

handle_pre() {
    log_msg "handling pre-sleep"
    schedule_alarm
}

handle_post() {
    log_msg "handling post-sleep"
    if [ -f "$TMPMARK" ]; then
        local scheduled now
        scheduled=$(cat "$TMPMARK")
        rm -f "$TMPMARK"
        now=$(date +%s)

        log_msg "wake time was $scheduled, now is $now"

        if [ "$now" -ge "$scheduled" ]; then
            # timer elapsed while we were asleep; initiate shutdown
            log_msg "timer elapsed, initiating shutdown sequence"
            /usr/bin/systemctl cancel
            /usr/bin/systemctl poweroff 2>&1 | tee -a "$LOGFILE"
        else
            # woke early; cancel the alarm so it doesn't fire later
            log_msg "woke early, cancelling alarm"
            clear_alarm
        fi
    else
        log_msg "no marker file; nothing to do"
    fi
}

case "${1:-}" in
    pre)
        handle_pre
        ;;
    post)
        handle_post
        ;;
    *)
        echo "Usage: $0 {pre|post}" >&2
        exit 1
        ;;
esac
