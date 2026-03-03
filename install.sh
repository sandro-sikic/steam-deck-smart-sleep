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

INSTALL_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$INSTALL_SCRIPT")"
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
# Write the hook script from the embedded heredoc
# ---------------------------------------------------------------------------

write_hook() {
    # Copy the templated hook script out of the installer directory into
    # the home storage area.
    if [ ! -r "$SCRIPT_DIR/shutdown-after-sleep.sh" ]; then
        error "template hook script not found at $SCRIPT_DIR/shutdown-after-sleep.sh"
        exit 1
    fi
    cp "$SCRIPT_DIR/shutdown-after-sleep.sh" "$HOOK_DEST"
}

# ---------------------------------------------------------------------------
# Installation
# ---------------------------------------------------------------------------

info "Disabling SteamOS read-only filesystem..."
steamos-readonly disable

info "Creating home storage directory: $SLEEP_FIX_DIR"
mkdir -p "$SLEEP_FIX_DIR"

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
if [ ! -r "$SCRIPT_DIR/shutdown-after-sleep-installer.service" ]; then
    error "template service unit not found at $SCRIPT_DIR/shutdown-after-sleep-installer.service"
    exit 1
fi
cp "$SCRIPT_DIR/shutdown-after-sleep-installer.service" "$SERVICE_DEST"
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
if [ ! -r "$SCRIPT_DIR/shutdown-after-sleep-installer.timer" ]; then
    error "template timer unit not found at $SCRIPT_DIR/shutdown-after-sleep-installer.timer"
    exit 1
fi
cp "$SCRIPT_DIR/shutdown-after-sleep-installer.timer" "$TIMER_DEST"

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

