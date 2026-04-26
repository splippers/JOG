#!/bin/bash
set -euo pipefail
# Download the official Ubuntu **26.04** Server live ISO (amd64) used with JOG autoinstall.
# Pin: see installer/UBUNTU_RELEASE

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REL="$(tr -d '[:space:]' <"${HERE}/UBUNTU_RELEASE")"
OUT="${1:-${HERE}/ubuntu-${REL}-live-server-amd64.iso}"

# GA naming (verified for 26.04): ubuntu-26.04-live-server-amd64.iso
URL="https://releases.ubuntu.com/${REL}/ubuntu-${REL}-live-server-amd64.iso"

echo "Downloading ${URL}"
rm -f "${OUT}.partial"
if ! curl -fL --retry 3 --retry-delay 2 -o "${OUT}.partial" "$URL"; then
  rm -f "${OUT}.partial"
  exit 1
fi
mv -f "${OUT}.partial" "$OUT"
echo "Saved: $OUT"
