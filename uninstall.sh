#!/bin/bash
# uninstall.sh
#
# Removes everything install.sh put on the system: the boot timer and
# service, the sleep hook, and the hook's runtime state (pending RTC alarm,
# marker file, log).  The files under ~/steam-deck-smart-sleep are left alone.
#
# Usage (as root on your Steam Deck):
#   sudo bash uninstall.sh
#   curl -fsSL https://raw.githubusercontent.com/sandro-sikic/steam-deck-smart-sleep/main/uninstall.sh | sudo bash
#
# Safe to run more than once.

set -euo pipefail

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
# The SDSS_* variables exist so the test suite can run the uninstaller against
# a scratch directory; the defaults are the real system locations.

TARGET_DIR="${SDSS_TARGET_DIR:-/usr/lib/systemd/system-sleep}"
SYSTEMD_DIR="${SDSS_SYSTEMD_DIR:-/etc/systemd/system}"
MARKER="${SDSS_MARKER:-/run/rtc_shutdown_wake}"
RTCWAKE="${SDSS_RTCWAKE:-/usr/bin/rtcwake}"
LOGFILE="${SDSS_LOGFILE:-/var/log/steam-deck-smart-sleep.log}"

SERVICE_UNIT="steam-deck-smart-sleep-installer.service"
TIMER_UNIT="steam-deck-smart-sleep-installer.timer"

# The files on the (normally read-only) root filesystem that we remove.
SYSTEM_FILES=("$TARGET_DIR/steam-deck-smart-sleep.sh" "$SYSTEMD_DIR/$SERVICE_UNIT" "$SYSTEMD_DIR/$TIMER_UNIT")

# Set when we have switched the root filesystem to read-write, so the EXIT
# trap knows it has to switch it back.
READONLY_DISABLED=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

info()  { printf '[INFO]  %s\n' "$*"; }
error() { printf '[ERROR] %s\n' "$*" >&2; }

# Runs on every exit: if we left the filesystem writable (because something
# failed half way), lock it again.
cleanup() {
    local rc=$?
    if [ "$READONLY_DISABLED" -eq 1 ]; then
        READONLY_DISABLED=0
        steamos-readonly enable || error "could not re-enable the read-only filesystem"
    fi
    return "$rc"
}

# True when PATH exists, even as a dangling symlink.
exists() {
    [ -e "$1" ] || [ -L "$1" ]
}

disable_readonly() {
    if command -v steamos-readonly >/dev/null 2>&1; then
        info "Disabling SteamOS read-only filesystem..."
        steamos-readonly disable
        READONLY_DISABLED=1
    else
        info "steamos-readonly not found; assuming a writable root filesystem."
    fi
}

enable_readonly() {
    if [ "$READONLY_DISABLED" -eq 1 ]; then
        info "Re-enabling SteamOS read-only filesystem..."
        READONLY_DISABLED=0
        steamos-readonly enable
    fi
}

# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------

# Stop the boot timer first so nothing can reinstall the hook while we remove
# it.  Each step tolerates a unit that is not installed.
stop_units() {
    info "Disabling and stopping $TIMER_UNIT..."
    systemctl disable --now "$TIMER_UNIT" 2>/dev/null || info "  timer was not enabled"
    systemctl stop "$SERVICE_UNIT" 2>/dev/null || info "  service was not running"
}

remove_system_files() {
    local f present=0
    for f in "${SYSTEM_FILES[@]}"; do
        if exists "$f"; then
            present=1
        fi
    done
    if [ "$present" -eq 0 ]; then
        info "No installed hook or units found."
        return 0
    fi

    disable_readonly
    for f in "${SYSTEM_FILES[@]}"; do
        if exists "$f"; then
            info "Removing $f"
            rm -f "$f"
        fi
    done
    enable_readonly

    info "Reloading systemd daemon..."
    systemctl daemon-reload
    systemctl reset-failed "$SERVICE_UNIT" 2>/dev/null || true
}

# Drop the hook's runtime state so a stale alarm cannot wake the device later.
clear_runtime_state() {
    if [ -x "$RTCWAKE" ]; then
        "$RTCWAKE" -m disable >/dev/null 2>&1 || info "  could not clear the RTC alarm"
    fi
    rm -f "$MARKER" "$LOGFILE" "$LOGFILE.1"
    info "Cleared the RTC alarm, marker file and log."
}

main() {
    if [ "${SDSS_EUID:-$EUID}" -ne 0 ]; then
        error "This script must be run as root."
        error "Try: sudo bash $0"
        return 1
    fi

    trap cleanup EXIT
    stop_units
    remove_system_files
    clear_runtime_state
    info "Uninstalled. Your files in ~/steam-deck-smart-sleep were left in place;"
    info "delete that directory yourself if you no longer want them."
}

# Only run when executed (or piped into bash), so the tests can source the
# functions.  Under `curl | bash` BASH_SOURCE[0] is empty.
if [ -z "${BASH_SOURCE[0]:-}" ] || [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
