#!/bin/bash
set -euo pipefail
exec 2>>/tmp/jog_error.log

# Install JOG helpers on the laptop (run with sudo).
# Repo root = directory containing install/, scripts/, config/

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

install -d /etc/jog /usr/local/bin /var/lib/jog/status /srv/tftp

if [[ ! -f /etc/jog/jog.env ]]; then
  install -m 0644 "${ROOT}/config/jog.env.example" /etc/jog/jog.env
  echo "Created /etc/jog/jog.env — EDIT JOG_USB_IFACE and IPs before starting dnsmasq."
fi

install -m 0755 "${ROOT}/scripts/jog-render-dnsmasq.sh" /usr/local/bin/jog-render-dnsmasq.sh
install -m 0755 "${ROOT}/scripts/jog-refresh-status.sh" /usr/local/bin/jog-refresh-status.sh
install -m 0755 "${ROOT}/kiosk/chromium-jog.sh" /usr/local/bin/chromium-jog.sh
install -m 0755 "${ROOT}/installer/jog-install-wizard.sh" /usr/local/sbin/jog-install-wizard.sh
install -m 0644 "${ROOT}/installer/motd/jog-remind.sh" /etc/profile.d/jog-remind.sh
install -m 0755 "${ROOT}/scripts/jog-sync-images-from-primary.sh" /usr/local/bin/jog-sync-images-from-primary.sh

install -m 0644 "${ROOT}/systemd/jog-refresh-status.service" /etc/systemd/system/jog-refresh-status.service
install -m 0644 "${ROOT}/systemd/jog-refresh-status.timer" /etc/systemd/system/jog-refresh-status.timer
install -m 0644 "${ROOT}/systemd/jog-render-dnsmasq.service" /etc/systemd/system/jog-render-dnsmasq.service

mkdir -p /etc/systemd/system/dnsmasq.service.d
install -m 0644 "${ROOT}/systemd/dnsmasq.service.d/jog-pre.conf" /etc/systemd/system/dnsmasq.service.d/jog-pre.conf

mkdir -p /etc/xdg/autostart
install -m 0644 "${ROOT}/kiosk/jog-chromium.desktop" /etc/xdg/autostart/jog-chromium.desktop

# During ISO late-commands (curtin in-target), systemd is not operational — skip.
if [[ "${JOG_SKIP_SYSTEMD:-0}" != "1" ]] && [[ -d /run/systemd/system ]]; then
  systemctl daemon-reload
  systemctl enable jog-render-dnsmasq.service || true
  systemctl enable --now jog-refresh-status.timer || true
fi

echo "Done. Next:"
echo "  1) Run: sudo jog-install-wizard   (or edit /etc/jog/jog.env by hand)."
echo "  2) Install Chromium if needed: sudo apt install -y chromium-browser || sudo apt install -y chromium"
echo "  3) sudo systemctl restart dnsmasq (after wizard renders DHCP config)."
echo "  4) Log into graphical session — Chromium autostarts from /etc/xdg/autostart/"
