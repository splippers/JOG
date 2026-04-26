#!/bin/bash
set -euo pipefail
# Renders user-data from user-data.in with a hashed password for the initial jogadmin account.
# Usage: ./render-user-data.sh [plaintext-password]
# Default password is ONLY for the first ISO boot — operator must run jog-install-wizard.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PW="${1:-jog-change-me-now}"
HASH="$(openssl passwd -6 "$PW")"
sed "s|@PASSWORD@|${HASH}|g" "${HERE}/user-data.in" >"${HERE}/user-data"
echo "Wrote ${HERE}/user-data (initial jogadmin password: ${PW})"
