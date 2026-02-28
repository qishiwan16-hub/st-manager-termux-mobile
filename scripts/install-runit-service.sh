#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="$(basename "$APP_DIR")"
SERVICE_NAME="${SERVICE_NAME:-st-manager}"
SERVICE_SRC="$APP_DIR/termux/runit/st-manager"
SERVICE_ROOT="${PREFIX:-/data/data/com.termux/files/usr}/var/service"
SERVICE_DST="$SERVICE_ROOT/$SERVICE_NAME"

if [ ! -d "$SERVICE_ROOT" ]; then
  echo "termux-services is not ready. run: pkg install termux-services"
  exit 1
fi

if [ ! -d "$SERVICE_SRC" ]; then
  echo "missing service template: $SERVICE_SRC"
  exit 1
fi

mkdir -p "$APP_DIR/logs/runit"

if [ -d "$SERVICE_DST" ]; then
  backup_dir="${SERVICE_DST}.bak.$(date +%s)"
  mv "$SERVICE_DST" "$backup_dir"
  echo "old service moved to $backup_dir"
fi

cp -r "$SERVICE_SRC" "$SERVICE_DST"
chmod +x "$SERVICE_DST/run" "$SERVICE_DST/log/run"
sed -i "s|__APP_DIR__|$APP_DIR|g" "$SERVICE_DST/run"
sed -i "s|__APP_DIR__|$APP_DIR|g" "$SERVICE_DST/log/run"

sv up "$SERVICE_NAME" || true
sv status "$SERVICE_NAME" || true

echo "runit service installed at $SERVICE_DST"
