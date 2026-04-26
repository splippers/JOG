#!/bin/bash
set -e
exec 2>>/tmp/jog_error.log

# Multi-tab Chromium session (not --kiosk) so you keep tabs for FOG + status.
# Requires /etc/jog/jog.env with JOG_FOG_URL and optional JOG_STATUS_URL.

JOG_ENV="${JOG_ENV:-/etc/jog/jog.env}"
[[ -f "$JOG_ENV" ]] || exit 0
# shellcheck disable=SC1090
source "$JOG_ENV"

: "${JOG_FOG_URL:=http://127.0.0.1/}"
: "${JOG_FOG_TASKS_URL:=}"
: "${JOG_STATUS_URL:=file:///var/lib/jog/status/index.html}"

CHROME="${CHROME:-}"
for c in chromium chromium-browser google-chrome; do
  if command -v "$c" >/dev/null 2>&1; then
    CHROME="$c"
    break
  fi
done
[[ -n "$CHROME" ]] || exit 0

# Multi-tab window: FOG UI, optional tasks page, local host stats.
TABS=( "about:blank" "$JOG_FOG_URL" )
[[ -n "$JOG_FOG_TASKS_URL" ]] && TABS+=( "$JOG_FOG_TASKS_URL" )
TABS+=( "$JOG_STATUS_URL" )

exec "$CHROME" \
  --disable-session-crashed-bubble \
  --disable-infobars \
  --start-maximized \
  --new-window \
  "${TABS[@]}"
