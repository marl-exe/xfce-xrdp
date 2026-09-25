# XFCE + xRDP

> **Looking for a $10.88/year VPS?** Use my referral links:
>
> DediRock Promo VPS - New York: https://billing.dedirock.com/aff.php?aff=898&pid=264
>
> DediRock Promo VPS - Los Angeles: https://billing.dedirock.com/aff.php?aff=898&pid=265
>
> GreenCloudVPS: https://greencloudvps.com/billing/aff.php?aff=10195&gid=68
>
> These are referral/affiliate links, which may provide me with a referral benefit if you sign up through them. Pricing and stock can change.

Interactive installer for a lightweight **XFCE desktop over xRDP** on Ubuntu VPS servers. It creates an isolated non-root desktop user, installs a minimal XFCE/xRDP stack, can optionally install **Brave Origin**, and lets you choose how TCP/3389 is exposed.

The project is designed for remote browser/admin workloads without converting the VPS into a full heavyweight Ubuntu desktop.

## Features

- Ubuntu 22.04, 24.04, and 26.04 support
- `amd64` and `arm64`
- Minimal XFCE installation using `--no-install-recommends`
- xRDP + Xorg (`xorgxrdp`)
- Dedicated non-root RDP user
- XFCE compositing disabled for lower remote-desktop overhead
- Optional Brave Origin installation from Brave's official APT repository
- Three RDP exposure choices:
  - SSH tunnel only / no new UFW rule
  - Allow one IPv4 address
  - Public TCP/3389
- Existing xRDP startup configuration is backed up before modification
- Installer state stored locally under `/var/lib/xfce-xrdp/` for safer rollback
- Uninstaller refuses to guess if installer state is missing
- No passwords, cookies, SSH keys, browser profiles, hostnames, or server IPs are stored in this repository

## Recommended resources

For a normal remote desktop:

- 1 vCPU / 1 GB RAM: basic administration only
- 2 vCPU / 2 GB RAM: practical minimum
- **2+ vCPU / 4 GB RAM: recommended for modern browsing/video sites**

Video viewed *through* RDP can look choppy even when playback on the VPS is healthy. A lower RDP resolution such as **1280x720** usually improves responsiveness considerably.

## Install

Clone the public repository:

```bash
git clone https://github.com/marl-exe/xfce-xrdp.git
cd xfce-xrdp
```

Run the installer:

```bash
sudo bash install.sh
```

The installer asks for the desktop username and then uses Linux's normal `passwd` prompt for the RDP password. The password is not written to the script, installer state, or GitHub.

Example flow:

```text
XFCE + xRDP Setup
==================
Detected: Ubuntu 24.04 (amd64)
CPU cores: 4
Memory: 8.0Gi

Desktop/RDP username [browser]:

Set the password used to sign in through RDP:
New password:
Retype new password:

Install Brave Origin? [Y/n]: y

RDP firewall mode:
  1) SSH tunnel only / do not add a TCP 3389 firewall rule (recommended)
  2) Allow TCP 3389 only from one IPv4 address
  3) Allow TCP 3389 publicly
Choice [1]: 2

IPv4 address allowed to connect to RDP: 203.0.113.25
Proceed with installation? [Y/n]: y
```

## Connect from Windows

Open Remote Desktop Connection:

```text
Win + R
mstsc
```

For a direct connection, enter your VPS public IP and sign in with the desktop user created by the installer. Choose **Xorg** on the xRDP login screen.

### SSH tunnel mode

If you selected mode 1, keep TCP/3389 closed and tunnel RDP through SSH:

```bash
ssh -L 13389:127.0.0.1:3389 root@YOUR_SERVER_IP
```

Leave that SSH session open, then connect Remote Desktop to:

```text
127.0.0.1:13389
```

This is the preferred setup when you do not need public RDP access.

## Public RDP warning

TCP/3389 exposed to the Internet will be scanned and attacked. Prefer an SSH tunnel, VPN/Tailscale, or an IP-restricted firewall rule whenever possible.

The installer changes UFW only when UFW is already active. It does **not** automatically enable UFW because doing so on an existing VPS could interfere with SSH, game servers, panels, Docker services, or other workloads. Provider-side firewalls must be managed separately.

## Brave Origin

If selected, the installer adds Brave's official Linux repository and installs:

```text
brave-origin
```

Brave Origin is useful for a lightweight Chromium-based browser session. Launch it from the XFCE desktop or a terminal as the RDP user:

```bash
brave-origin
```

Do not launch graphical browsers with `sudo`.

## Useful commands

Check xRDP:

```bash
systemctl status xrdp --no-pager
systemctl status xrdp-sesman --no-pager
```

Restart xRDP:

```bash
sudo systemctl restart xrdp
```

Close Brave processes owned by a user named `browser`:

```bash
sudo pkill -u browser brave
```

Check whether TCP/3389 is listening:

```bash
ss -tlnp | grep 3389
```

Check resource usage:

```bash
free -h
top
```

## Multiple RDP users

xRDP can run separate simultaneous desktop sessions for multiple Linux users. Version 1 of this installer configures one requested user during installation. Additional users can be created manually with `adduser` and given their own XFCE session, or multi-user management can be added in a future release.

## Uninstall / rollback

Run:

```bash
sudo bash uninstall.sh
```

The uninstaller reads `/var/lib/xfce-xrdp/state.env` and offers:

1. Remove the xRDP/XFCE components installed by this project
2. Remove Brave Origin only, when it was installed by this project
3. Remove everything configured/installed by this project
4. Cancel

If the installer created the desktop user, full removal also offers to delete that user and its home directory.

For safety, `uninstall.sh` does **not** run `apt autoremove` automatically and does not remove packages that were already installed before this project ran.

## What this project does not store

The public repository contains no machine-specific secrets. Do not commit any of the following:

- VPS public/private IP addresses that you consider sensitive
- root or RDP passwords
- SSH private keys
- browser profiles, cookies, or logged-in sessions
- TLS private keys
- application/API tokens
- Pterodactyl credentials or configuration

Local rollback metadata is written only to the VPS under:

```text
/var/lib/xfce-xrdp/
```

## Notes for existing servers

The installer is intended to be conservative, but any desktop stack adds packages and services. On servers already running Docker, Pterodactyl, game servers, databases, or production workloads, take a snapshot/backup first and monitor CPU/RAM after installation.

The installer does not intentionally modify Docker, nginx, MariaDB, Redis, Pterodactyl, game-server ports, or the system boot target.

---

## Need a VPS?

> DediRock Promo VPS - New York: https://billing.dedirock.com/aff.php?aff=898&pid=264
>
> DediRock Promo VPS - Los Angeles: https://billing.dedirock.com/aff.php?aff=898&pid=265
>
> GreenCloudVPS: https://greencloudvps.com/billing/aff.php?aff=10195&gid=68

These are referral/affiliate links, which may provide me with a referral benefit if you sign up through them. Pricing and stock can change.
