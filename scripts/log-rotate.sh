#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$APP_DIR/logs"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
MAX_LOG_MB="${MAX_LOG_MB:-20}"

mkdir -p "$LOG_DIR"

find "$LOG_DIR" -type f -name 'app-*.log' -mtime +"$RETENTION_DAYS" -delete
find "$LOG_DIR" -type f -name 'health-*.log' -mtime +"$RETENTION_DAYS" -delete

while IFS= read -r -d '' log_file; do
  size_mb="$(du -m "$log_file" | awk '{print $1}')"
  if [ "$size_mb" -gt "$MAX_LOG_MB" ]; then
    gzip -f "$log_file"
  fi
done < <(find "$LOG_DIR" -type f -name 'app-*.log' -print0)

find "$LOG_DIR" -type f -name '*.log.gz' -mtime +"$RETENTION_DAYS" -delete
echo "log rotate complete (retention=${RETENTION_DAYS}d, max=${MAX_LOG_MB}MB)"
