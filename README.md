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

The installer asks how many minutes the device should sleep before auto-shutdown (default 180) and saves it to `~/steam-deck-smart-sleep/smart-sleep.conf`; see [Configuration](#configuration). It always tries to fetch the latest files from GitHub first. If that fails (offline, GitHub down) it falls back to the files next to `install.sh`, e.g. from a local clone. To skip the download and install your local edits, run `sudo SDSS_USE_LOCAL=1 bash install.sh`.

### What the Installer Does

1. Disables the SteamOS read-only filesystem temporarily.
2. Fetches the latest files (or uses the local fallback) and copies them, including `uninstall.sh`, into `~/steam-deck-smart-sleep` (uses the invoking user's home when run with `sudo`, not `/root`).
3. Creates symlinks from system paths to the home directory copies:
   ```
   /usr/lib/systemd/system-sleep/steam-deck-smart-sleep.sh  ->  ~/steam-deck-smart-sleep/steam-deck-smart-sleep.sh
   /etc/systemd/system/steam-deck-smart-sleep-installer.*   ->  ~/steam-deck-smart-sleep/...
   ```
4. Re-enables the read-only filesystem.
5. Registers and starts a systemd boot timer (`steam-deck-smart-sleep-installer.timer`) that re-runs the installer on every boot, so SteamOS updates cannot permanently remove the hook. The boot service runs after `network-online.target`, so it normally pulls the newest version from `main` on every boot, and falls back to the files already in `~/steam-deck-smart-sleep` when offline. systemd does not set `$HOME` for the service, so the unit passes the install directory explicitly (`SDSS_INSTALL_DIR`). When everything is already in place the boot run changes no system files and never touches the read-only setting; if a run fails part-way, the read-only filesystem is restored on exit.

## Uninstalling

The installer prints these uninstall instructions when it finishes. It also keeps a copy of the uninstaller in `~/steam-deck-smart-sleep`, so you can uninstall offline (it is optional: if it can't be fetched, the install still succeeds). Run it as root, from that copy, from a clone, or straight from GitHub:

```bash
sudo ~/steam-deck-smart-sleep/uninstall.sh
# or, from a clone
sudo bash uninstall.sh
# or
curl -fsSL https://raw.githubusercontent.com/sandro-sikic/steam-deck-smart-sleep/main/uninstall.sh | sudo bash
```

It disables and stops the boot timer first (so nothing can reinstall the hook), then removes the sleep hook symlink and the timer/service symlinks (temporarily lifting the read-only filesystem, and restoring it even if something fails), reloads systemd, and clears the hook's runtime state: any pending RTC alarm, `/run/rtc_shutdown_wake` and the log at `/var/log/steam-deck-smart-sleep.log`.

Your files in `~/steam-deck-smart-sleep` are **not** touched; delete that directory yourself if you want them gone. It is safe to run more than once.

## Configuration

The only setting is how long the device sleeps before it wakes to decide between sleeping again (charging) and shutting down (not charging). It is stored in `~/steam-deck-smart-sleep/smart-sleep.conf`:

```ini
WAKE_DELAY_MINUTES=180
```

- **During install** you are asked "Minutes to sleep before auto-shutdown [180]". Press enter for the default (3 hours). With no terminal to ask on (such as the boot-time reinstall) the default is used.
- **Skip the question** with `--minutes`: `curl -fsSL …/install.sh | sudo bash -s -- --minutes 90` (or `sudo bash install.sh --minutes 90`). This also replaces an existing value.
- **Change it later** by editing the file (no `sudo` needed if you installed with `sudo`, since the file belongs to you). It applies the next time the device goes to sleep; there is nothing to reinstall.
- **Updates keep your time.** The installer never overwrites an existing config, including the boot-time update from GitHub. The setting is only lost if you delete the file or the whole `~/steam-deck-smart-sleep` directory, in which case the next run asks again (or falls back to 180 minutes).
- **Valid values** are whole numbers from 1 to 10080 (one week). Anything else in the file is ignored with a note in the log, and the 180-minute default is used. The hook parses the file strictly and never executes it.
- The uninstaller leaves the config in place along with the rest of the directory.

## Files

| File                                       | Description                                                                                                                                                            |
| ------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `install.sh`                               | Installer. Copies files to `~/steam-deck-smart-sleep`, creates system symlinks, and registers the boot timer. Supports both local clone and `curl \| bash` invocation. |
| `smart-sleep.conf`                         | Created by the installer in `~/steam-deck-smart-sleep` (not part of the repo): your sleep time in minutes. Preserved across updates.                                    |
| `uninstall.sh`                             | Uninstaller. Stops and removes the timer, service and hook from the system and clears runtime state; leaves `~/steam-deck-smart-sleep` alone. A copy is installed there for offline use. |
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
