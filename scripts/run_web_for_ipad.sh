#!/usr/bin/env bash
# Run in YOUR terminal (foreground) so stdin works: press r / R for hot reload.
# iPad Safari: http://<printed-ip>:8080
set -euo pipefail
cd "$(dirname "$0")/.."
HOST="${WEB_HOSTNAME:-$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)}"
if [[ -z "${HOST}" ]]; then
  echo "Could not detect LAN IP. Set WEB_HOSTNAME, e.g.:"
  echo "  WEB_HOSTNAME=192.168.x.x ./scripts/run_web_for_ipad.sh"
  exit 1
fi
PORT="${WEB_PORT:-8080}"
echo "iPad: http://${HOST}:${PORT}"
echo "Keep this window focused — type r (reload) or R (restart). Ctrl+C to stop."
exec flutter run -d web-server --web-hostname "$HOST" --web-port "$PORT"
