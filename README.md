# steam-deck-auto-off

A small utility for the Steam Deck (or similar Linux systems) that
automatically shuts down the machine shortly after it wakes from sleep
when an RTC alarm has been scheduled. This mitigates issues with the deck
left on during transport or when the lid is inadvertently opened while
suspended.

The repository contains three primary files:

- `install.sh` – installer script that sets up the hook and a
  systemd timer to re‑apply itself after each SteamOS update. It stores
  the real payload under `~/steam-deck-auto-off` and leaves symbolic links in the
  system directories.
- `shutdown-after-sleep.sh` – the systemd "system-sleep" hook executed on
  suspend/resume. It programs the RTC alarm and triggers a clean shutdown
  if the alarm fired.
- `shutdown-after-sleep-installer.{service,timer}` – service and timer
  units used by the installer to re-run on every boot.

## Usage

Run the installer once as root. For convenience there's a one‑liner that
fetches it from GitHub:

```bash
sudo bash <(curl -fsSL https://raw.githubusercontent.com/sandro-sikic/steam-deck-auto-off/main/install.sh)
```

After installation the hook will be automatically reinstalled on every
boot (via a systemd timer) so that SteamOS updates cannot permanently
remove it.

## Configuration

The wake‑delay is currently hard‑coded in
`shutdown-after-sleep.sh` (default 30 seconds). To change it, edit that
file in your home `steam-deck-auto-off` directory or modify the template before
running the installer.

## Installation path

All generated files are kept in `$HOME/steam-deck-auto-off` (or the invoking
user's home when run with `sudo`). The system locations contain only
symlinks:

```
/usr/lib/systemd/system-sleep/shutdown-after-sleep.sh -> ~/steam-deck-auto-off/shutdown-after-sleep.sh
/etc/systemd/system/shutdown-after-sleep-installer.* -> ~/steam-deck-auto-off/...
```

This makes it easier to inspect or modify the scripts without dealing
with a read‑only root filesystem.

## License & Contributing

Feel free to open issues or pull requests on GitHub. Include any real-world
feedback or suggestions for improvements.

The repository is distributed under the MIT License (see `LICENSE`).
