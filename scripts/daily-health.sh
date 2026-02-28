#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$APP_DIR/logs"
HEALTH_SCRIPT="$APP_DIR/scripts/healthcheck.sh"
ROTATE_SCRIPT="$APP_DIR/scripts/log-rotate.sh"
LOG_FILE="$LOG_DIR/health-$(date +%F).log"
SERVICE_NAME="${SERVICE_NAME:-st-manager}"

mkdir -p "$LOG_DIR"

if "$HEALTH_SCRIPT" >>"$LOG_FILE" 2>&1; then
  "$ROTATE_SCRIPT" >>"$LOG_FILE" 2>&1 || true
  exit 0
fi

echo "$(date '+%F %T') healthcheck failed" >>"$LOG_FILE"

if command -v termux-notification >/dev/null 2>&1; then
  termux-notification \
    --id st-manager-health \
    --title "st-manager healthcheck failed" \
    --content "Run $APP_DIR/scripts/status.sh"
fi

if command -v sv >/dev/null 2>&1 && [ -d "${PREFIX:-}/var/service/$SERVICE_NAME" ]; then
  sv restart "$SERVICE_NAME" >>"$LOG_FILE" 2>&1 || true
fi

exit 1
