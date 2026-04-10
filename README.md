# pi-wayvnc-macos

Connect to your Raspberry Pi from **macOS Screen Sharing**, **iPad VNC
clients** (like Jump Desktop), or any standard VNC viewer — without
installing a custom client.

## The problem

Raspberry Pi OS has a built-in option to
[enable VNC](https://www.raspberrypi.com/documentation/computers/remote-access.html#vnc)
via `wayvnc`. However, the stock `wayvnc` only supports VeNCrypt / PAM
authentication, which most VNC clients don't understand. The official
documentation recommends installing TigerVNC — but on macOS there's a
perfectly good Screen Sharing app built into the OS, and on iPad there are
great VNC apps like Jump Desktop that also can't connect.

The upstream `wayvnc` and `neatvnc` projects have accepted patches that add
standard VNC authentication (DES VNC-Auth, security type 2) and fix display
compositing issues. But Raspberry Pi OS is Debian-based — these fixes won't
land in the official package until Debian updates `wayvnc`, likely not
before 2027-2028.

## What this package does

This drop-in `.deb` bundles a fresh build of
[wayvnc](https://github.com/any1/wayvnc),
[neatvnc](https://github.com/any1/neatvnc) and
[aml](https://github.com/any1/aml) under `/opt/pi-wayvnc-macos/` and
redirects `wayvnc.service` via a systemd drop-in. The stock wayvnc package
is **never modified** — `apt remove pi-wayvnc-macos` cleanly reverts.

**Security:** DES VNC-Auth is cryptographically weak (8-char password,
no encryption after auth). Use only on a trusted LAN or behind an SSH
tunnel (`ssh -L 5900:localhost:5900 pi@raspberrypi.local`).

## Requirements

Raspberry Pi 4 or 5 running Raspberry Pi OS **trixie** (Debian 13), aarch64,
with the stock `wayvnc` package installed and VNC enabled in `raspi-config`.

## Install

Download the `.deb` from
[GitHub Releases](https://github.com/AndrianBdn/pi-wayvnc-macos/releases/latest),
then on your Pi:

    sudo apt install ./pi-wayvnc-macos_1.0.0-1_arm64.deb
    sudo pi-wayvnc-macos-enable

The install places files under `/opt/pi-wayvnc-macos/` but does **not**
activate anything — your existing VNC keeps working until you run `enable`.

`enable` backs up `/etc/wayvnc/config`, patches it for DES auth, generates
a random VNC password, restarts `wayvnc`, and prints the password:

```
============================================================
  pi-wayvnc-macos enabled.

  Generated VNC password (write this down):

      Ab3dEfGh

  Connect from macOS:
    Finder -> Go -> Connect to Server -> vnc://raspberrypi.local
============================================================
```

Re-running `enable` when already enabled is safe — the password is preserved.

See the password again: `sudo pi-wayvnc-macos-show-password`

## Disable / Uninstall

    sudo pi-wayvnc-macos-disable    # restore stock VNC
    sudo apt remove pi-wayvnc-macos # remove the package

## Build from source

Requires Docker on the Pi (or any aarch64 Linux host):

    git clone https://github.com/AndrianBdn/pi-wayvnc-macos
    cd pi-wayvnc-macos
    make deb

Output: `./out/pi-wayvnc-macos_1.0.0-1_arm64.deb`. The build runs inside a
`debian:trixie-slim` container. Upstream sources are cloned automatically
from the commits pinned in `sources/manifest.txt`.

## Troubleshooting

    sudo journalctl -u wayvnc -f                         # service log
    sudo systemctl show wayvnc -p ExecStart --value       # which binary
    cat /opt/pi-wayvnc-macos/share/manifest.txt           # upstream SHAs

If `enable` fails with "wayvnc.service shape changed", reinstall stock
wayvnc first: `sudo apt install --reinstall wayvnc`

## Upstream fixes included

All fixes are merged upstream into [any1/neatvnc](https://github.com/any1/neatvnc)
and [any1/wayvnc](https://github.com/any1/wayvnc) by maintainer
[Andri Yngvason](https://github.com/any1). This package just builds them
before the Debian package catches up:

- **DES VNC-Auth** — [neatvnc PR #160](https://github.com/any1/neatvnc/pull/160):
  standard VNC authentication (security type 2), RFB 3.3/3.7 support
- **`allow_broken_crypto` config** — [wayvnc commit 1497397](https://github.com/any1/wayvnc/commit/1497397):
  opt-in config flag to enable DES auth
- **Stale display fix** — [wayvnc PR #426](https://github.com/any1/wayvnc/pull/426):
  fix gray/black artifacts in detached mode caused by a leftover placeholder display

License: ISC (see `LICENSE`).
