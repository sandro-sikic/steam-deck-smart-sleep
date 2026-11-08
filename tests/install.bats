#!/usr/bin/env bats
# Tests for install.sh.  The installer runs against a scratch root: HOME, the
# system-sleep and systemd directories live under $BATS_TEST_TMPDIR, and
# steamos-readonly / systemctl / chown / getent are stubs earlier on PATH.
# Nothing here touches the real system.

REPO="$BATS_TEST_DIRNAME/.."

setup() {
    T="$BATS_TEST_TMPDIR"
    export CALLS="$T/calls"
    : > "$CALLS"

    # a pretend local clone
    SRC="$T/src"
    mkdir -p "$SRC"
    cp "$REPO"/install.sh "$REPO"/uninstall.sh "$REPO"/steam-deck-smart-sleep.sh \
       "$REPO"/steam-deck-smart-sleep-installer.service \
       "$REPO"/steam-deck-smart-sleep-installer.timer "$SRC/"

    # stub commands
    mkdir -p "$T/bin"
    for c in steamos-readonly systemctl chown; do
        cat > "$T/bin/$c" <<STUB
#!/bin/bash
echo "$c \$*" >> "\$CALLS"
if [ "\${FAIL_${c//-/_}:-}" = "\$1" ]; then exit 1; fi
exit 0
STUB
        chmod +x "$T/bin/$c"
    done
    cat > "$T/bin/getent" <<'STUB'
#!/bin/bash
printf '%s\n' "${GETENT_OUT:-}"
STUB
    chmod +x "$T/bin/getent"

    export PATH="$T/bin:$PATH"
    export HOME="$T/home"
    export SDSS_EUID=0
    export SDSS_TARGET_DIR="$T/sys/system-sleep"
    export SDSS_SYSTEMD_DIR="$T/sys/systemd"
    export SDSS_GITHUB_RAW="file://$SRC"
    export TMPDIR="$T/tmp"
    export SDSS_SCRIPT_DIR="$SRC"
    export SDSS_USE_LOCAL=1   # tests opt in to downloading
    unset SUDO_USER
    mkdir -p "$HOME" "$TMPDIR"
}

# Run the repo's installer against the fake clone in $SRC.
inst() { bash "$REPO/install.sh"; }

skip_if_coverage() {
    [ -z "${SDSS_COVERAGE:-}" ] || skip "kcov cannot follow a piped/real entry point"
}

@test "refuses to run as non-root" {
    SDSS_EUID=1000 run inst
    [ "$status" -eq 1 ]
    [[ "$output" == *"must be run as root"* ]]
    [ ! -e "$HOME/steam-deck-smart-sleep" ]
}

@test "fresh install from a local clone" {
    run inst
    [ "$status" -eq 0 ]
    d="$HOME/steam-deck-smart-sleep"
    [ -x "$d/steam-deck-smart-sleep.sh" ]
    [ "$(stat -c %a "$d/install.sh")" = 755 ]
    [ "$(stat -c %a "$d/uninstall.sh")" = 755 ]
    [[ "$output" == *"To uninstall it later (works offline):"* ]]
    [[ "$output" == *"sudo $d/uninstall.sh"* ]]
    [[ "$output" == *"curl -fsSL file://$SRC/uninstall.sh | sudo bash"* ]]
    [[ "$output" == *"Your files in $d are kept;"* ]]
    [ "$(stat -c %a "$d/steam-deck-smart-sleep-installer.service")" = 644 ]
    [ "$(readlink "$SDSS_TARGET_DIR/steam-deck-smart-sleep.sh")" = "$d/steam-deck-smart-sleep.sh" ]
    [ "$(readlink "$SDSS_SYSTEMD_DIR/steam-deck-smart-sleep-installer.service")" = "$d/steam-deck-smart-sleep-installer.service" ]
    [ "$(readlink "$SDSS_SYSTEMD_DIR/steam-deck-smart-sleep-installer.timer")" = "$d/steam-deck-smart-sleep-installer.timer" ]
    grep -q "^ExecStart=$d/install.sh$" "$d/steam-deck-smart-sleep-installer.service"
    grep -qxF "Environment=\"SDSS_INSTALL_DIR=$d\"" "$d/steam-deck-smart-sleep-installer.service"
    ! grep -q __INSTALL_DIR__ "$d/steam-deck-smart-sleep-installer.service"
    [ ! -e "$d/install.sh.new" ]
    ! grep -q __INSTALL_SCRIPT__ "$d/steam-deck-smart-sleep-installer.service"
    # read-only is lifted only around the system changes, then restored
    mapfile -t lines < "$CALLS"
    [[ "${lines[*]}" == *"steamos-readonly disable"*"steamos-readonly enable"*"systemctl daemon-reload"*"systemctl enable --now steam-deck-smart-sleep-installer.timer"* ]]
}

@test "the boot re-run from the installed copy works and changes nothing" {
    inst
    : > "$CALLS"
    SDSS_SCRIPT_DIR="$HOME/steam-deck-smart-sleep" run inst
    [ "$status" -eq 0 ]
    [[ "$output" == *"Already installed"* ]]
    ! grep -q steamos-readonly "$CALLS"
    ! grep -q systemctl "$CALLS"
}

@test "the boot re-run restores a hook wiped by an OS update" {
    inst
    rm "$SDSS_TARGET_DIR/steam-deck-smart-sleep.sh"
    : > "$CALLS"
    SDSS_SCRIPT_DIR="$HOME/steam-deck-smart-sleep" run inst
    [ "$status" -eq 0 ]
    [ -L "$SDSS_TARGET_DIR/steam-deck-smart-sleep.sh" ]
    grep -q "steamos-readonly disable" "$CALLS"
    grep -q "steamos-readonly enable" "$CALLS"
}

@test "a real file in the hook location is replaced by the symlink" {
    mkdir -p "$SDSS_TARGET_DIR"
    echo old > "$SDSS_TARGET_DIR/steam-deck-smart-sleep.sh"
    run inst
    [ "$status" -eq 0 ]
    [ -L "$SDSS_TARGET_DIR/steam-deck-smart-sleep.sh" ]
}

@test "without a local clone the files are downloaded and temp files removed" {
    mv "$SRC" "$T/remote"
    export SDSS_GITHUB_RAW="file://$T/remote"
    unset SDSS_USE_LOCAL
    SDSS_SCRIPT_DIR="" run inst
    [ "$status" -eq 0 ]
    [[ "$output" == *"Downloading install.sh"* ]]
    [ -L "$SDSS_TARGET_DIR/steam-deck-smart-sleep.sh" ]
    [ -z "$(ls -A "$TMPDIR")" ]
}

@test "end to end: cat install.sh | bash" {
    skip_if_coverage
    mv "$SRC" "$T/remote"
    export SDSS_GITHUB_RAW="file://$T/remote"
    unset SDSS_SCRIPT_DIR SDSS_USE_LOCAL
    run bash -c 'cat "$1" | bash' _ "$REPO/install.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Downloading install.sh"* ]]
    [ -L "$SDSS_TARGET_DIR/steam-deck-smart-sleep.sh" ]
}

@test "end to end: a non-regular script path (process substitution)" {
    skip_if_coverage
    unset SDSS_SCRIPT_DIR SDSS_USE_LOCAL
    run bash <(cat "$REPO/install.sh")
    [ "$status" -eq 0 ]
    [[ "$output" == *"Downloading install.sh"* ]]
}

@test "end to end: the script locates its own clone" {
    unset SDSS_SCRIPT_DIR
    run inst
    [ "$status" -eq 0 ]
    [ -L "$SDSS_TARGET_DIR/steam-deck-smart-sleep.sh" ]
    [[ "$output" == *"Using local files"* ]]
}

@test "end to end: the installed copy re-runs cleanly on boot" {
    skip_if_coverage
    inst
    unset SDSS_SCRIPT_DIR
    run bash "$HOME/steam-deck-smart-sleep/install.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Already installed"* ]]
}

@test "downloads by default, even when a complete local copy exists" {
    cp -r "$SRC" "$T/remote"
    echo "# from github" >> "$T/remote/steam-deck-smart-sleep.sh"
    export SDSS_GITHUB_RAW="file://$T/remote"
    unset SDSS_USE_LOCAL
    run inst
    [ "$status" -eq 0 ]
    [[ "$output" == *"Fetching the latest version"* ]]
    grep -q "# from github" "$HOME/steam-deck-smart-sleep/steam-deck-smart-sleep.sh"
    [ -z "$(ls -A "$TMPDIR")" ]
}

@test "falls back to the local copy when the download fails" {
    echo "# local" >> "$SRC/steam-deck-smart-sleep.sh"
    export SDSS_GITHUB_RAW="file://$T/nowhere"
    unset SDSS_USE_LOCAL
    run inst
    [ "$status" -eq 0 ]
    [[ "$output" == *"download failed; falling back to local files"* ]]
    [[ "$output" == *"Using local files"* ]]
    grep -q "# local" "$HOME/steam-deck-smart-sleep/steam-deck-smart-sleep.sh"
    [ -z "$(ls -A "$TMPDIR")" ]
}

@test "an empty download counts as a failure" {
    cp -r "$SRC" "$T/remote"
    : > "$T/remote/steam-deck-smart-sleep-installer.timer"
    export SDSS_GITHUB_RAW="file://$T/remote"
    unset SDSS_USE_LOCAL
    run inst
    [ "$status" -eq 0 ]
    [[ "$output" == *"falling back to local files"* ]]
    [ -s "$HOME/steam-deck-smart-sleep/steam-deck-smart-sleep-installer.timer" ]
}

@test "SDSS_USE_LOCAL=1 never downloads" {
    export SDSS_GITHUB_RAW="file://$T/nowhere"
    run inst
    [ "$status" -eq 0 ]
    ! [[ "$output" == *"Fetching"* ]]
    ! [[ "$output" == *"download failed"* ]]
}

@test "aborts before touching anything when there is neither a download nor a complete local copy" {
    rm "$SRC/steam-deck-smart-sleep-installer.timer"
    export SDSS_GITHUB_RAW="file://$T/nowhere"
    unset SDSS_USE_LOCAL
    run inst
    [ "$status" -eq 1 ]
    [[ "$output" == *"no usable source files"* ]]
    ! grep -q steamos-readonly "$CALLS"
    [ -z "$(ls -A "$TMPDIR")" ]
}

@test "aborts when run via curl | bash and GitHub is unreachable" {
    export SDSS_GITHUB_RAW="file://$T/nowhere"
    unset SDSS_USE_LOCAL
    SDSS_SCRIPT_DIR="" run inst
    [ "$status" -eq 1 ]
    [[ "$output" == *"<none>"* ]]
}

@test "uses the home of the sudo user" {
    export SUDO_USER=deck
    export GETENT_OUT="deck:x:1000:1000::$T/deckhome:/bin/bash"
    mkdir -p "$T/deckhome"
    run inst
    [ "$status" -eq 0 ]
    [ -d "$T/deckhome/steam-deck-smart-sleep" ]
}

@test "fails when the sudo user has no home" {
    export SUDO_USER=ghost
    export GETENT_OUT=""
    run inst
    [ "$status" -eq 1 ]
    [[ "$output" == *"could not determine the home directory"* ]]
}

@test "SUDO_USER=root falls back to HOME" {
    export SUDO_USER=root
    run inst
    [ "$status" -eq 0 ]
    [ -d "$HOME/steam-deck-smart-sleep" ]
}

@test "works without steamos-readonly" {
    rm "$T/bin/steamos-readonly"
    run inst
    [ "$status" -eq 0 ]
    [[ "$output" == *"steamos-readonly not found"* ]]
    [ -L "$SDSS_TARGET_DIR/steam-deck-smart-sleep.sh" ]
}

@test "special characters in the home path survive the unit substitution" {
    export HOME="$T/we&ird|dir\\x"
    mkdir -p "$HOME"
    run inst
    [ "$status" -eq 0 ]
    grep -qxF "ExecStart=$HOME/steam-deck-smart-sleep/install.sh" \
        "$HOME/steam-deck-smart-sleep/steam-deck-smart-sleep-installer.service"
}

@test "a failure mid-install still re-enables read-only" {
    touch "$T/blocker"
    export SDSS_SYSTEMD_DIR="$T/blocker/systemd"   # mkdir will fail
    run inst
    [ "$status" -ne 0 ]
    grep -q "steamos-readonly disable" "$CALLS"
    grep -q "steamos-readonly enable" "$CALLS"
}

@test "reports when read-only cannot be restored after a failure" {
    touch "$T/blocker"
    export SDSS_SYSTEMD_DIR="$T/blocker/systemd"
    FAIL_steamos_readonly=enable run inst
    [ "$status" -ne 0 ]
    [[ "$output" == *"could not re-enable the read-only filesystem"* ]]
}

@test "fails loudly when read-only cannot be restored on the normal path" {
    FAIL_steamos_readonly=enable run inst
    [ "$status" -ne 0 ]
}

@test "sourcing the installer does not run it" {
    run bash -c 'source "$1"' _ "$REPO/install.sh"
    [ "$status" -eq 0 ]
    [ ! -e "$HOME/steam-deck-smart-sleep" ]
}

# --------------------------------------------- boot run (no $HOME under systemd)

@test "fails clearly when neither HOME nor SDSS_INSTALL_DIR is available" {
    run env -u HOME bash "$REPO/install.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"HOME is not set"* ]]
}

@test "SDSS_INSTALL_DIR is used when HOME is unset" {
    SDSS_INSTALL_DIR="$T/elsewhere" run env -u HOME bash "$REPO/install.sh"
    [ "$status" -eq 0 ]
    [ -x "$T/elsewhere/steam-deck-smart-sleep.sh" ]
}

@test "end to end: the boot service environment reinstalls with no HOME and fetches the latest files" {
    skip_if_coverage
    inst >/dev/null
    d="$HOME/steam-deck-smart-sleep"
    # exactly what systemd would pass to ExecStart
    unit_env=$(sed -n 's/^Environment="\(.*\)"$/\1/p' "$d/steam-deck-smart-sleep-installer.service")
    exec_start=$(sed -n 's/^ExecStart=//p' "$d/steam-deck-smart-sleep-installer.service")
    # an OS update wipes the hook; GitHub has a newer version
    rm "$SDSS_TARGET_DIR/steam-deck-smart-sleep.sh"
    cp -r "$SRC" "$T/remote"
    echo "# newer" >> "$T/remote/steam-deck-smart-sleep.sh"
    : > "$CALLS"
    run env -i PATH="$PATH" CALLS="$CALLS" SDSS_EUID=0 SDSS_TARGET_DIR="$SDSS_TARGET_DIR" \
        SDSS_SYSTEMD_DIR="$SDSS_SYSTEMD_DIR" SDSS_GITHUB_RAW="file://$T/remote" \
        TMPDIR="$TMPDIR" "$unit_env" bash "$exec_start"
    [ "$status" -eq 0 ]
    [ -L "$SDSS_TARGET_DIR/steam-deck-smart-sleep.sh" ]
    grep -q "# newer" "$d/steam-deck-smart-sleep.sh"
    grep -q "steamos-readonly enable" "$CALLS"
}

@test "end to end: the boot service falls back to the installed files when offline" {
    skip_if_coverage
    inst >/dev/null
    d="$HOME/steam-deck-smart-sleep"
    unit_env=$(sed -n 's/^Environment="\(.*\)"$/\1/p' "$d/steam-deck-smart-sleep-installer.service")
    rm "$SDSS_TARGET_DIR/steam-deck-smart-sleep.sh"
    run env -i PATH="$PATH" CALLS="$CALLS" SDSS_EUID=0 SDSS_TARGET_DIR="$SDSS_TARGET_DIR" \
        SDSS_SYSTEMD_DIR="$SDSS_SYSTEMD_DIR" SDSS_GITHUB_RAW="file://$T/nowhere" \
        TMPDIR="$TMPDIR" "$unit_env" bash "$d/install.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"falling back to local files"* ]]
    [ -L "$SDSS_TARGET_DIR/steam-deck-smart-sleep.sh" ]
}

# ------------------------------------------------- optional offline uninstaller

@test "uninstall.sh is downloaded alongside the required files" {
    cp -r "$SRC" "$T/remote"
    rm "$SRC/uninstall.sh"
    export SDSS_GITHUB_RAW="file://$T/remote"
    unset SDSS_USE_LOCAL
    run inst
    [ "$status" -eq 0 ]
    [ -x "$HOME/steam-deck-smart-sleep/uninstall.sh" ]
    cmp "$HOME/steam-deck-smart-sleep/uninstall.sh" "$T/remote/uninstall.sh"
}

@test "a missing remote uninstall.sh does not stop the install" {
    cp -r "$SRC" "$T/remote"
    rm "$T/remote/uninstall.sh"
    export SDSS_GITHUB_RAW="file://$T/remote"
    unset SDSS_USE_LOCAL
    run inst
    [ "$status" -eq 0 ]
    [[ "$output" == *"uninstall.sh unavailable; skipping"* ]]
    [ ! -e "$HOME/steam-deck-smart-sleep/uninstall.sh" ]
    # no offline command, but the GitHub one is still shown
    ! [[ "$output" == *"works offline"* ]]
    [[ "$output" == *"To uninstall it later, run:"* ]]
    [[ "$output" == *"| sudo bash"* ]]
    [ -L "$SDSS_TARGET_DIR/steam-deck-smart-sleep.sh" ]
}

@test "an empty remote uninstall.sh is skipped, keeping an existing copy" {
    mkdir -p "$HOME/steam-deck-smart-sleep"
    echo "# existing" > "$HOME/steam-deck-smart-sleep/uninstall.sh"
    cp -r "$SRC" "$T/remote"
    : > "$T/remote/uninstall.sh"
    export SDSS_GITHUB_RAW="file://$T/remote"
    unset SDSS_USE_LOCAL
    run inst
    [ "$status" -eq 0 ]
    grep -q "# existing" "$HOME/steam-deck-smart-sleep/uninstall.sh"
}

@test "the local fallback copies uninstall.sh when present, and works without it" {
    run inst
    [ -x "$HOME/steam-deck-smart-sleep/uninstall.sh" ]
    rm -rf "$HOME/steam-deck-smart-sleep" "$SDSS_TARGET_DIR" "$SDSS_SYSTEMD_DIR"
    rm "$SRC/uninstall.sh"
    run inst
    [ "$status" -eq 0 ]
    [ ! -e "$HOME/steam-deck-smart-sleep/uninstall.sh" ]
}

@test "end to end: the copied uninstall.sh removes the install offline" {
    skip_if_coverage
    inst >/dev/null
    export SDSS_MARKER="$T/marker" SDSS_LOGFILE="$T/log" SDSS_RTCWAKE="$T/bin/rtcwake"
    printf '#!/bin/bash\nexit 0\n' > "$T/bin/rtcwake"; chmod +x "$T/bin/rtcwake"
    run bash "$HOME/steam-deck-smart-sleep/uninstall.sh"
    [ "$status" -eq 0 ]
    [ ! -L "$SDSS_TARGET_DIR/steam-deck-smart-sleep.sh" ]
    [ ! -L "$SDSS_SYSTEMD_DIR/steam-deck-smart-sleep-installer.timer" ]
    [ -f "$HOME/steam-deck-smart-sleep/install.sh" ]
}

@test "the uninstall help is shown after an install but not on an already-installed run" {
    run inst
    [ "$status" -eq 0 ]
    [[ "$output" == *"steam-deck-smart-sleep is installed."* ]]
    run inst
    [ "$status" -eq 0 ]
    [[ "$output" == *"Already installed"* ]]
    ! [[ "$output" == *"steam-deck-smart-sleep is installed."* ]]
}

@test "the uninstall help shows the sudo user's home, not root's" {
    export SUDO_USER=deck
    export GETENT_OUT="deck:x:1000:1000::$T/deckhome:/bin/bash"
    mkdir -p "$T/deckhome"
    run inst
    [[ "$output" == *"sudo $T/deckhome/steam-deck-smart-sleep/uninstall.sh"* ]]
}
