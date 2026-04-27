# JOG — Jonathan's Opensource Ghost

Portable **FOG** server on a laptop (Ubuntu), designed to sit **next to a sensitive corporate LAN** while only offering DHCP/TFTP/PXE on a **USB3 Ethernet** link. Pairs with **JOS** clients.

Upstream repo: [github.com/splippers/JOG](https://github.com/splippers/JOG).

**OS pin:** JOG’s ISO / autoinstall path targets **Ubuntu Server 26.04 LTS** (`installer/UBUNTU_RELEASE`). The live installer image is `ubuntu-26.04-live-server-amd64.iso` from [releases.ubuntu.com/26.04](https://releases.ubuntu.com/26.04/).

## Technician workflow

- Target laptop: **F12** → **Boot from IPv4**
- DHCP **NEXT SERVER** (siaddr) = JOG laptop’s address on the **USB imaging** subnet only
- iPXE loads `ipxe/boot.ipxe`, which chains **JOS** from `${next-server}`
- JOS registers with FOG, uploads inventory, and joins multicast (see the JOS repo)

## Hard requirements (corporate LAN safety)

### 1) DHCP only on the USB3 NIC

`dnsmasq` is configured with **`interface=<your USB NIC>`** and **`bind-interfaces`**, so it does **not** open a DHCP socket on onboard Ethernet or WiFi. The authoritative source is `/etc/jog/jog.env` → rendered file **`/etc/dnsmasq.d/99-jog-imaging.conf`** via `jog-render-dnsmasq.sh`.

Operational checklist:

- Identify the USB adapter once: `ip -br link` (names like `enx…` are common).
- Set **`JOG_USB_IFACE`** in `/etc/jog/jog.env` to **only** that interface.
- Do **not** plug the laptop’s onboard NIC into the corporate network during imaging if you can avoid it; if it must stay connected, use **netplan metrics** + optional **nftables** (see `nftables/jog-isolate-imaging.nft.example`).

### 2) WiFi for updates; imaging traffic stays on USB

Recommended split:

- **USB**: static IP on an **isolated** RFC1918 subnet (example `10.99.0.1/24`) used only for PXE clients. **No default route** on this interface.
- **WiFi**: DHCP to your “unfiltered” SSID, **default route + DNS** with a **low route metric** so `apt`, `docker pull`, and browser traffic use WiFi.

Start from `netplan/99-jog-usb.yaml.example`, copy to `/etc/netplan/`, adjust interface names, then `sudo netplan apply`.

### 3) Chromium “kiosk” with FOG + stats tabs

JOG is not a single-URL `--kiosk` fullscreen (that hides tabs). Instead it launches **maximized Chromium** with multiple tabs:

1. FOG UI — `JOG_FOG_URL` (default `http://127.0.0.1/`)
2. FOG tasks / imaging view — `JOG_FOG_TASKS_URL` (optional; tune path for your FOG build)
3. Local host dashboard — `file:///var/lib/jog/status/index.html` (refreshed every ~10s)

Install:

- `sudo ./install/jog-install.sh`
- Enable **graphical autologin** for a dedicated user (example in `lightdm/50-jog-autologin.conf.example`).
- Put that user in the **`docker`** group if you want `docker stats` in the status tab without sudo.

Autostart is shipped as `/etc/xdg/autostart/jog-chromium.desktop` pointing at `/usr/local/bin/chromium-jog.sh`.

## FOG in Docker (laptop)

`docker-compose.yml` uses the community-maintained **`ghcr.io/88fingerslukee/fog-docker`** image ([documentation](https://88fingerslukee.github.io/fog-docker/), [source](https://github.com/88fingerslukee/fog-docker/)). That project publishes **versioned tags that match upstream FOG Project builds** (for example `fog-1.5.10.1826` ships FOG **1.5.10.1826**). JOG **pins** that tag in `docker-compose.yml` / `.env.example` so “current FOG” means a **deliberate upgrade** when you bump `FOG_DOCKER_IMAGE`, not whatever `:latest` happened to be on the day you pulled.

To move to a newer FOG: open [fog-docker releases](https://github.com/88fingerslukee/fog-docker/releases), pick the newest `fog-x.y.z.*` tag, set it in `.env`:

```bash
FOG_DOCKER_IMAGE=ghcr.io/88fingerslukee/fog-docker:fog-1.5.10.1826
```

Then `docker compose pull && docker compose up -d`.

```bash
cp .env.example .env
# set FOG_WEB_HOST to the USB imaging IP (e.g. 10.99.0.1) or hostname clients use
docker compose up -d
```

## ISO install + first-boot wizard

- **Unattended OS layer**: `installer/autoinstall/` targets **Ubuntu Server 26.04** live-server + Subiquity autoinstall (Docker, dnsmasq, git, clones JOG to `/opt/JOG`). Fetch the GA ISO with `installer/fetch-ubuntu-live-server-iso.sh`, build the **CIDATA** seed with `installer/build-cidata-seed-iso.sh` after `./installer/autoinstall/render-user-data.sh`. Full procedure: [docs/ISO-BUILD.md](docs/ISO-BUILD.md).
- **Operator questions (hostname, IP ranges, USB NIC, passwords, FOG pin)**: run **`sudo jog-install-wizard`** after first boot (dialog TUI). A reminder is shown from `/etc/profile.d/jog-remind.sh` until `/etc/jog/wizard.done` exists.

Re-run prep (Ubuntu ISO + seed ISO):

```bash
cd /mnt/EDDIE-SANDIEGO/Projects/JOG
sudo apt update
sudo apt install -y cloud-image-utils xorriso openssl curl
./installer/fetch-ubuntu-live-server-iso.sh
( cd installer/autoinstall && ./render-user-data.sh 'TEMP-PASSWORD-HERE' )
./installer/build-cidata-seed-iso.sh
```

## Multi-JOG / saturated networks

See [docs/CLUSTER.md](docs/CLUSTER.md). Short version: **do not** put multiple DHCP servers on the same L2 with overlapping pools; scale with **separate imaging segments**, **FOG storage nodes**, **image rsync** (`scripts/jog-sync-images-from-primary.sh`), or **fatter uplinks**.

## Quick install sequence (reference)

```bash
# 1) Network: USB static + WiFi default route (edit names/IPs)
sudo cp netplan/99-jog-usb.yaml.example /etc/netplan/99-jog-usb.yaml
sudo nano /etc/netplan/99-jog-usb.yaml
sudo netplan apply

# 2) JOG helpers + env
sudo ./install/jog-install.sh
sudo nano /etc/jog/jog.env

# 3) DHCP/TFTP (dnsmasq) — renders USB-only config then starts
sudo apt install -y dnsmasq
sudo jog-render-dnsmasq.sh
sudo systemctl restart dnsmasq

# 4) TFTP root: place ipxe.efi + kernels per your FOG/JOS layout under /srv/tftp

# 5) Graphical autologin + reboot into UI
sudo cp lightdm/50-jog-autologin.conf.example /etc/lightdm/lightdm.conf.d/50-jog-autologin.conf
sudo nano /etc/lightdm/lightdm.conf.d/50-jog-autologin.conf
```

## Repository layout

| Path | Purpose |
|------|---------|
| `docker-compose.yml` | FOG stack (`fog-docker`) |
| `.env.example` | Docker env template |
| `config/jog.env.example` | USB-only DHCP + kiosk URLs → `/etc/jog/jog.env` |
| `scripts/jog-render-dnsmasq.sh` | Renders `/etc/dnsmasq.d/99-jog-imaging.conf` from `jog.env` |
| `scripts/jog-refresh-status.sh` | Writes `/var/lib/jog/status/index.html` |
| `systemd/*` | Timer for status HTML + dnsmasq `ExecStartPre` hook |
| `kiosk/chromium-jog.sh` | Multi-tab Chromium launcher |
| `kiosk/jog-chromium.desktop` | XDG autostart entry |
| `netplan/99-jog-usb.yaml.example` | USB static + WiFi default route |
| `nftables/jog-isolate-imaging.nft.example` | Optional forward isolation |
| `ipxe/boot.ipxe` | Chain-load JOS using `${next-server}` |
| `installer/` | Autoinstall + seed ISO builder + `jog-install-wizard` |
| `installer/UBUNTU_RELEASE` | Pinned Ubuntu series (**26.04**) |
| `installer/fetch-ubuntu-live-server-iso.sh` | Downloads official `ubuntu-26.04-live-server-amd64.iso` |
| `docs/ISO-BUILD.md` | How to combine Ubuntu Server ISO + JOG seed |
| `docs/CLUSTER.md` | Multi-node patterns and limits |
| `cluster/jog-node-role.env.example` | Edge vs standalone hints |

## JOS integration reminder

JOS reads DHCP **NEXT SERVER** into `/tmp/jos-next-server` and uses it as `FOG_SERVER` when not overridden. Your `dnsmasq` template must keep **`dhcp-boot=…,${JOG_NEXT_SERVER}`** and **`option:tftp-server`** aligned with that IP.
