#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PID_FILE="$APP_DIR/.st-manager.pid"
PORT="${PORT:-3456}"
STOPPED=0

if [ -f "$PID_FILE" ]; then
  PID="$(cat "$PID_FILE" || true)"
  if [ -n "${PID:-}" ] && kill -0 "$PID" 2>/dev/null; then
    kill "$PID" || true
    sleep 1
    if kill -0 "$PID" 2>/dev/null; then
      kill -9 "$PID" || true
    fi
    echo "st-manager stopped by pid ($PID)"
    STOPPED=1
  fi
  rm -f "$PID_FILE"
fi

if command -v lsof >/dev/null 2>&1; then
  PORT_PIDS="$(lsof -ti tcp:"$PORT" || true)"
  if [ -n "${PORT_PIDS:-}" ]; then
    echo "$PORT_PIDS" | xargs -r kill || true
    STOPPED=1
    echo "st-manager stopped by port ($PORT)"
  fi
fi

if [ "$STOPPED" -eq 0 ] && command -v ss >/dev/null 2>&1; then
  SS_PIDS="$(ss -ltnp 2>/dev/null | awk -v p=":$PORT" '$4 ~ p {print}' | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' | sort -u || true)"
  if [ -n "${SS_PIDS:-}" ]; then
    echo "$SS_PIDS" | xargs -r kill || true
    STOPPED=1
    echo "st-manager stopped by ss port scan ($PORT)"
  fi
fi

if [ "$STOPPED" -eq 0 ]; then
  echo "st-manager is not running"
fi
