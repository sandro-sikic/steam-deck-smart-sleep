#!/bin/bash
# install.sh
#
# Installer for the steam-deck-smart-sleep systemd sleep hook.
# The hook script and helper units live in sibling files alongside this
# installer; running the script copies them into ~/steam-deck-smart-sleep and creates
# symlinks from the system locations.
#
# Usage (once as root on your Steam Deck):
#   sudo bash install.sh
#
# After the first run the hook is installed and this script registers itself
# as a systemd boot timer so the installation is automatically re-applied
# after every SteamOS update (which resets the read-only root filesystem).
# When everything is already in place the boot run changes nothing and never
# touches the read-only setting.
#
# Source files: the installer first tries to fetch the latest versions from
# GitHub; only if that fails does it fall back to the copies next to it.  Set
# SDSS_USE_LOCAL=1 to skip the download (e.g. to test local edits).

set -euo pipefail

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
# The SDSS_* variables exist so the test suite can run the installer against
# a scratch directory; the defaults are the real system locations.

TARGET_DIR="${SDSS_TARGET_DIR:-/usr/lib/systemd/system-sleep}"
SYSTEMD_DIR="${SDSS_SYSTEMD_DIR:-/etc/systemd/system}"
GITHUB_RAW="${SDSS_GITHUB_RAW:-https://raw.githubusercontent.com/sandro-sikic/steam-deck-smart-sleep/main}"

HOOK_NAME="steam-deck-smart-sleep.sh"
SERVICE_UNIT="steam-deck-smart-sleep-installer.service"
TIMER_UNIT="steam-deck-smart-sleep-installer.timer"
SOURCE_FILES=("$HOOK_NAME" "$SERVICE_UNIT" "$TIMER_UNIT" "install.sh")
# Nice to have (offline uninstall) but never required: a missing or failed
# download of these must not stop an install.
OPTIONAL_FILES=("uninstall.sh")

TARGET_SCRIPT="$TARGET_DIR/$HOOK_NAME"

# Set when we have switched the root filesystem to read-write, so the EXIT
# trap knows it has to switch it back.
READONLY_DISABLED=0
TMP_DIR=""

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

info()  { printf '[INFO]  %s\n' "$*"; }
error() { printf '[ERROR] %s\n' "$*" >&2; }
die()   { error "$*"; exit 1; }

# Runs on every exit: remove the download directory and, if we left the
# filesystem writable (because something failed half way), lock it again.
cleanup() {
    local rc=$?
    if [ -n "$TMP_DIR" ]; then
        rm -rf "$TMP_DIR"
    fi
    if [ "$READONLY_DISABLED" -eq 1 ]; then
        READONLY_DISABLED=0
        steamos-readonly enable || error "could not re-enable the read-only filesystem"
    fi
    return "$rc"
}

# Copy SRC to DST unless they are the same file (a local re-run from the
# directory it installs into).  The copy goes through a temp file and a rename
# so that overwriting the running installer never corrupts it: bash keeps
# reading the old inode.
copy_file() {
    local src="$1" dst="$2"
    if [ "$src" -ef "$dst" ]; then
        return 0
    fi
    cp "$src" "$dst.new"
    mv -f "$dst.new" "$dst"
}

# Escape a string for use as the replacement in a sed s||| expression.
sed_escape() {
    printf '%s' "$1" | sed 's/[\\&|]/\\&/g'
}

# True when LINK is a symlink pointing at DEST.
links_to() {
    [ -L "$1" ] && [ "$(readlink "$1")" = "$2" ]
}

# Replace whatever is at LINK with a symlink to DEST.
force_link() {
    local dest="$1" link="$2"
    rm -f "$link"
    ln -s "$dest" "$link"
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

resolve_paths() {
    # Directory containing this script; empty under `curl | bash`.  The test
    # suite sets SDSS_SCRIPT_DIR to stand in for either situation.
    SCRIPT_DIR=""
    if [ -n "${SDSS_SCRIPT_DIR+x}" ]; then
        SCRIPT_DIR="$SDSS_SCRIPT_DIR"
    elif [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    fi

    # Directory under the user's home where the real files will live. When the
    # installer is invoked with sudo we prefer the invoking user's home rather
    # than /root so that the files are easy to inspect and modify later.
    # The boot service sets SDSS_INSTALL_DIR explicitly: systemd does not set
    # $HOME for services without User=.
    if [ -n "${SDSS_INSTALL_DIR:-}" ]; then
        SLEEP_FIX_DIR="$SDSS_INSTALL_DIR"
    else
        local user_home
        if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
            user_home=$(getent passwd "$SUDO_USER" | cut -d: -f6)
            [ -n "$user_home" ] || die "could not determine the home directory of $SUDO_USER"
        else
            user_home="${HOME:-}"
            [ -n "$user_home" ] || die "HOME is not set; set SDSS_INSTALL_DIR to the install directory"
        fi
        SLEEP_FIX_DIR="$user_home/steam-deck-smart-sleep"
    fi
    HOOK_DEST="$SLEEP_FIX_DIR/$HOOK_NAME"
    SERVICE_DEST="$SLEEP_FIX_DIR/$SERVICE_UNIT"
    TIMER_DEST="$SLEEP_FIX_DIR/$TIMER_UNIT"
    # The systemd service always re-runs the persistent copy stored in
    # SLEEP_FIX_DIR, however this script was originally invoked.
    INSTALL_SCRIPT="$SLEEP_FIX_DIR/install.sh"
    UNINSTALL_DEST="$SLEEP_FIX_DIR/uninstall.sh"
}

# True when SCRIPT_DIR holds a readable copy of every source file.
local_sources_complete() {
    local f
    [ -n "$SCRIPT_DIR" ] || return 1
    for f in "${SOURCE_FILES[@]}"; do
        [ -r "$SCRIPT_DIR/$f" ] || return 1
    done
}

# Fetch every source file into TMP_DIR; non-zero if any is missing or empty.
download_sources() {
    local f
    TMP_DIR=$(mktemp -d)
    for f in "${SOURCE_FILES[@]}"; do
        info "  Downloading $f"
        curl -fsSL --connect-timeout 10 --max-time 60 "$GITHUB_RAW/$f" -o "$TMP_DIR/$f" || return 1
        [ -s "$TMP_DIR/$f" ] || return 1
    done
    for f in "${OPTIONAL_FILES[@]}"; do
        info "  Downloading $f (optional)"
        if ! curl -fsSL --connect-timeout 10 --max-time 60 "$GITHUB_RAW/$f" -o "$TMP_DIR/$f" \
                || [ ! -s "$TMP_DIR/$f" ]; then
            rm -f "$TMP_DIR/$f"
            info "  $f unavailable; skipping"
        fi
    done
}

# Prefer the latest files from GitHub; fall back to the local copies when the
# download fails (offline at boot, GitHub down) or SDSS_USE_LOCAL=1.
locate_sources() {
    if [ "${SDSS_USE_LOCAL:-0}" != "1" ]; then
        info "Fetching the latest version from GitHub..."
        if download_sources; then
            FILES_DIR="$TMP_DIR"
            return 0
        fi
        error "download failed; falling back to local files"
        rm -rf "$TMP_DIR"
        TMP_DIR=""
    fi

    local_sources_complete \
        || die "no usable source files: download failed or disabled, and no complete local copy in '${SCRIPT_DIR:-<none>}'"
    FILES_DIR="$SCRIPT_DIR"
    info "Using local files from $FILES_DIR"
}

# Put the real files into the home directory.  This needs no write access to
# the root filesystem, so it happens before the read-only switch is touched.
stage_files() {
    info "Creating home storage directory: $SLEEP_FIX_DIR"
    mkdir -p "$SLEEP_FIX_DIR"

    info "Persisting installer script -> $INSTALL_SCRIPT"
    copy_file "$FILES_DIR/install.sh" "$INSTALL_SCRIPT"
    chown root:root "$INSTALL_SCRIPT"
    chmod 755 "$INSTALL_SCRIPT"

    info "Writing $HOOK_NAME -> $HOOK_DEST"
    copy_file "$FILES_DIR/$HOOK_NAME" "$HOOK_DEST"
    chown root:root "$HOOK_DEST"
    chmod 755 "$HOOK_DEST"

    if [ -r "$FILES_DIR/uninstall.sh" ]; then
        info "Writing uninstall.sh -> $UNINSTALL_DEST"
        copy_file "$FILES_DIR/uninstall.sh" "$UNINSTALL_DEST"
        chown root:root "$UNINSTALL_DEST"
        chmod 755 "$UNINSTALL_DEST"
    fi

    info "Writing systemd service unit: $SERVICE_DEST"
    copy_file "$FILES_DIR/$SERVICE_UNIT" "$SERVICE_DEST"
    # substitute the dynamic paths (escaped for sed)
    sed -i -e "s|__INSTALL_SCRIPT__|$(sed_escape "$INSTALL_SCRIPT")|" \
           -e "s|__INSTALL_DIR__|$(sed_escape "$SLEEP_FIX_DIR")|" "$SERVICE_DEST"
    chown root:root "$SERVICE_DEST"
    chmod 644 "$SERVICE_DEST"

    info "Writing systemd timer unit: $TIMER_DEST"
    copy_file "$FILES_DIR/$TIMER_UNIT" "$TIMER_DEST"
    chown root:root "$TIMER_DEST"
    chmod 644 "$TIMER_DEST"
}

# True when all three system symlinks already point at the home copies.
system_links_current() {
    links_to "$TARGET_SCRIPT" "$HOOK_DEST" \
        && links_to "$SYSTEMD_DIR/$SERVICE_UNIT" "$SERVICE_DEST" \
        && links_to "$SYSTEMD_DIR/$TIMER_UNIT" "$TIMER_DEST"
}

link_system_files() {
    disable_readonly

    info "Creating symlink at $TARGET_SCRIPT -> $HOOK_DEST"
    mkdir -p "$TARGET_DIR"
    force_link "$HOOK_DEST" "$TARGET_SCRIPT"

    info "Linking systemd units into $SYSTEMD_DIR"
    mkdir -p "$SYSTEMD_DIR"
    force_link "$SERVICE_DEST" "$SYSTEMD_DIR/$SERVICE_UNIT"
    force_link "$TIMER_DEST" "$SYSTEMD_DIR/$TIMER_UNIT"

    enable_readonly
}

register_timer() {
    info "Reloading systemd daemon..."
    systemctl daemon-reload

    info "Enabling and starting timer: $TIMER_UNIT"
    systemctl enable --now "$TIMER_UNIT"
}

main() {
    if [ "${SDSS_EUID:-$EUID}" -ne 0 ]; then
        error "This script must be run as root."
        error "Try: sudo bash $0"
        return 1
    fi

    trap cleanup EXIT
    resolve_paths
    locate_sources
    stage_files

    if system_links_current; then
        info "Already installed; nothing to do."
        return 0
    fi

    link_system_files
    info "Installation complete: original hook at $HOOK_DEST"
    [ ! -x "$UNINSTALL_DEST" ] || info "To uninstall later: sudo $UNINSTALL_DEST"
    register_timer
    info "Done. The hook will be automatically reinstalled on every boot."
}

# Only run when executed (or piped into bash), so the tests can source the
# functions.  Under `curl | bash` BASH_SOURCE[0] is empty.
if [ -z "${BASH_SOURCE[0]:-}" ] || [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
