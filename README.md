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
- **WiFi**: DHCP to your “unfiltered” SSID, **default route + DNS** with a **low route metric** so `apt`, browser traffic, and FOG’s installer use WiFi.

Start from `netplan/99-jog-usb.yaml.example`, copy to `/etc/netplan/`, adjust interface names, then `sudo netplan apply`.

### 3) Chromium “kiosk” with FOG + stats tabs (X11 — reliable on Intel laptops)

JOG is not a single-URL `--kiosk` fullscreen (that hides tabs). **`kiosk/chromium-jog.sh`** launches **maximized Chromium** with:

1. FOG management — `JOG_FOG_URL` (default **`http://localhost/fog/management/`**)
2. Optional extra FOG URL — `JOG_FOG_TASKS_URL` if set and different from `JOG_FOG_URL`
3. Local dashboard — `file:///var/lib/jog/status/index.html` (status timer refreshes HTML)

On **Intel iGPU** laptops (e.g. Dell Latitude 3410), use **`sudo jog-setup-reliable-kiosk.sh jogadmin`** after **`install/jog-install.sh`** + **`jog-install-wizard`**. That installs **ubuntu-xorg + LightDM + Chromium**, writes **`lightdm/50-jog-autologin.conf.example`** into **`/etc/lightdm/lightdm.conf.d/`**, and avoids Wayland/session glitches by matching **`ubuntu-xorg`** with Chromium’s **`--ozone-platform=x11`** / **`GDK_BACKEND=x11`**. Optional **`JOG_CHROMIUM_RESTART=1`** in **`/etc/jog/jog.env`** restarts Chromium if it exits.

Autostart: **`kiosk/jog-chromium.desktop`** → **`/usr/local/bin/chromium-jog.sh`**. Native FOG runs on the host; the status tab shows Apache/MariaDB/tftpd instead of containers.

See **[docs/ISO-BUILD.md](docs/ISO-BUILD.md)** (graphical kiosk section) for the full command sequence.

## FOG on the host (`/opt/fog`)

JOG installs the **official [FOG Project](https://fogproject.org/)** server natively under **`/opt/fog`** using **`install/fog-native-install.sh`** (wraps `bin/installfog.sh`). That pulls Apache, PHP, MariaDB, TFTP, NFS, etc. onto Ubuntu — no Docker.

```bash
sudo jog-install-wizard    # NIC + IPs + EFI → /tftpboot/ubuntu-signed + dnsmasq + starts FOG in background
journalctl -fu jog-fog-install.service   # optional: watch native FOG install progress
```
Manual rerun (e.g. edited `/etc/jog/jog.env`): **`sudo jog-provision-stack.sh`**. Low-level installer: **`sudo fog-native-install.sh`**.

FOG owns **UDP/69 (TFTP)**; JOG’s **dnsmasq** provides **DHCP only** on the USB imaging NIC and advertises **`dhcp-boot`** / **next-server** toward FOG’s IP (see `scripts/jog-render-dnsmasq.sh`). Pin the Git branch with **`FOG_GIT_REF`** in `/opt/JOG/.env` if you need a specific release line.

## ISO install + first-boot wizard

Authoritative steps: **[docs/ISO-BUILD.md](docs/ISO-BUILD.md)**.

- **Two ISOs (wizard on first boot)** — Canonical live-server ISO + **`jog-autoinstall-seed.iso`**: interactive **`jog-install-wizard`** after install (USB NIC hints, **`enx…`** recommended). Then **`jog-setup-reliable-kiosk.sh`** for **X11 + LightDM + Chromium**.
- **One ISO (Hyper-V / lab VM)** — **`installer/build-hyperv-single-iso.sh`** produces **`installer/ubuntu-26.04-live-server-jog-hyperv-amd64.iso`**: embedded nocloud + unattended first-boot (**`jog-provision-stack.sh --blocking-fog`**). No wizard; optional kiosk on the VM with **`jog-setup-reliable-kiosk.sh`** after install.
- **Wizard flow** applies **EFI staging**, **dnsmasq**, **`jog-provision-stack.sh`**, and starts **`jog-fog-install.service`**. Reminders: **`/etc/profile.d/jog-remind.sh`** tracks **`wizard.done`** and **`fog-native.done`**.

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

# 3) Wizard-driven install (recommended): applies dnsmasq + EFI staging + starts FOG
sudo jog-install-wizard
# Or manual: edit /etc/jog/jog.env then: sudo jog-provision-stack.sh

# 4) Reliable X11 kiosk (Intel laptop / Latitude-class): LightDM + ubuntu-xorg + Chromium
sudo jog-setup-reliable-kiosk.sh jogadmin && sudo reboot
```

## Repository layout

| Path | Purpose |
|------|---------|
| `install/fog-native-install.sh` | Clone FOG to `/opt/fog` and run official `installfog.sh` |
| `scripts/jog-copy-signed-ubuntu-efi-to-tftpboot.sh` | Stage shim/grub signed EFI under `/tftpboot/ubuntu-signed/` |
| `scripts/jog-provision-stack.sh` | EFI + dnsmasq + start FOG install (wizard / optional manual) |
| `scripts/jog-setup-reliable-kiosk.sh` | **`jog-setup-reliable-kiosk.sh`**: ubuntu-xorg + LightDM + Chromium for Intel kiosk |
| `systemd/jog-fog-install.service` | One-shot native FOG via `jog-fog-install-once.sh` |
| `.env.example` | Optional `FOG_GIT_REF` for pinning the fogproject clone |
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
| `docs/ISO-BUILD.md` | ISO builds (two-disc wizard vs single Hyper-V), kiosk (**`jog-setup-reliable-kiosk.sh`**) |
| `docs/CLUSTER.md` | Multi-node patterns and limits |
| `cluster/jog-node-role.env.example` | Edge vs standalone hints |

## JOS integration reminder

JOS reads DHCP **NEXT SERVER** into `/tmp/jos-next-server` and uses it as `FOG_SERVER` when not overridden. Your `dnsmasq` template must keep **`dhcp-boot=…,${JOG_NEXT_SERVER}`** and **`option:tftp-server`** aligned with that IP.
