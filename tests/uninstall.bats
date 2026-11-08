#!/usr/bin/env bats
# Tests for uninstall.sh.  Everything runs against a scratch root with
# stubbed steamos-readonly / systemctl / rtcwake; the real system is never
# touched.  (Never remove the systemctl or rtcwake stubs: the real ones exist.)

REPO="$BATS_TEST_DIRNAME/.."

setup() {
    T="$BATS_TEST_TMPDIR"
    export CALLS="$T/calls"
    : > "$CALLS"

    mkdir -p "$T/bin"
    for c in steamos-readonly systemctl chown rtcwake; do
        cat > "$T/bin/$c" <<STUB
#!/bin/bash
echo "$c \$*" >> "\$CALLS"
if [ "\${FAIL_${c//-/_}:-}" = "\$1" ] || [ "\${FAIL_${c//-/_}:-}" = all ]; then exit 1; fi
exit 0
STUB
        chmod +x "$T/bin/$c"
    done

    export PATH="$T/bin:$PATH"
    export HOME="$T/home"
    export SDSS_EUID=0
    export SDSS_TARGET_DIR="$T/sys/system-sleep"
    export SDSS_SYSTEMD_DIR="$T/sys/systemd"
    export SDSS_MARKER="$T/marker"
    export SDSS_LOGFILE="$T/log"
    export SDSS_RTCWAKE="$T/bin/rtcwake"
    export SDSS_USE_LOCAL=1
    export SDSS_SCRIPT_DIR="$REPO"
    mkdir -p "$HOME"
}

uninst() { bash "$REPO/uninstall.sh"; }

# Install into the scratch root, leave a runtime marker and logs behind.
do_install() {
    bash "$REPO/install.sh" >/dev/null
    echo 123 > "$SDSS_MARKER"
    echo line > "$SDSS_LOGFILE"
    echo old > "$SDSS_LOGFILE.1"
    : > "$CALLS"
}

@test "refuses to run as non-root" {
    SDSS_EUID=1000 run uninst
    [ "$status" -eq 1 ]
    [[ "$output" == *"must be run as root"* ]]
    [ ! -s "$CALLS" ]
}

@test "removes the hook, units, marker and log but keeps the home files" {
    do_install
    echo precious > "$HOME/steam-deck-smart-sleep/my-notes.txt"
    run uninst
    [ "$status" -eq 0 ]
    [ ! -e "$SDSS_TARGET_DIR/steam-deck-smart-sleep.sh" ]
    [ ! -L "$SDSS_TARGET_DIR/steam-deck-smart-sleep.sh" ]
    [ ! -L "$SDSS_SYSTEMD_DIR/steam-deck-smart-sleep-installer.service" ]
    [ ! -L "$SDSS_SYSTEMD_DIR/steam-deck-smart-sleep-installer.timer" ]
    [ ! -e "$SDSS_MARKER" ]
    [ ! -e "$SDSS_LOGFILE" ]
    [ ! -e "$SDSS_LOGFILE.1" ]
    # home directory untouched
    d="$HOME/steam-deck-smart-sleep"
    [ -f "$d/install.sh" ]
    [ -f "$d/steam-deck-smart-sleep.sh" ]
    [ -f "$d/steam-deck-smart-sleep-installer.service" ]
    [ -f "$d/steam-deck-smart-sleep-installer.timer" ]
    [ "$(cat "$d/my-notes.txt")" = precious ]
    [[ "$output" == *"left in place"* ]]
}

@test "stops the timer before touching files, and brackets removal with read-only toggles" {
    do_install
    run uninst
    mapfile -t lines < "$CALLS"
    all="${lines[*]}"
    [[ "$all" == *"systemctl disable --now steam-deck-smart-sleep-installer.timer"*"steamos-readonly disable"*"steamos-readonly enable"*"systemctl daemon-reload"* ]]
    grep -q "systemctl stop steam-deck-smart-sleep-installer.service" "$CALLS"
    grep -q "rtcwake -m disable" "$CALLS"
}

@test "running it twice is harmless and the second run leaves read-only alone" {
    do_install
    uninst >/dev/null
    : > "$CALLS"
    run uninst
    [ "$status" -eq 0 ]
    [[ "$output" == *"No installed hook or units found"* ]]
    ! grep -q steamos-readonly "$CALLS"
    ! grep -q daemon-reload "$CALLS"
}

@test "copes with units that are not enabled or running" {
    do_install
    FAIL_systemctl=all run uninst
    [[ "$output" == *"timer was not enabled"* ]]
    [[ "$output" == *"service was not running"* ]]
}

@test "a failing reset-failed is ignored" {
    do_install
    FAIL_systemctl=reset-failed run uninst
    [ "$status" -eq 0 ]
}

@test "a dangling symlink still counts as installed" {
    do_install
    rm "$HOME/steam-deck-smart-sleep/steam-deck-smart-sleep.sh"
    [ -L "$SDSS_TARGET_DIR/steam-deck-smart-sleep.sh" ]
    run uninst
    [ "$status" -eq 0 ]
    [ ! -L "$SDSS_TARGET_DIR/steam-deck-smart-sleep.sh" ]
}

@test "removes only what exists when the install was partial" {
    mkdir -p "$SDSS_TARGET_DIR"
    echo hook > "$SDSS_TARGET_DIR/steam-deck-smart-sleep.sh"
    run uninst
    [ "$status" -eq 0 ]
    [ ! -e "$SDSS_TARGET_DIR/steam-deck-smart-sleep.sh" ]
    [[ "$output" == *"Removing $SDSS_TARGET_DIR/steam-deck-smart-sleep.sh"* ]]
    ! [[ "$output" == *"Removing $SDSS_SYSTEMD_DIR"* ]]
}

@test "does not complain when rtcwake is missing" {
    do_install
    SDSS_RTCWAKE="$T/missing" run uninst
    [ "$status" -eq 0 ]
    ! grep -q rtcwake "$CALLS"
}

@test "reports an RTC alarm that cannot be cleared but carries on" {
    do_install
    FAIL_rtcwake=all run uninst
    [ "$status" -eq 0 ]
    [[ "$output" == *"could not clear the RTC alarm"* ]]
    [ ! -e "$SDSS_MARKER" ]
}

@test "works without steamos-readonly" {
    do_install
    rm "$T/bin/steamos-readonly"
    run uninst
    [ "$status" -eq 0 ]
    [[ "$output" == *"steamos-readonly not found"* ]]
    [ ! -L "$SDSS_TARGET_DIR/steam-deck-smart-sleep.sh" ]
}

@test "a failure while removing still restores read-only" {
    do_install
    rm "$SDSS_TARGET_DIR/steam-deck-smart-sleep.sh"
    mkdir -p "$SDSS_TARGET_DIR/steam-deck-smart-sleep.sh/sub"   # rm -f cannot remove a directory
    run uninst
    [ "$status" -ne 0 ]
    grep -q "steamos-readonly disable" "$CALLS"
    grep -q "steamos-readonly enable" "$CALLS"
}

@test "reports when read-only cannot be restored after a failure" {
    do_install
    rm "$SDSS_TARGET_DIR/steam-deck-smart-sleep.sh"
    mkdir -p "$SDSS_TARGET_DIR/steam-deck-smart-sleep.sh/sub"
    FAIL_steamos_readonly=enable run uninst
    [ "$status" -ne 0 ]
    [[ "$output" == *"could not re-enable the read-only filesystem"* ]]
}

@test "fails loudly when read-only cannot be restored on the normal path" {
    do_install
    FAIL_steamos_readonly=enable run uninst
    [ "$status" -ne 0 ]
}

@test "sourcing the uninstaller does not run it" {
    do_install
    run bash -c 'source "$1"' _ "$REPO/uninstall.sh"
    [ "$status" -eq 0 ]
    [ -L "$SDSS_TARGET_DIR/steam-deck-smart-sleep.sh" ]
}

@test "end to end: piped into bash (curl | bash)" {
    [ -z "${SDSS_COVERAGE:-}" ] || skip "kcov cannot follow a piped entry point"
    do_install
    run bash -c 'cat "$1" | bash' _ "$REPO/uninstall.sh"
    [ "$status" -eq 0 ]
    [ ! -L "$SDSS_TARGET_DIR/steam-deck-smart-sleep.sh" ]
}
