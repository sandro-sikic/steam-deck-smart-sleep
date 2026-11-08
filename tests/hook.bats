#!/usr/bin/env bats
# Unit tests for steam-deck-smart-sleep.sh.  Everything runs against stubs in
# $BATS_TEST_TMPDIR; nothing touches the real RTC, systemd or /sys.

SCRIPT="$BATS_TEST_DIRNAME/../steam-deck-smart-sleep.sh"

setup() {
    T="$BATS_TEST_TMPDIR"
    export SDSS_LOGFILE="$T/log"
    export SDSS_MARKER="$T/marker"
    export SDSS_RTCWAKE="$T/rtcwake"
    export SDSS_SYSTEMCTL="$T/systemctl"
    export SDSS_RTC_WAKEALARM="$T/wakealarm"
    export SDSS_POWER_SUPPLY_DIR="$T/ps"
    export SDSS_CONFIG="$T/smart-sleep.conf"   # absent unless a test writes it
    export CALLS="$T/calls"
    export NOW=1000
    mkdir -p "$T/ps"
    : > "$CALLS"
    make_stub rtcwake
    make_stub systemctl
}

# make_stub NAME: records its argv in $CALLS; fails when $FAIL_<NAME>_ON
# matches the first argument-pair ("-m no" -> "no") or is "all".
make_stub() {
    local name="$1"
    cat > "$T/$name" <<STUB
#!/bin/bash
echo "$name \$*" >> "\$CALLS"
mode="\$2"
fail="\$FAIL_${name^^}"
if [ "\$fail" = all ] || [ "\$fail" = "\$mode" ] || [ "\$fail" = "\$1" ]; then echo "stub failure" >&2; exit 1; fi
exit 0
STUB
    chmod +x "$T/$name"
}

# call FUNC [ARGS]: source the script, pin the clock, run FUNC.
call() {
    bash -c 'source "$1"; shift; now_epoch() { echo "$NOW"; }; "$@"' _ "$SCRIPT" "$@"
}

set_ac() { mkdir -p "$T/ps/$1"; echo "$2" > "$T/ps/$1/online"; }
set_bat() { mkdir -p "$T/ps/BAT0"; echo "$1" > "$T/ps/BAT0/status"; }

# ---------------------------------------------------------------- log_msg

@test "log_msg appends a timestamped line" {
    run call log_msg hello world
    [ "$status" -eq 0 ]
    grep -qE '^[0-9T:+-]+ hello world$' "$SDSS_LOGFILE"
}

@test "log_msg rotates an oversized log" {
    head -c 2000000 /dev/zero | tr '\0' x > "$SDSS_LOGFILE"
    run call log_msg after-rotate
    [ -f "$SDSS_LOGFILE.1" ]
    [ "$(wc -l < "$SDSS_LOGFILE")" -eq 1 ]
}

@test "log_msg survives an unwritable log" {
    export SDSS_LOGFILE="$T/no/such/dir/log"
    run call log_msg x
    [ "$status" -eq 0 ]
}

# ------------------------------------------------------------- config / delay

delay() { run --separate-stderr call effective_delay; }

@test "effective_delay is the default (3h) without a config file, silently" {
    delay
    [ "$output" = "10800" ]
    [ ! -e "$SDSS_LOGFILE" ]
}

@test "effective_delay converts the configured minutes to seconds" {
    echo "WAKE_DELAY_MINUTES=90" > "$SDSS_CONFIG"
    delay
    [ "$output" = "5400" ]
    [ ! -e "$SDSS_LOGFILE" ]
}

@test "the config tolerates comments, blank lines, trailing spaces and no final newline" {
    printf '# a comment\n\nWAKE_DELAY_MINUTES=45   ' > "$SDSS_CONFIG"
    delay
    [ "$output" = "2700" ]
}

@test "the last WAKE_DELAY_MINUTES line wins" {
    printf 'WAKE_DELAY_MINUTES=10\nWAKE_DELAY_MINUTES=20\n' > "$SDSS_CONFIG"
    delay
    [ "$output" = "1200" ]
}

@test "leading zeros are decimal, not octal" {
    echo "WAKE_DELAY_MINUTES=010" > "$SDSS_CONFIG"
    delay
    [ "$output" = "600" ]
}

@test "the limits 1 and 10080 minutes are accepted" {
    echo "WAKE_DELAY_MINUTES=1" > "$SDSS_CONFIG"
    delay
    [ "$output" = "60" ]
    echo "WAKE_DELAY_MINUTES=10080" > "$SDSS_CONFIG"
    delay
    [ "$output" = "604800" ]
}

@test "invalid values fall back to the default and are logged" {
    for bad in 0 10081 abc -5 1e3 "" "5 6" 99999999999999999999; do
        rm -f "$SDSS_LOGFILE"
        echo "WAKE_DELAY_MINUTES=$bad" > "$SDSS_CONFIG"
        delay
        [ "$output" = "10800" ]
        grep -q "no valid WAKE_DELAY_MINUTES" "$SDSS_LOGFILE"
    done
}

@test "an empty config file falls back to the default and is logged" {
    : > "$SDSS_CONFIG"
    delay
    [ "$output" = "10800" ]
    grep -q "no valid WAKE_DELAY_MINUTES" "$SDSS_LOGFILE"
}

@test "a config without the setting falls back to the default and is logged" {
    echo "# nothing here" > "$SDSS_CONFIG"
    delay
    [ "$output" = "10800" ]
    grep -q "no valid WAKE_DELAY_MINUTES" "$SDSS_LOGFILE"
}

@test "the config is parsed, never executed" {
    printf 'WAKE_DELAY_MINUTES=5; touch %s/pwned\n$(touch %s/pwned2)\n' "$T" "$T" > "$SDSS_CONFIG"
    delay
    [ "$output" = "10800" ]
    [ ! -e "$T/pwned" ] && [ ! -e "$T/pwned2" ]
}

@test "an unreadable config is treated as invalid" {
    if [ "$(id -u)" -eq 0 ]; then skip "root can read anything"; fi
    echo "WAKE_DELAY_MINUTES=90" > "$SDSS_CONFIG"; chmod 000 "$SDSS_CONFIG"
    delay
    [ "$output" = "10800" ]
}

@test "the config is found next to the real script, through the symlink the system uses" {
    mkdir -p "$T/home" "$T/sleepdir"
    cp "$SCRIPT" "$T/home/steam-deck-smart-sleep.sh"
    ln -s "$T/home/steam-deck-smart-sleep.sh" "$T/sleepdir/steam-deck-smart-sleep.sh"
    echo "WAKE_DELAY_MINUTES=30" > "$T/home/smart-sleep.conf"
    unset SDSS_CONFIG
    run --separate-stderr bash -c 'source "$1"; config_file; effective_delay' _ "$T/sleepdir/steam-deck-smart-sleep.sh"
    [ "${lines[0]}" = "$T/home/smart-sleep.conf" ]
    [ "${lines[1]}" = "1800" ]
}

@test "a config change applies to the next alarm without reinstalling" {
    echo "WAKE_DELAY_MINUTES=10" > "$SDSS_CONFIG"
    run call schedule_alarm
    [ "$(cat "$SDSS_MARKER")" = "1600" ]
    echo "WAKE_DELAY_MINUTES=20" > "$SDSS_CONFIG"
    run call schedule_alarm
    [ "$(cat "$SDSS_MARKER")" = "2200" ]
}

# --------------------------------------------------------------- clear_alarm

@test "clear_alarm uses rtcwake -m disable" {
    run call clear_alarm
    grep -q "rtcwake -m disable" "$CALLS"
    grep -q "cleared RTC alarm" "$SDSS_LOGFILE"
}

@test "clear_alarm logs when rtcwake disable fails" {
    FAIL_RTCWAKE=disable run call clear_alarm
    grep -q "rtcwake -m disable failed" "$SDSS_LOGFILE"
}

@test "clear_alarm falls back to the sysfs wakealarm" {
    export SDSS_RTCWAKE="$T/missing"
    echo 123 > "$SDSS_RTC_WAKEALARM"
    run call clear_alarm
    [ "$(cat "$SDSS_RTC_WAKEALARM")" = "0" ]
}

@test "clear_alarm logs when the sysfs fallback is unwritable" {
    export SDSS_RTCWAKE="$T/missing"
    export SDSS_RTC_WAKEALARM="$T/no/such/dir/wakealarm"
    run call clear_alarm
    grep -q "could not clear" "$SDSS_LOGFILE"
}

# ------------------------------------------------------------ schedule_alarm

@test "schedule_alarm writes marker and arms the alarm" {
    run call schedule_alarm
    [ "$status" -eq 0 ]
    [ "$(cat "$SDSS_MARKER")" = "11800" ]
    grep -q "rtcwake -m disable" "$CALLS"
    grep -q "rtcwake -m no -t 11800" "$CALLS"
}

@test "schedule_alarm ignores a failing initial disable" {
    FAIL_RTCWAKE=disable run call schedule_alarm
    [ "$status" -eq 0 ]
    [ -f "$SDSS_MARKER" ]
}

@test "schedule_alarm fails cleanly when rtcwake is missing" {
    export SDSS_RTCWAKE="$T/missing"
    run call schedule_alarm
    [ "$status" -eq 1 ]
    [ ! -e "$SDSS_MARKER" ]
    grep -q "rtcwake not found" "$SDSS_LOGFILE"
}

@test "schedule_alarm fails when the marker cannot be written" {
    export SDSS_MARKER="$T/no/such/dir/marker"
    run call schedule_alarm
    [ "$status" -eq 1 ]
    ! grep -q "rtcwake -m no" "$CALLS"
    grep -q "could not write marker" "$SDSS_LOGFILE"
}

@test "schedule_alarm removes the marker if arming fails" {
    FAIL_RTCWAKE=no run call schedule_alarm
    [ "$status" -eq 1 ]
    [ ! -e "$SDSS_MARKER" ]
    grep -q "failed to set the alarm" "$SDSS_LOGFILE"
}

# --------------------------------------------------------------- is_charging

@test "is_charging: AC online" {
    set_ac AC 1
    run call is_charging
    [ "$status" -eq 0 ]
}

@test "is_charging: ADP online" {
    set_ac ADP1 1
    run call is_charging
    [ "$status" -eq 0 ]
}

@test "is_charging: AC offline and battery discharging" {
    set_ac AC 0
    set_bat Discharging
    run call is_charging
    [ "$status" -eq 1 ]
}

@test "is_charging: battery Charging" {
    set_bat Charging
    run call is_charging
    [ "$status" -eq 0 ]
}

@test "is_charging: battery Full" {
    set_bat Full
    run call is_charging
    [ "$status" -eq 0 ]
}

@test "is_charging: nothing present" {
    run call is_charging
    [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------- handle_pre

@test "pre arms the alarm" {
    run call main pre suspend
    [ "$status" -eq 0 ]
    [ -f "$SDSS_MARKER" ]
}

@test "pre never fails even if the alarm cannot be set" {
    FAIL_RTCWAKE=no run call main pre suspend
    [ "$status" -eq 0 ]
    grep -q "will not auto-shutdown" "$SDSS_LOGFILE"
}

# --------------------------------------------------------------- handle_post

@test "post without a marker does nothing" {
    run call main post suspend
    [ "$status" -eq 0 ]
    grep -q "nothing to do" "$SDSS_LOGFILE"
    ! grep -q systemctl "$CALLS"
}

@test "post with a garbage marker clears the alarm" {
    echo oops > "$SDSS_MARKER"
    run call main post suspend
    [ "$status" -eq 0 ]
    [ ! -e "$SDSS_MARKER" ]
    grep -q "invalid marker" "$SDSS_LOGFILE"
    grep -q "rtcwake -m disable" "$CALLS"
}

@test "post with an unreadable marker is treated as invalid" {
    if [ "$(id -u)" -eq 0 ]; then skip "root can read anything"; fi
    echo 5 > "$SDSS_MARKER"; chmod 000 "$SDSS_MARKER"
    run call main post suspend
    grep -q "invalid marker" "$SDSS_LOGFILE"
}

@test "post woken early clears the alarm and does not sleep or poweroff" {
    echo 2000 > "$SDSS_MARKER"
    NOW=1500 run call main post suspend
    [ ! -e "$SDSS_MARKER" ]
    grep -q "woke early" "$SDSS_LOGFILE"
    grep -q "rtcwake -m disable" "$CALLS"
    ! grep -q systemctl "$CALLS"
}

@test "post after timer while not charging powers off without blocking" {
    echo 900 > "$SDSS_MARKER"
    set_bat Discharging
    run call main post suspend
    grep -q "^systemctl poweroff$" "$CALLS"
    [ ! -e "$SDSS_MARKER" ]
}

# Regression: the re-suspend only works if pending jobs are cancelled first,
# and plain (blocking) calls are used, exactly as in the original hook.
sysctl_calls() { grep '^systemctl ' "$CALLS"; }

@test "re-suspend cancels pending jobs first, then suspends, with no other systemctl calls" {
    echo 900 > "$SDSS_MARKER"
    set_ac AC 1
    run call main post suspend
    run sysctl_calls
    [ "${lines[0]}" = "systemctl cancel" ]
    [ "${lines[1]}" = "systemctl suspend" ]
    [ "${#lines[@]}" -eq 2 ]
}

@test "shutdown cancels pending jobs first, then powers off, with no other systemctl calls" {
    echo 900 > "$SDSS_MARKER"
    set_bat Discharging
    run call main post suspend
    run sysctl_calls
    [ "${lines[0]}" = "systemctl cancel" ]
    [ "${lines[1]}" = "systemctl poweroff" ]
    [ "${#lines[@]}" -eq 2 ]
}

@test "no systemctl call uses --no-block" {
    echo 900 > "$SDSS_MARKER"
    set_ac AC 1
    run call main post suspend
    ! grep -q -- "--no-block" "$CALLS"
}

@test "a failing cancel is logged but the suspend is still attempted" {
    echo 900 > "$SDSS_MARKER"
    set_ac AC 1
    FAIL_SYSTEMCTL=cancel run call main post suspend
    [ "$status" -eq 0 ]
    grep -q "systemctl cancel failed" "$SDSS_LOGFILE"
    grep -q "^systemctl suspend$" "$CALLS"
}

@test "post logs a failing poweroff" {
    echo 900 > "$SDSS_MARKER"
    FAIL_SYSTEMCTL=all run call main post suspend
    [ "$status" -eq 0 ]
    grep -q "systemctl poweroff failed" "$SDSS_LOGFILE"
}

@test "post after timer while charging re-arms and suspends" {
    echo 900 > "$SDSS_MARKER"
    set_ac AC 1
    run call main post suspend
    [ "$(cat "$SDSS_MARKER")" = "11800" ]
    grep -q "^systemctl suspend$" "$CALLS"
    ! grep -q poweroff "$CALLS"
}

@test "post while charging stays awake if re-arming fails" {
    echo 900 > "$SDSS_MARKER"
    set_ac AC 1
    FAIL_RTCWAKE=no run call main post suspend
    grep -q "staying awake" "$SDSS_LOGFILE"
    ! grep -q systemctl "$CALLS"
}

# ---------------------------------------------------------------------- main

@test "main rejects an unknown argument" {
    run call main bogus
    [ "$status" -eq 1 ]
    [[ "$output" == *Usage* ]]
}

@test "main rejects a missing argument" {
    run call main
    [ "$status" -eq 1 ]
}

@test "executing the script directly dispatches to main" {
    run bash "$SCRIPT" pre suspend
    [ "$status" -eq 0 ]
    [ -f "$SDSS_MARKER" ]
}

@test "sourcing the script does not run main" {
    run bash -c 'source "$1"' _ "$SCRIPT"
    [ "$status" -eq 0 ]
    [ ! -e "$SDSS_LOGFILE" ]
}
