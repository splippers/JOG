# JOG — ISO-based install (**Ubuntu 26.04 LTS**)

JOG is pinned to **Ubuntu Server 26.04** (`installer/UBUNTU_RELEASE`). Use the **live-server** amd64 image from [releases.ubuntu.com/26.04](https://releases.ubuntu.com/26.04/) (file name: `ubuntu-26.04-live-server-amd64.iso`).

JOG ships two layers:

1. **Unattended base OS** — autoinstall (`installer/autoinstall/`) installs Docker, dnsmasq, git, clones JOG to `/opt/JOG`, and drops helper units.
2. **Interactive network + FOG** — after reboot, run **`sudo jog-install-wizard`** (dialog TUI). `/etc/profile.d/jog-remind.sh` nags until `/etc/jog/wizard.done` exists.

Canonical reference (same major): [Autoinstall quick start](https://ubuntu.com/server/docs/install/autoinstall-quickstart) and Subiquity docs: [Providing autoinstall configuration](https://canonical-subiquity.readthedocs-hosted.com/en/latest/tutorial/providing-autoinstall.html).

## Why two steps?

Autoinstall cannot know your **USB NIC name**, **safe IP ranges** beside a corporate LAN, or your **hostname** on every laptop. The wizard collects those on the installed system.

## 1) Download the 26.04 live-server ISO

From the JOG repo:

```bash
./installer/fetch-ubuntu-live-server-iso.sh
```

Writes `installer/ubuntu-26.04-live-server-amd64.iso` (override path: `./installer/fetch-ubuntu-live-server-iso.sh /path/to/out.iso`).

## 2) Build the CIDATA seed ISO

```bash
sudo apt install -y cloud-image-utils xorriso   # cloud-localds preferred
cd installer/autoinstall
./render-user-data.sh 'your-temporary-install-password'
cd ..
./build-cidata-seed-iso.sh
```

Produces **`installer/jog-autoinstall-seed.iso`**. If `cloud-localds` is installed, the seed is built the same way as in the [Ubuntu autoinstall quick start](https://ubuntu.com/server/docs/install/autoinstall-quickstart#using-another-volume-to-provide-the-autoinstall-configuration); otherwise the script falls back to `xorriso`.

## 3) Boot the installer (VM or bare metal)

**Second-volume method** (matches Ubuntu quick start):

- **Drive 1**: `ubuntu-26.04-live-server-amd64.iso` (USB or virtual CD)
- **Drive 2**: `jog-autoinstall-seed.iso` (second USB or virtual CD)

At the bootloader, edit the kernel command line and add **`autoinstall`** so the installer consumes the autoinstall config **without** interactive disk confirmation (see quick start: *“add the autoinstall parameter to the kernel command line”*).

**Network method** (optional): serve `user-data` / `meta-data` over HTTP and boot with something like:

`autoinstall ds=nocloud-net\;s=http://<host>:<port>/`

(Exact URL encoding depends on your boot loader; see the [quick start network section](https://ubuntu.com/server/docs/install/autoinstall-quickstart#providing-the-autoinstall-data-over-the-network).)

## After first boot

1. Log in as **`jogadmin`** (password from `./render-user-data.sh`).
2. **`sudo jog-install-wizard`**
3. `cd /opt/JOG && docker compose pull && docker compose up -d`
4. `sudo systemctl restart dnsmasq`
