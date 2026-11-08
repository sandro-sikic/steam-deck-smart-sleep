# steam-deck-smart-sleep

Stop losing ~1% battery per hour in sleep mode. This tool automatically shuts down your Steam Deck (or any Linux system with an RTC) after a configurable delay, preventing battery drain while away from a charger — while keeping the device ready when plugged in.

## How It Works

The script is a systemd `system-sleep` hook. Every time the device enters sleep, it programs an RTC alarm to fire after a set delay (default: **3 hours**). When the device wakes:

1. **Device enters sleep** — an RTC alarm is scheduled `WAKE_DELAY` seconds in the future; the target time is written to `/run/rtc_shutdown_wake`.
2. **Device wakes after the timer fires** — the script checks the current time against the saved target:
   - **Connected to AC power / charging** → reschedules the alarm and goes back to sleep. The cycle repeats indefinitely while the charger is connected.
   - **Not charging** → initiates a clean shutdown (`systemctl poweroff`) to preserve battery.
3. **Device woken manually before the timer** — the RTC alarm is cancelled and nothing else happens.

The hook is built to fail safe: it never blocks a suspend, so if the alarm cannot be set the device simply sleeps normally. If it is charging but cannot re-arm the alarm, it stays awake rather than sleeping with no way to wake. It also validates `WAKE_DELAY` and the saved marker, issues `systemctl` calls with `--no-block` (the hook runs while `sleep.target` is still being torn down), and rotates its log at 1 MiB.

All activity is logged to `/var/log/steam-deck-smart-sleep.log`.

> **Save your game first.** A shutdown triggered by this script is equivalent to running out of battery — any unsaved in-memory data is lost.

## Charger Detection

The script checks multiple sysfs paths to reliably detect AC power across different hardware layouts:

- `/sys/class/power_supply/AC*/online`
- `/sys/class/power_supply/ADP*/online`
- `/sys/class/power_supply/ACAD*/online`
- Fallback: `/sys/class/power_supply/BAT*/status` (`Charging` or `Full`)

## Installation

Run the installer once as root:

```bash
curl -fsSL https://raw.githubusercontent.com/sandro-sikic/steam-deck-smart-sleep/main/install.sh | sudo bash
```

The installer always tries to fetch the latest files from GitHub first. If that fails (offline, GitHub down) it falls back to the files next to `install.sh`, e.g. from a local clone. To skip the download and install your local edits, run `sudo SDSS_USE_LOCAL=1 bash install.sh`.

### What the Installer Does

1. Disables the SteamOS read-only filesystem temporarily.
2. Fetches the latest files (or uses the local fallback) and copies them into `~/steam-deck-smart-sleep` (uses the invoking user's home when run with `sudo`, not `/root`).
3. Creates symlinks from system paths to the home directory copies:
   ```
   /usr/lib/systemd/system-sleep/steam-deck-smart-sleep.sh  ->  ~/steam-deck-smart-sleep/steam-deck-smart-sleep.sh
   /etc/systemd/system/steam-deck-smart-sleep-installer.*   ->  ~/steam-deck-smart-sleep/...
   ```
4. Re-enables the read-only filesystem.
5. Registers and starts a systemd boot timer (`steam-deck-smart-sleep-installer.timer`) that re-runs the installer on every boot, so SteamOS updates cannot permanently remove the hook. The boot service runs after `network-online.target`, so it normally pulls the newest version from `main` on every boot, and falls back to the files already in `~/steam-deck-smart-sleep` when offline. systemd does not set `$HOME` for the service, so the unit passes the install directory explicitly (`SDSS_INSTALL_DIR`). When everything is already in place the boot run changes no system files and never touches the read-only setting; if a run fails part-way, the read-only filesystem is restored on exit.

## Configuration

The wake delay is set by the `WAKE_DELAY` variable in `steam-deck-smart-sleep.sh` (default: `10800` seconds = 3 hours). To change it, edit the file in your `~/steam-deck-smart-sleep` directory — the symlink means the change takes effect immediately with no reinstall needed.

```bash
nano ~/steam-deck-smart-sleep/steam-deck-smart-sleep.sh
# change: WAKE_DELAY=10800
```

## Files

| File                                       | Description                                                                                                                                                            |
| ------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `install.sh`                               | Installer. Copies files to `~/steam-deck-smart-sleep`, creates system symlinks, and registers the boot timer. Supports both local clone and `curl \| bash` invocation. |
| `steam-deck-smart-sleep.sh`                | The systemd `system-sleep` hook. Programs the RTC alarm on suspend (`pre`) and handles wake logic on resume (`post`).                                                  |
| `steam-deck-smart-sleep-installer.service` | Systemd service unit that runs `install.sh` on boot.                                                                                                                   |
| `steam-deck-smart-sleep-installer.timer`   | Systemd timer unit that triggers the service on every boot.                                                                                                            |
| `tests/`                                   | [bats](https://github.com/bats-core/bats-core) unit tests plus `coverage.sh`, which enforces 100% line coverage with [kcov](https://github.com/SimonKagstrom/kcov).     |

## Development

The tests run the scripts against stubs (fake `rtcwake`, `systemctl`, `steamos-readonly`, sysfs and install directories in a temp dir), so they are safe to run on any Linux machine and never touch the real RTC, systemd or `/etc`. They cannot prove behaviour on real Steam Deck hardware.

```bash
bats tests/            # run the tests
tests/coverage.sh      # run them under kcov and require 100% line coverage
```

## Security Notice

This script modifies system files and requires root access. Because the boot service fetches and runs the installer from the `main` branch as root, anything merged there is executed on your device at the next boot; use `SDSS_USE_LOCAL=1` and a pinned copy if you do not want that. Please [review the source code](https://github.com/sandro-sikic/steam-deck-smart-sleep) before installation. The developer is not responsible for any damage caused by this program. Use at your own risk.

## Contributing & License

Issues and pull requests are welcome. Open source and community-driven.
