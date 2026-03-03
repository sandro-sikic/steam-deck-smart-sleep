# steam-deck-smart-sleep

Automatically shuts down your Steam Deck (or any similar Linux system) shortly after it wakes from sleep when an RTC alarm was responsible for the wake. This prevents the device from staying on unintentionally during transport.

## Files

| File                                               | Description                                                                                                                                                                              |
| -------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `install.sh`                                       | Sets up the sleep hook and a systemd timer that re-applies the hook after SteamOS updates. Stores files under `~/steam-deck-smart-sleep` and creates symlinks in the system directories. |
| `steam-deck-smart-sleep.sh`                        | The systemd `system-sleep` hook. Programs the RTC alarm on suspend and triggers a clean shutdown on resume if the alarm fired.                                                           |
| `steam-deck-smart-sleep-installer.{service,timer}` | Systemd units that re-run the installer on every boot.                                                                                                                                   |

## Usage

Run the installer once as root:

```bash
curl -fsSL https://raw.githubusercontent.com/sandro-sikic/steam-deck-smart-sleep/main/install.sh | sudo bash
```

After installation, the hook is automatically reinstalled on every boot via a systemd timer, so SteamOS updates cannot permanently remove it.

## Configuration

The shutdown delay after wake is hard-coded in `steam-deck-smart-sleep.sh` (default: **10800 seconds**). To change it, edit the file in your `~/steam-deck-smart-sleep` directory.

## Installation Path

All files are stored in `$HOME/steam-deck-smart-sleep` (or the home directory of the invoking user when run with `sudo`). System paths contain only symlinks, making it easy to inspect and modify scripts without dealing with a read-only root filesystem:

```
/usr/lib/systemd/system-sleep/steam-deck-smart-sleep.sh  ->  ~/steam-deck-smart-sleep/steam-deck-smart-sleep.sh
/etc/systemd/system/steam-deck-smart-sleep-installer.*   ->  ~/steam-deck-smart-sleep/...
```

## Contributing & License

Issues and pull requests are welcome.
