#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$APP_DIR/logs"
PID_FILE="$APP_DIR/.st-manager.pid"
DATE_TAG="$(date +%F-%H%M%S)"
CONFIG_FILE="$APP_DIR/app-config.json"

mkdir -p "$LOG_DIR"

if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  echo "st-manager already running (pid=$(cat "$PID_FILE"))."
  exit 0
fi

rm -f "$PID_FILE"

export HOSTNAME="${ST_MANAGER_HOST:-127.0.0.1}"
export PORT="${PORT:-3456}"
export NODE_ENV="${NODE_ENV:-production}"

verify_runtime_dependencies() {
  (
    cd "$APP_DIR"
    node -e 'for (const m of ["next", "react", "react-dom"]) require.resolve(m)'
  ) >/dev/null 2>&1
}

install_runtime_dependencies() {
  local npm_cache_dir npm_registry_primary npm_registry_fallback registry
  local npm_fetch_retries npm_fetch_retry_mintimeout npm_fetch_retry_maxtimeout npm_fetch_timeout
  local npm_args attempt max_attempts use_npm_ci install_rc

  npm_cache_dir="${NPM_CACHE_DIR:-$APP_DIR/.npm-cache}"
  npm_registry_primary="${NPM_REGISTRY_PRIMARY:-https://registry.npmjs.org/}"
  npm_registry_fallback="${NPM_REGISTRY_FALLBACK:-https://registry.npmmirror.com/}"
  npm_fetch_retries="${NPM_FETCH_RETRIES:-2}"
  npm_fetch_retry_mintimeout="${NPM_FETCH_RETRY_MINTIMEOUT:-2000}"
  npm_fetch_retry_maxtimeout="${NPM_FETCH_RETRY_MAXTIMEOUT:-20000}"
  npm_fetch_timeout="${NPM_FETCH_TIMEOUT:-60000}"

  npm_args=(
    "--omit=dev"
    "--no-audit"
    "--fund=false"
    "--prefer-offline"
    "--progress=false"
  )

  max_attempts=1
  if [ -n "${npm_registry_fallback:-}" ] && [ "$npm_registry_fallback" != "$npm_registry_primary" ]; then
    max_attempts=2
  fi

  use_npm_ci=0
  if [ -f "$APP_DIR/package-lock.json" ]; then
    use_npm_ci=1
  fi

  mkdir -p "$npm_cache_dir"

  (
    cd "$APP_DIR"
    export npm_config_cache="$npm_cache_dir"
    export npm_config_fetch_retries="$npm_fetch_retries"
    export npm_config_fetch_retry_mintimeout="$npm_fetch_retry_mintimeout"
    export npm_config_fetch_retry_maxtimeout="$npm_fetch_retry_maxtimeout"
    export npm_config_fetch_timeout="$npm_fetch_timeout"

    install_rc=1
    attempt=1
    while [ "$attempt" -le "$max_attempts" ]; do
      registry="$npm_registry_primary"
      if [ "$attempt" -eq 2 ]; then
        registry="$npm_registry_fallback"
      fi
      export npm_config_registry="$registry"

      if [ "$use_npm_ci" -eq 1 ]; then
        echo "Installing runtime dependencies via npm ci (attempt $attempt/$max_attempts, registry=$registry)"
        npm ci "${npm_args[@]}" && install_rc=0 || install_rc=$?
      else
        echo "Installing runtime dependencies via npm install (attempt $attempt/$max_attempts, registry=$registry)"
        npm install "${npm_args[@]}" && install_rc=0 || install_rc=$?
      fi

      if [ "$install_rc" -eq 0 ]; then
        break
      fi
      attempt=$((attempt + 1))
    done

    return "$install_rc"
  )
}

ensure_runtime_dependencies() {
  if verify_runtime_dependencies; then
    return 0
  fi

  echo "WARN: missing runtime modules (next/react/react-dom), attempting auto-install..."
  if ! command -v npm >/dev/null 2>&1; then
    echo "ERROR: npm is not available. Run: bash install-termux.sh"
    return 1
  fi

  if ! install_runtime_dependencies; then
    echo "ERROR: auto-install failed. Check npm logs under $APP_DIR/.npm-cache/_logs"
    return 1
  fi

  if ! verify_runtime_dependencies; then
    echo "ERROR: dependencies installed but runtime modules are still missing."
    return 1
  fi

  echo "Runtime dependencies verified."
  return 0
}

CONFIG_DATA_ROOT=""
if [ -f "$CONFIG_FILE" ] && command -v node >/dev/null 2>&1; then
  CONFIG_DATA_ROOT="$(node -e 'try{const fs=require("fs"); const p=JSON.parse(fs.readFileSync(process.argv[1], "utf8")).dataPath || ""; process.stdout.write(p)}catch{}' "$CONFIG_FILE" 2>/dev/null || true)"
fi

export DATA_ROOT="${DATA_ROOT:-${CONFIG_DATA_ROOT:-$HOME/.st-manager/data/default-user}}"

if ! ensure_runtime_dependencies; then
  exit 1
fi

if command -v node >/dev/null 2>&1; then
  node "$APP_DIR/scripts/sanitize-prerender.js" "$APP_DIR" settings worlds || true
fi

if [ "${MOBILE_UI_PATCH:-1}" != "0" ]; then
  if [ -f "$APP_DIR/scripts/patch-mobile-ui.sh" ]; then
    if ! bash "$APP_DIR/scripts/patch-mobile-ui.sh"; then
      echo "WARN: patch-mobile-ui failed, continuing startup."
    fi
  fi
fi

LOG_FILE="$LOG_DIR/app-$DATE_TAG.log"

PORT_PID=""
PORT_IN_USE=0
if command -v lsof >/dev/null 2>&1; then
  PORT_PID="$(lsof -ti tcp:"$PORT" -sTCP:LISTEN 2>/dev/null | head -n 1 || true)"
  if [ -n "${PORT_PID:-}" ]; then
    PORT_IN_USE=1
  fi
fi

if [ "$PORT_IN_USE" -eq 0 ] && command -v ss >/dev/null 2>&1; then
  SS_LINE="$(ss -ltnp 2>/dev/null | awk -v p=":$PORT" '$4 ~ p {print; exit}' || true)"
  if [ -n "${SS_LINE:-}" ]; then
    PORT_IN_USE=1
    if [ -z "${PORT_PID:-}" ]; then
      PORT_PID="$(printf '%s\n' "$SS_LINE" | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' | head -n 1 || true)"
    fi
  fi
fi

if [ "$PORT_IN_USE" -eq 1 ]; then
  if command -v curl >/dev/null 2>&1 && curl -fsS --max-time 3 "http://127.0.0.1:${PORT}/api/config" >/dev/null 2>&1; then
    if [ -n "${PORT_PID:-}" ]; then
      echo "$PORT_PID" >"$PID_FILE"
      echo "st-manager already running on port $PORT (pid=$PORT_PID)."
    else
      rm -f "$PID_FILE"
      echo "st-manager already running on port $PORT."
    fi
    exit 0
  fi
  if [ -n "${PORT_PID:-}" ]; then
    echo "port $PORT already in use by pid=$PORT_PID, refusing to start"
  else
    echo "port $PORT already in use, refusing to start"
  fi
  exit 1
fi

(
  cd "$APP_DIR"
  nohup node server.js >>"$LOG_FILE" 2>&1 &
  echo $! >"$PID_FILE"
)

sleep 1

if kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  echo "st-manager started (pid=$(cat "$PID_FILE"), host=$HOSTNAME, port=$PORT)"
  exit 0
fi

echo "st-manager failed to start, check $LOG_FILE"
if [ -f "$LOG_FILE" ]; then
  tail -n 40 "$LOG_FILE" || true
fi
exit 1
