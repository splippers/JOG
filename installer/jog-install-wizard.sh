#!/bin/bash
set -euo pipefail
exec 2>>/tmp/jog_error.log

# Interactive setup for JOG (hostname, imaging network, DHCP, admin user, FOG pin).
# Requires: dialog, root. Idempotent-ish: re-run to overwrite generated configs.

: "${DIALOG:=dialog}"

log() { echo "JOG-WIZARD: $*"; }
die() { echo "JOG-WIZARD-ERROR: $*" >&2; exit 1; }

[[ "$(id -u)" -eq 0 ]] || die "Run as root (sudo jog-install-wizard)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "$SCRIPT_DIR" == "/usr/local/sbin" || "$SCRIPT_DIR" == "/usr/local/bin" ]]; then
  REPO_ROOT="${JOG_REPO:-/opt/JOG}"
else
  REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
fi
[[ -f "${REPO_ROOT}/docker-compose.yml" ]] || die "JOG repo not found at ${REPO_ROOT} (set JOG_REPO=...)"

if ! command -v dialog >/dev/null 2>&1; then
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq dialog
fi

# --- Defaults (sensible isolated imaging subnet) ---
DEF_HOSTNAME="jog"
DEF_IMAGING_IP="10.99.0.1"
DEF_PREFIX="24"
DEF_DHCP_START="10.99.0.100"
DEF_DHCP_END="10.99.0.250"
DEF_ROUTER="${DEF_IMAGING_IP}"
DEF_NEXT="${DEF_IMAGING_IP}"
DEF_FOG_IMAGE="ghcr.io/88fingerslukee/fog-docker:fog-1.5.10.1826"

# --- Welcome ---
$DIALOG --title "JOG setup" --msgbox \
"Welcome to JOG (Jonathan's Opensource Ghost).

This wizard will ask for:
  • system hostname
  • imaging network (USB NIC IP + DHCP range)
  • admin Linux account (username + password)
  • FOG container image tag (upstream FOG version pin)

Corporate LAN safety: DHCP is rendered ONLY on the USB interface you select.

Press OK to continue." 18 70 || exit 0

# --- Hostname ---
HOSTNAME="$($DIALOG --stdout --title "Hostname" --inputbox "Short hostname for this JOG laptop (DNS / UI):" 10 60 "${DEF_HOSTNAME}" || true)"
[[ -n "${HOSTNAME// }" ]] || HOSTNAME="$DEF_HOSTNAME"

# --- USB interface menu ---
mapfile -t IFACES < <(ip -br link show | awk '$1!="lo"{print $1}' | grep -v '^lo$' || true)
[[ "${#IFACES[@]}" -gt 0 ]] || die "No non-loopback interfaces found."

IFACE_ITEMS=()
for i in "${!IFACES[@]}"; do
  IFACE_ITEMS+=("$i" "${IFACES[$i]}")
done

IDX="$($DIALOG --stdout --title "USB imaging NIC" --menu \
"Select the USB3 Ethernet adapter used ONLY for imaging (not onboard LAN, not WiFi):" 20 70 10 \
"${IFACE_ITEMS[@]}" 2>&1)" || exit 0
JOG_USB_IFACE="${IFACES[$IDX]}"

# --- Imaging IP / DHCP ---
IMAGING_IP="$($DIALOG --stdout --title "Imaging IP" --inputbox "Static IP on the USB imaging link (laptop side):" 10 60 "${DEF_IMAGING_IP}" || true)"
PREFIX="$($DIALOG --stdout --title "Prefix" --inputbox "CIDR prefix length (usually 24):" 10 60 "${DEF_PREFIX}" || true)"
DHCP_START="$($DIALOG --stdout --title "DHCP start" --inputbox "DHCP pool first address:" 10 60 "${DEF_DHCP_START}" || true)"
DHCP_END="$($DIALOG --stdout --title "DHCP end" --inputbox "DHCP pool last address:" 10 60 "${DEF_DHCP_END}" || true)"
ROUTER="$($DIALOG --stdout --title "Default gateway for PXE clients" --inputbox "Usually the same as the JOG IP on this cable:" 10 60 "${IMAGING_IP}" || true)"
NEXT_SERVER="$($DIALOG --stdout --title "NEXT SERVER (TFTP/PXE)" --inputbox "Must match siaddr / tftp-server for clients (usually this laptop on USB):" 10 60 "${IMAGING_IP}" || true)"

NETMASK="255.255.255.0"
if [[ "$PREFIX" == "24" ]]; then NETMASK="255.255.255.0"; fi

FOG_WEB_HOST="$($DIALOG --stdout --title "FOG web host" --inputbox "Host/IP clients and Chromium use to open FOG (typical: same as imaging IP):" 10 60 "${IMAGING_IP}" || true)"

FOG_DOCKER_IMAGE="$($DIALOG --stdout --title "FOG Docker image" --inputbox "Pinned fog-docker image (see github.com/88fingerslukee/fog-docker/releases):" 12 70 "${DEF_FOG_IMAGE}" || true)"

# --- Cluster (optional) ---
CLUSTER_MODE="$($DIALOG --stdout --title "Cluster mode" --menu \
"Multiple JOG units on one busy network: choose how this node participates." 18 70 4 \
standalone "Single JOG (default)" \
edge "Edge node: sync images from primary + optional split DHCP" \
primary "Mark as primary (hint file for edge nodes)" \
2>&1)" || CLUSTER_MODE="standalone"

PRIMARY_SSH=""
if [[ "$CLUSTER_MODE" == "edge" ]]; then
  PRIMARY_SSH="$($DIALOG --stdout --title "Primary SSH" --inputbox "Primary JOG sync source (user@host), e.g. jogadmin@10.99.0.1:" 10 60 "" || true)"
fi

# --- Admin user ---
ADMIN_USER="$($DIALOG --stdout --title "Admin username" --inputbox "Linux account for kiosk login + sudo (lowercase, no spaces):" 10 60 "jogadmin" || true)"
[[ "$ADMIN_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] || die "Invalid username"

getent group docker >/dev/null 2>&1 || groupadd docker 2>/dev/null || true

PASS1="$($DIALOG --stdout --title "Password" --passwordbox "Password for ${ADMIN_USER}:" 10 60 || true)"
PASS2="$($DIALOG --stdout --title "Password" --passwordbox "Confirm password:" 10 60 || true)"
[[ -n "$PASS1" && "$PASS1" == "$PASS2" ]] || die "Passwords missing or mismatch"

# --- Summary ---
SUMMARY="hostname=$HOSTNAME
USB_IFACE=$JOG_USB_IFACE
imaging=${IMAGING_IP}/${PREFIX}
dhcp=${DHCP_START}-${DHCP_END}
router=$ROUTER next_server=$NEXT_SERVER
fog_web=$FOG_WEB_HOST
fog_image=$FOG_DOCKER_IMAGE
cluster=$CLUSTER_MODE
primary_ssh=$PRIMARY_SSH
admin=$ADMIN_USER"

$DIALOG --title "Confirm" --yesno "$SUMMARY

Write configuration and apply hostname?" 20 70 || exit 0

# --- Apply ---
install -d /etc/jog /etc/jog/cluster

hostnamectl set-hostname "$HOSTNAME"

# Linux user
if ! id -u "$ADMIN_USER" >/dev/null 2>&1; then
  useradd -m -s /bin/bash -G sudo,docker "$ADMIN_USER" 2>/dev/null || useradd -m -s /bin/bash -G sudo "$ADMIN_USER"
fi
echo "${ADMIN_USER}:${PASS1}" | chpasswd

cat >/etc/jog/jog.env <<EOF
JOG_USB_IFACE=${JOG_USB_IFACE}
JOG_IMAGING_IP=${IMAGING_IP}
JOG_IMAGING_PREFIX=${PREFIX}
JOG_DHCP_START=${DHCP_START}
JOG_DHCP_END=${DHCP_END}
JOG_DHCP_NETMASK=${NETMASK}
JOG_DHCP_LEASE_HOURS=12
JOG_DHCP_ROUTER=${ROUTER}
JOG_NEXT_SERVER=${NEXT_SERVER}
JOG_FOG_URL=http://127.0.0.1/
JOG_FOG_TASKS_URL=http://127.0.0.1/fog/management/index.php
JOG_STATUS_URL=file:///var/lib/jog/status/index.html
EOF

cat >/etc/jog/cluster.env <<EOF
JOG_CLUSTER_MODE=${CLUSTER_MODE}
JOG_PRIMARY_SSH=${PRIMARY_SSH}
EOF

# Netplan for USB static (WiFi unchanged — user should manage WiFi separately)
cat >/etc/netplan/90-jog-wizard.yaml <<EOF
network:
  version: 2
  ethernets:
    ${JOG_USB_IFACE}:
      addresses:
        - ${IMAGING_IP}/${PREFIX}
      dhcp4: false
      optional: true
EOF
chmod 0600 /etc/netplan/90-jog-wizard.yaml

# Docker compose env for FOG stack (used from JOG repo directory)
cat >"${REPO_ROOT}/.env" <<EOF
FOG_DOCKER_IMAGE=${FOG_DOCKER_IMAGE}
FOG_WEB_HOST=${FOG_WEB_HOST}
FOG_DB_ROOT_PASSWORD=$(openssl rand -base64 24)
TZ=UTC
EOF
chmod 0600 "${REPO_ROOT}/.env"

if command -v netplan >/dev/null 2>&1; then
  netplan generate
  netplan apply || log "netplan apply returned non-zero; check conflicts with other netplan files"
fi

if [[ -x "${REPO_ROOT}/install/jog-install.sh" ]]; then
  bash "${REPO_ROOT}/install/jog-install.sh"
fi

if [[ -d /run/systemd/system ]]; then
  systemctl daemon-reload || true
  systemctl enable jog-render-dnsmasq.service 2>/dev/null || true
  systemctl enable --now jog-refresh-status.timer 2>/dev/null || true
fi

if command -v jog-render-dnsmasq.sh >/dev/null 2>&1 || [[ -x /usr/local/bin/jog-render-dnsmasq.sh ]]; then
  /usr/local/bin/jog-render-dnsmasq.sh || true
fi

touch /etc/jog/wizard.done

$DIALOG --title "Done" --msgbox \
"JOG wizard finished.

Next steps:
  1) Review /etc/netplan/ — add WiFi with low route-metric if not already configured.
  2) cd ${REPO_ROOT} && docker compose pull && docker compose up -d
  3) sudo systemctl restart dnsmasq
  4) Reboot if you changed hostname or netplan.

Cluster: read docs/CLUSTER.md and run scripts/jog-sync-images-from-primary.sh on edge nodes." 22 70
