#!/bin/bash
# install.sh
#
# Installer for the shutdown-after-sleep systemd sleep hook.
# The hook script and helper units live in sibling files alongside this
# installer; running the script copies them into ~/steam-deck-auto-off and creates
# symlinks from the system locations.
#
# Usage (once as root on your Steam Deck):
#   sudo bash install.sh
#
# After the first run the hook is installed and this script registers itself
# as a systemd boot timer so the installation is automatically re-applied
# after every SteamOS update (which resets the read-only root filesystem).

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration — adjust before running
# ---------------------------------------------------------------------------

# (wake delay is now fixed in the template script; edit
# shutdown-after-sleep.sh directly if you need to change it)

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-/tmp}")" && pwd 2>/dev/null || echo "/tmp")"
TARGET_DIR="/usr/lib/systemd/system-sleep"
TARGET_SCRIPT="$TARGET_DIR/shutdown-after-sleep.sh"

# Directory under the user's home where the real files will live. When the
# installer is invoked with sudo we prefer the invoking user's home rather
# than /root so that the files are easy to inspect and modify later.
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    USER_HOME="$HOME"
fi
SLEEP_FIX_DIR="$USER_HOME/steam-deck-auto-off"
HOOK_DEST="$SLEEP_FIX_DIR/$(basename "$TARGET_SCRIPT")"

# The systemd service always re-runs the persistent copy stored in SLEEP_FIX_DIR,
# regardless of how this script was originally invoked (local clone or curl pipe).
INSTALL_SCRIPT="$SLEEP_FIX_DIR/install.sh"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

info()  { printf '[INFO]  %s\n' "$*"; }
error() { printf '[ERROR] %s\n' "$*" >&2; }

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------

if [ "$EUID" -ne 0 ]; then
    error "This script must be run as root."
    error "Try: sudo bash $0"
    exit 1
fi

# ---------------------------------------------------------------------------
# Source files – download from GitHub when not running from a local clone
# ---------------------------------------------------------------------------
# When invoked via `curl | bash` the sibling files are not present on disk.
# Detect this and fetch them from GitHub into a temporary directory.

GITHUB_RAW="https://raw.githubusercontent.com/sandro-sikic/steam-deck-auto-off/main"
FILES_DIR="$SCRIPT_DIR"
TMP_DIR=""

_need_download=0
for _f in shutdown-after-sleep.sh \
          shutdown-after-sleep-installer.service \
          shutdown-after-sleep-installer.timer \
          install.sh; do
    [ -r "$SCRIPT_DIR/$_f" ] || { _need_download=1; break; }
done

if [ "$_need_download" -eq 1 ]; then
    TMP_DIR=$(mktemp -d)
    FILES_DIR="$TMP_DIR"
    info "Sibling files not found locally – downloading from GitHub..."
    for _f in shutdown-after-sleep.sh \
              shutdown-after-sleep-installer.service \
              shutdown-after-sleep-installer.timer \
              install.sh; do
        info "  Downloading $_f"
        curl -fsSL "$GITHUB_RAW/$_f" -o "$TMP_DIR/$_f"
    done
fi

_cleanup() {
    [ -n "$TMP_DIR" ] && rm -rf "$TMP_DIR"
}
trap _cleanup EXIT

# ---------------------------------------------------------------------------
# Write the hook script from the embedded heredoc
# ---------------------------------------------------------------------------

write_hook() {
    # Copy the templated hook script out of the installer directory into
    # the home storage area.
    if [ ! -r "$FILES_DIR/shutdown-after-sleep.sh" ]; then
        error "template hook script not found at $FILES_DIR/shutdown-after-sleep.sh"
        exit 1
    fi
    cp "$FILES_DIR/shutdown-after-sleep.sh" "$HOOK_DEST"
}

# ---------------------------------------------------------------------------
# Installation
# ---------------------------------------------------------------------------

info "Disabling SteamOS read-only filesystem..."
steamos-readonly disable

info "Creating home storage directory: $SLEEP_FIX_DIR"
mkdir -p "$SLEEP_FIX_DIR"

info "Persisting installer script -> $SLEEP_FIX_DIR/install.sh"
cp "$FILES_DIR/install.sh" "$SLEEP_FIX_DIR/install.sh"
chown root:root "$SLEEP_FIX_DIR/install.sh"
chmod 755 "$SLEEP_FIX_DIR/install.sh"

info "Creating target directory: $TARGET_DIR"  # required for the symlink
mkdir -p "$TARGET_DIR"

info "Writing shutdown-after-sleep.sh -> $HOOK_DEST"
write_hook

info "Setting ownership: root:root on $HOOK_DEST"
chown root:root "$HOOK_DEST"

info "Setting permissions: 755 (executable) on $HOOK_DEST"
chmod 755 "$HOOK_DEST"

# ensure the system location contains a symlink instead of a real file
info "Creating symlink at $TARGET_SCRIPT -> $HOOK_DEST"
if [ -L "$TARGET_SCRIPT" ] || [ -e "$TARGET_SCRIPT" ]; then
    rm -f "$TARGET_SCRIPT"
fi
ln -s "$HOOK_DEST" "$TARGET_SCRIPT"

info "Re-enabling SteamOS read-only filesystem..."
steamos-readonly enable

info "Installation complete: original hook at $HOOK_DEST"
info "Symlink created at $TARGET_SCRIPT"

# ---------------------------------------------------------------------------
# Register systemd boot timer (idempotent)
# ---------------------------------------------------------------------------
# SteamOS updates reset the root filesystem, so the hook file gets wiped.
# We re-run this installer on every boot via a systemd timer so it is
# always restored after an update, without further manual intervention.
# Unit files live under /etc/systemd/system/ which persists across updates.

SERVICE_UNIT="shutdown-after-sleep-installer.service"
TIMER_UNIT="shutdown-after-sleep-installer.timer"
SYSTEMD_DIR="/etc/systemd/system"

# locations where we will keep the real unit files
SERVICE_DEST="$SLEEP_FIX_DIR/$SERVICE_UNIT"
TIMER_DEST="$SLEEP_FIX_DIR/$TIMER_UNIT"

info "Writing systemd service unit (home): $SERVICE_DEST"
mkdir -p "$SLEEP_FIX_DIR"
if [ ! -r "$FILES_DIR/shutdown-after-sleep-installer.service" ]; then
    error "template service unit not found at $FILES_DIR/shutdown-after-sleep-installer.service"
    exit 1
fi
cp "$FILES_DIR/shutdown-after-sleep-installer.service" "$SERVICE_DEST"
# substitute the dynamic exec path
sed -i "s|__INSTALL_SCRIPT__|$INSTALL_SCRIPT|" "$SERVICE_DEST"

info "Setting ownership and permissions on $SERVICE_DEST"
chown root:root "$SERVICE_DEST"
chmod 644 "$SERVICE_DEST"

info "Linking service unit into $SYSTEMD_DIR"
mkdir -p "$SYSTEMD_DIR"
if [ -L "$SYSTEMD_DIR/$SERVICE_UNIT" ] || [ -e "$SYSTEMD_DIR/$SERVICE_UNIT" ]; then
    rm -f "$SYSTEMD_DIR/$SERVICE_UNIT"
fi
ln -s "$SERVICE_DEST" "$SYSTEMD_DIR/$SERVICE_UNIT"

info "Writing systemd timer unit (home): $TIMER_DEST"
if [ ! -r "$FILES_DIR/shutdown-after-sleep-installer.timer" ]; then
    error "template timer unit not found at $FILES_DIR/shutdown-after-sleep-installer.timer"
    exit 1
fi
cp "$FILES_DIR/shutdown-after-sleep-installer.timer" "$TIMER_DEST"

info "Setting ownership and permissions on $TIMER_DEST"
chown root:root "$TIMER_DEST"
chmod 644 "$TIMER_DEST"

info "Linking timer unit into $SYSTEMD_DIR"
if [ -L "$SYSTEMD_DIR/$TIMER_UNIT" ] || [ -e "$SYSTEMD_DIR/$TIMER_UNIT" ]; then
    rm -f "$SYSTEMD_DIR/$TIMER_UNIT"
fi
ln -s "$TIMER_DEST" "$SYSTEMD_DIR/$TIMER_UNIT"

info "Reloading systemd daemon..."
systemctl daemon-reload

info "Enabling and starting timer: $TIMER_UNIT"
systemctl enable --now "$TIMER_UNIT"
info "Timer registered: $TIMER_UNIT"

info "Done. The hook will be automatically reinstalled on every boot."

