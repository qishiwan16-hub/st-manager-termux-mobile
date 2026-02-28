#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$APP_DIR/logs"
PID_FILE="$APP_DIR/.st-manager.pid"
PORT="${PORT:-3456}"

echo "[process]"
if [ -f "$PID_FILE" ]; then
  PID="$(cat "$PID_FILE" || true)"
  if [ -n "${PID:-}" ] && kill -0 "$PID" 2>/dev/null; then
    echo "running (pid=$PID)"
  else
    echo "pid file exists but process not running"
  fi
else
  echo "not running (pid file missing)"
fi

echo
echo "[listener]"
if command -v ss >/dev/null 2>&1; then
  LISTEN_OUT="$(ss -ltnp 2>/dev/null | awk -v p=":$PORT" '$4 ~ p {print}')"
  if [ -n "${LISTEN_OUT:-}" ]; then
    echo "$LISTEN_OUT"
  else
    echo "no listener found on :$PORT"
  fi
elif command -v netstat >/dev/null 2>&1; then
  LISTEN_OUT="$(netstat -ltn 2>/dev/null | awk -v p=":$PORT" '$4 ~ p {print}')"
  if [ -n "${LISTEN_OUT:-}" ]; then
    echo "$LISTEN_OUT"
  else
    echo "no listener found on :$PORT"
  fi
else
  echo "ss/netstat not available"
fi

echo
echo "[health]"
if command -v curl >/dev/null 2>&1; then
  TMP_FILE="$(mktemp)"
  if curl -fsS --max-time 10 "http://127.0.0.1:${PORT}/api/stats" >"$TMP_FILE" 2>/dev/null; then
    head -c 240 "$TMP_FILE"
    echo
  else
    echo "health endpoint unreachable"
  fi
  rm -f "$TMP_FILE"
else
  echo "curl not available"
fi

echo
echo "[logs]"
LATEST_LOG="$(ls -1t "$LOG_DIR"/app-*.log 2>/dev/null | head -n 1 || true)"
if [ -n "${LATEST_LOG:-}" ]; then
  echo "latest: $LATEST_LOG"
  tail -n 30 "$LATEST_LOG"
else
  echo "no app log found"
fi
