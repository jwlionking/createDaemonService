# createDaemonService

Generate a systemd unit for a Linux daemon, then optionally enable and start it.

The original script wrote `ExecStart=realichaind` (a bare name, no path), always ran as root, and enabled the unit even if the binary did not exist. This version resolves an absolute `ExecStart`, previews the unit, and can run non-interactively.

## Requirements

- Linux with systemd
- bash
- root for installing into `/etc/systemd/system` (`--dry-run` and `--output` do not need root)

## Usage

```bash
git clone https://github.com/jwlionking/createDaemonService.git
cd createDaemonService
chmod +x createDaemonService.sh
```

Interactive (prompts for name, binary, user, enable, start):

```bash
sudo ./createDaemonService.sh
```

Non-interactive:

```bash
sudo ./createDaemonService.sh \
  --name realichaind \
  --exec /usr/local/bin/realichaind \
  --user realichain \
  --datadir /var/lib/realichain \
  --conf /etc/realichain.conf \
  --enable \
  --start
```

Preview without writing:

```bash
./createDaemonService.sh --dry-run --name myapp --exec /usr/local/bin/myapp --user www-data
```

Remove a unit this script installed:

```bash
sudo ./createDaemonService.sh --remove realichaind
```

## Options

| Flag | Meaning |
| --- | --- |
| `--name` | Unit name without `.service` |
| `--exec` | Binary path, or a name on `PATH` |
| `--args` | Extra `ExecStart` arguments |
| `--user` / `--group` | Unix user/group (default `root`) |
| `--datadir` / `--conf` | Append `-datadir=` and `-conf=` (coin-style daemons) |
| `--type` | `simple` (default), `forking`, or `notify` |
| `--harden` | Stronger sandbox (`PrivateDevices`, `ProtectHome`, `MemoryDenyWriteExecute`) |
| `--enable` / `--start` | Enable on boot / start now |
| `--dry-run` / `--output FILE` | Print or write without touching systemd |
| `--force` | Overwrite an existing unit |
| `--remove NAME` | Stop, disable, delete |

`Type=simple` expects the process to stay in the foreground. If your daemon forks, use `--type forking` and keep a PID file, or pass a foreground flag such as `-printtoconsole` / `-daemon=0` via `--args`.

`--harden` is off by default. `MemoryDenyWriteExecute` and `ProtectHome` break a lot of real daemons (JIT runtimes, data under `$HOME`).

## Example unit

```ini
[Unit]
Description=Realichain daemon
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=realichain
Group=realichain
ExecStart=/usr/local/bin/realichaind -printtoconsole -conf=/etc/realichain.conf -datadir=/var/lib/realichain
Restart=on-failure
RestartSec=10
LimitNOFILE=65535
PrivateTmp=true
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
```

## Tests

```bash
bash tests/test_generate.sh
```

## License

MIT. See [LICENSE](LICENSE).
