#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/qishiwan16-hub/st-manager-termux-mobile.git}"
BRANCH="${BRANCH:-main}"
APP_DIR="${APP_DIR:-$HOME/apps/st-manager-termux-mobile}"
INSTALL_STAGE="${INSTALL_STAGE:-bootstrap}"

ST_MANAGER_HOST_INPUT="${ST_MANAGER_HOST:-}"
HOST="${ST_MANAGER_HOST_INPUT:-127.0.0.1}"
PORT="${PORT:-3456}"

DATA_PATH_INPUT="${DATA_PATH:-}"
DATA_PATH=""
SHARED_STORAGE_READY=0

FORCE_NPM_INSTALL="${FORCE_NPM_INSTALL:-0}"
NPM_CACHE_DIR="${NPM_CACHE_DIR:-$APP_DIR/.npm-cache}"
NPM_HEARTBEAT_SECONDS="${NPM_HEARTBEAT_SECONDS:-10}"
NPM_INSTALL_TIMEOUT_SECONDS="${NPM_INSTALL_TIMEOUT_SECONDS:-1200}"
NPM_FETCH_RETRIES="${NPM_FETCH_RETRIES:-2}"
NPM_FETCH_RETRY_MINTIMEOUT="${NPM_FETCH_RETRY_MINTIMEOUT:-2000}"
NPM_FETCH_RETRY_MAXTIMEOUT="${NPM_FETCH_RETRY_MAXTIMEOUT:-20000}"
NPM_FETCH_TIMEOUT="${NPM_FETCH_TIMEOUT:-60000}"
NPM_LOG_TAIL_LINES="${NPM_LOG_TAIL_LINES:-80}"
NPM_INSTALL_RETRY_COUNT="${NPM_INSTALL_RETRY_COUNT:-3}"
NPM_INSTALL_RETRY_DELAY_SECONDS="${NPM_INSTALL_RETRY_DELAY_SECONDS:-5}"
NPM_REGISTRY_PRIMARY="${NPM_REGISTRY_PRIMARY:-https://registry.npmjs.org/}"
NPM_REGISTRY_FALLBACK="${NPM_REGISTRY_FALLBACK:-https://registry.npmmirror.com/}"

is_termux_env() {
  if command -v pkg >/dev/null 2>&1; then
    return 0
  fi
  case "${PREFIX:-}" in
    */com.termux/*) return 0 ;;
  esac
  return 1
}

install_base_packages() {
  if is_termux_env; then
    echo "Detected Termux environment; using pkg."
    pkg update -y
    pkg upgrade -y
    pkg install -y nodejs-lts git curl jq tmux termux-api termux-services lsof cronie
    return 0
  fi

  if ! command -v apt-get >/dev/null 2>&1; then
    echo "ERROR: this installer supports Termux (pkg) or Debian/Ubuntu-like systems (apt-get)."
    exit 1
  fi

  local sudo_cmd=""
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
      sudo_cmd="sudo"
    else
      echo "ERROR: apt-get needs root privileges; run as root or install sudo."
      exit 1
    fi
  fi

  echo "Detected non-Termux environment; using apt-get compatibility mode."
  $sudo_cmd apt-get update -y
  $sudo_cmd apt-get install -y nodejs npm git curl jq tmux lsof cron ca-certificates
}

prompt_access_mode() {
  if [ -n "$ST_MANAGER_HOST_INPUT" ]; then
    HOST="$ST_MANAGER_HOST_INPUT"
    return 0
  fi

  if [ ! -t 0 ]; then
    HOST="127.0.0.1"
    echo "No interactive terminal detected, defaulting to local access (127.0.0.1)."
    return 0
  fi

  echo "请选择访问模式:"
  echo "  1) 本地访问 (127.0.0.1)"
  echo "  2) 公网访问 (0.0.0.0)"

  while true; do
    printf "请输入选项 [1/2] (默认 1): "
    local choice=""
    IFS= read -r choice || choice=""
    case "${choice:-1}" in
      1)
        HOST="127.0.0.1"
        break
        ;;
      2)
        HOST="0.0.0.0"
        echo "WARN: 已启用公网监听，请确保已配置防火墙和鉴权。"
        break
        ;;
      *)
        echo "无效选项，请输入 1 或 2。"
        ;;
    esac
  done

  echo "Selected host: $HOST"
}

run_with_heartbeat() {
  local start_ts now_ts elapsed timeout pid rc
  timeout=0
  start_ts="$(date +%s)"

  case "$NPM_INSTALL_TIMEOUT_SECONDS" in
    ''|*[!0-9]*) timeout=0 ;;
    *) timeout="$NPM_INSTALL_TIMEOUT_SECONDS" ;;
  esac

  "$@" &
  pid=$!

  while kill -0 "$pid" 2>/dev/null; do
    sleep "$NPM_HEARTBEAT_SECONDS"
    if ! kill -0 "$pid" 2>/dev/null; then
      break
    fi

    now_ts="$(date +%s)"
    elapsed=$((now_ts - start_ts))
    echo "npm install in progress... ${elapsed}s elapsed"

    if [ "$timeout" -gt 0 ] && [ "$elapsed" -ge "$timeout" ]; then
      echo "ERROR: npm install exceeded timeout (${timeout}s), terminating process..."
      kill "$pid" 2>/dev/null || true
      sleep 1
      kill -9 "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 124
    fi
  done

  wait "$pid"
  rc=$?
  return "$rc"
}

latest_npm_log_file() {
  ls -1t "$NPM_CACHE_DIR"/_logs/*-debug-0.log 2>/dev/null | head -n 1 || true
}

show_npm_install_diagnostics() {
  local latest_npm_log=""
  latest_npm_log="$(latest_npm_log_file)"
  if [ -n "$latest_npm_log" ]; then
    echo "--- npm log tail: $latest_npm_log ---"
    tail -n "$NPM_LOG_TAIL_LINES" "$latest_npm_log" || true
  fi
}

is_retryable_npm_error() {
  local log_file="$1"
  [ -n "$log_file" ] || return 1
  grep -Eq "EAI_AGAIN|ENOTFOUND|ETIMEDOUT|ECONNRESET|getaddrinfo|network timeout" "$log_file"
}

dependency_signature() {
  local hash_cmd=""
  local node_ver npm_ver
  node_ver="$(node -v 2>/dev/null || echo unknown-node)"
  npm_ver="$(npm -v 2>/dev/null || echo unknown-npm)"

  if command -v sha256sum >/dev/null 2>&1; then
    hash_cmd="sha256sum"
  elif command -v shasum >/dev/null 2>&1; then
    hash_cmd="shasum -a 256"
  elif command -v md5sum >/dev/null 2>&1; then
    hash_cmd="md5sum"
  else
    node -e 'const fs=require("fs");const crypto=require("crypto");const app=process.argv[1];const nodeV=process.argv[2];const npmV=process.argv[3];let s=`node=${nodeV}\nnpm=${npmV}\n`;for(const f of ["package.json","package-lock.json"]){const p=`${app}/${f}`;if(fs.existsSync(p))s+=fs.readFileSync(p,"utf8")}process.stdout.write(crypto.createHash("sha256").update(s).digest("hex"))' "$APP_DIR" "$node_ver" "$npm_ver"
    return 0
  fi

  {
    echo "node=$node_ver"
    echo "npm=$npm_ver"
    [ -f "$APP_DIR/package.json" ] && cat "$APP_DIR/package.json"
    [ -f "$APP_DIR/package-lock.json" ] && cat "$APP_DIR/package-lock.json"
  } | sh -c "$hash_cmd" | awk '{print $1}'
}

verify_runtime_dependencies() {
  local dep
  local missing=()

  for dep in next react react-dom; do
    if [ ! -f "$APP_DIR/node_modules/$dep/package.json" ]; then
      missing+=("$dep")
    fi
  done

  if [ "${#missing[@]}" -gt 0 ]; then
    echo "ERROR: missing runtime dependency metadata: ${missing[*]}"
    return 1
  fi

  if command -v node >/dev/null 2>&1; then
    if ! (cd "$APP_DIR" && node -e 'for (const m of ["next","react","react-dom"]) require.resolve(m);') >/dev/null 2>&1; then
      echo "ERROR: runtime dependency resolve check failed (next/react/react-dom)"
      return 1
    fi
  fi

  return 0
}

install_node_dependencies() {
  local stamp_file="$APP_DIR/.deps-installed.sig"
  local sig_current sig_saved sig_after
  local use_npm_ci=0
  local npm_registry="$NPM_REGISTRY_PRIMARY"
  local use_fallback_registry=0
  local attempt=1 max_attempts=1 retry_delay=0
  local install_rc=0 latest_npm_log=""
  local npm_base_args=(
    "--omit=dev"
    "--no-audit"
    "--fund=false"
    "--prefer-offline"
    "--progress=false"
  )

  sig_current="$(dependency_signature)"
  sig_saved=""
  [ -f "$stamp_file" ] && sig_saved="$(cat "$stamp_file" 2>/dev/null || true)"

  if [ "$FORCE_NPM_INSTALL" != "1" ] && [ -d "$APP_DIR/node_modules" ] && [ "$sig_current" = "$sig_saved" ]; then
    if verify_runtime_dependencies; then
      echo "Dependencies unchanged, skipping npm install."
      return 0
    fi
    echo "WARN: dependency cache looks incomplete, forcing reinstall."
  fi

  if [ -f "$APP_DIR/package-lock.json" ]; then
    use_npm_ci=1
  else
    echo "WARN: package-lock.json not found; first install may be slower."
  fi

  case "$NPM_INSTALL_RETRY_COUNT" in
    ''|*[!0-9]*) max_attempts=1 ;;
    *) max_attempts="$NPM_INSTALL_RETRY_COUNT" ;;
  esac
  [ "$max_attempts" -lt 1 ] && max_attempts=1

  case "$NPM_INSTALL_RETRY_DELAY_SECONDS" in
    ''|*[!0-9]*) retry_delay=0 ;;
    *) retry_delay="$NPM_INSTALL_RETRY_DELAY_SECONDS" ;;
  esac

  mkdir -p "$NPM_CACHE_DIR"
  export npm_config_cache="$NPM_CACHE_DIR"
  export npm_config_fetch_retries="$NPM_FETCH_RETRIES"
  export npm_config_fetch_retry_mintimeout="$NPM_FETCH_RETRY_MINTIMEOUT"
  export npm_config_fetch_retry_maxtimeout="$NPM_FETCH_RETRY_MAXTIMEOUT"
  export npm_config_fetch_timeout="$NPM_FETCH_TIMEOUT"

  cd "$APP_DIR"

  while [ "$attempt" -le "$max_attempts" ]; do
    export npm_config_registry="$npm_registry"
    echo "Dependency install attempt ${attempt}/${max_attempts} (registry: $npm_config_registry)"

    install_rc=0
    if [ "$use_npm_ci" = "1" ]; then
      run_with_heartbeat npm ci "${npm_base_args[@]}" || install_rc=$?
    else
      run_with_heartbeat npm install "${npm_base_args[@]}" || install_rc=$?
    fi

    if [ "$install_rc" -eq 0 ]; then
      break
    fi

    latest_npm_log="$(latest_npm_log_file)"
    show_npm_install_diagnostics

    if [ "$attempt" -lt "$max_attempts" ] && { [ "$install_rc" -eq 124 ] || is_retryable_npm_error "$latest_npm_log"; }; then
      if [ "$install_rc" -eq 124 ]; then
        echo "Install attempt timed out, preparing retry..."
      fi

      if [ "$use_fallback_registry" = "0" ] && [ -n "$NPM_REGISTRY_FALLBACK" ] && [ "$NPM_REGISTRY_FALLBACK" != "$NPM_REGISTRY_PRIMARY" ]; then
        use_fallback_registry=1
        npm_registry="$NPM_REGISTRY_FALLBACK"
        echo "Retryable network error detected; switching registry to: $npm_registry"
      fi

      if [ "$retry_delay" -gt 0 ]; then
        echo "Retrying dependency install in ${retry_delay}s..."
        sleep "$retry_delay"
      else
        echo "Retrying dependency install now..."
      fi

      attempt=$((attempt + 1))
      continue
    fi

    return "$install_rc"
  done

  if [ "$attempt" -gt "$max_attempts" ]; then
    return 1
  fi

  verify_runtime_dependencies
  sig_after="$(dependency_signature)"
  echo "$sig_after" >"$stamp_file"
}

ensure_webpack_runtime() {
  local runtime_file="$APP_DIR/.next/server/webpack-runtime.js"
  if [ -f "$runtime_file" ]; then
    return 0
  fi

  echo "WARN: missing $runtime_file, creating fallback runtime"
  mkdir -p "$APP_DIR/.next/server"
  cat >"$runtime_file" <<'RUNTIME_EOF'
"use strict";
const path = require("path");
const moduleFactories = Object.create(null);
const moduleCache = Object.create(null);
const loadedChunks = Object.create(null);
function __webpack_require__(moduleId) {
  const id = String(moduleId);
  if (__webpack_require__.c[id]) return __webpack_require__.c[id].exports;
  const factory = __webpack_require__.m[id];
  if (!factory) {
    const err = new Error(`Cannot find webpack module '${id}'`);
    err.code = "MODULE_NOT_FOUND";
    throw err;
  }
  const module = (__webpack_require__.c[id] = { exports: {} });
  factory(module, module.exports, __webpack_require__);
  return module.exports;
}
__webpack_require__.m = moduleFactories;
__webpack_require__.c = moduleCache;
__webpack_require__.o = (obj, prop) => Object.prototype.hasOwnProperty.call(obj, prop);
__webpack_require__.d = (exports, definition) => {
  for (const key in definition) {
    if (__webpack_require__.o(definition, key) && !__webpack_require__.o(exports, key)) {
      Object.defineProperty(exports, key, { enumerable: true, get: definition[key] });
    }
  }
};
__webpack_require__.r = (exports) => {
  if (typeof Symbol !== "undefined" && Symbol.toStringTag) {
    Object.defineProperty(exports, Symbol.toStringTag, { value: "Module" });
  }
  Object.defineProperty(exports, "__esModule", { value: true });
};
__webpack_require__.n = (module) => {
  const getter = module && module.__esModule ? () => module.default : () => module;
  __webpack_require__.d(getter, { a: getter });
  return getter;
};
function registerChunk(chunk) {
  if (!chunk || typeof chunk !== "object") return;
  if (chunk.modules && typeof chunk.modules === "object") {
    for (const id in chunk.modules) __webpack_require__.m[id] = chunk.modules[id];
  }
  const ids = Array.isArray(chunk.ids) ? chunk.ids : chunk.id != null ? [chunk.id] : [];
  for (const id of ids) loadedChunks[id] = true;
}
function ensureChunkLoaded(chunkId) {
  if (loadedChunks[chunkId]) return;
  const chunkPath = path.join(__dirname, "chunks", `${chunkId}.js`);
  const chunk = require(chunkPath);
  registerChunk(chunk);
}
__webpack_require__.C = registerChunk;
__webpack_require__.X = (_unused, chunkIds, execute) => {
  if (Array.isArray(chunkIds)) for (const chunkId of chunkIds) ensureChunkLoaded(chunkId);
  return execute();
};
module.exports = __webpack_require__;
RUNTIME_EOF
}

show_runtime_diagnostics() {
  local latest_log=""
  echo "--- app-config.json ---"
  cat "$APP_DIR/app-config.json" || true
  echo "--- status ---"
  PORT="$PORT" bash "$APP_DIR/scripts/status.sh" || true

  latest_log="$(ls -1t "$APP_DIR"/logs/app-*.log 2>/dev/null | head -n 1 || true)"
  if [ -n "$latest_log" ]; then
    echo "--- tail: $latest_log ---"
    tail -n 120 "$latest_log" || true
  fi
}

sync_repo_from_github() {
  local backup_dir
  mkdir -p "$(dirname "$APP_DIR")"

  if [ -d "$APP_DIR/.git" ]; then
    echo "Updating repo in $APP_DIR"
    git -C "$APP_DIR" remote set-url origin "$REPO_URL" || true
    git -C "$APP_DIR" fetch --depth 1 origin "$BRANCH"
    if git -C "$APP_DIR" show-ref --verify --quiet "refs/heads/$BRANCH"; then
      git -C "$APP_DIR" checkout "$BRANCH"
    else
      git -C "$APP_DIR" checkout -b "$BRANCH" "origin/$BRANCH"
    fi

    if ! git -C "$APP_DIR" pull --ff-only origin "$BRANCH"; then
      backup_dir="${APP_DIR}.bak.$(date +%s)"
      mv "$APP_DIR" "$backup_dir"
      echo "Local repo update failed, backup moved to: $backup_dir"
      git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$APP_DIR"
      if [ -d "$backup_dir/node_modules" ] && [ ! -d "$APP_DIR/node_modules" ]; then
        echo "Reusing cached node_modules from backup directory..."
        mv "$backup_dir/node_modules" "$APP_DIR/node_modules" 2>/dev/null || cp -a "$backup_dir/node_modules" "$APP_DIR/node_modules" || true
      fi
      if [ -f "$backup_dir/.deps-installed.sig" ] && [ ! -f "$APP_DIR/.deps-installed.sig" ]; then
        cp -a "$backup_dir/.deps-installed.sig" "$APP_DIR/.deps-installed.sig" || true
      fi
      if [ -f "$backup_dir/package-lock.json" ] && [ ! -f "$APP_DIR/package-lock.json" ]; then
        cp -a "$backup_dir/package-lock.json" "$APP_DIR/package-lock.json" || true
      fi
    fi
    return 0
  fi

  if [ -d "$APP_DIR" ]; then
    backup_dir="${APP_DIR}.bak.$(date +%s)"
    mv "$APP_DIR" "$backup_dir"
    echo "Existing non-git directory moved to: $backup_dir"
  fi

  echo "Cloning repo from GitHub to $APP_DIR"
  git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$APP_DIR"
}

try_prepare_data_path() {
  local p="$1"
  [ -n "$p" ] || return 1
  mkdir -p "$p/characters" "$p/worlds" "$p/chats" 2>/dev/null || return 1
  touch "$p/.st_manager_rwtest" 2>/dev/null || return 1
  rm -f "$p/.st_manager_rwtest" || true
  DATA_PATH="$p"
  return 0
}

setup_shared_storage_permission() {
  [ "$SHARED_STORAGE_READY" = "1" ] && return 0
  SHARED_STORAGE_READY=1
  if command -v termux-setup-storage >/dev/null 2>&1; then
    echo "Requesting shared storage permission..."
    termux-setup-storage || true
  fi
}

fallback_data_path() {
  local candidate
  for candidate in \
    "$HOME/.st-manager/data/default-user" \
    "$APP_DIR/.data/default-user" \
    "/tmp/st-manager-data"; do
    if try_prepare_data_path "$candidate"; then
      echo "WARN: fallback to writable DATA_PATH=$candidate"
      return 0
    fi
  done
  return 1
}

resolve_data_path() {
  if [ -n "$DATA_PATH_INPUT" ]; then
    if try_prepare_data_path "$DATA_PATH_INPUT"; then
      return 0
    fi

    if [[ "$DATA_PATH_INPUT" == /storage/* ]]; then
      setup_shared_storage_permission
      if try_prepare_data_path "$DATA_PATH_INPUT"; then
        return 0
      fi
    fi

    echo "WARN: DATA_PATH is not accessible: $DATA_PATH_INPUT"
    if fallback_data_path; then
      return 0
    fi

    echo "ERROR: no writable fallback data path found"
    exit 1
  fi

  local candidate
  for candidate in \
    "$HOME/.st-manager/data/default-user" \
    "$HOME/.local/share/SillyTavern/default-user" \
    "/data/data/com.termux/files/home/.st-manager/data/default-user"; do
    if try_prepare_data_path "$candidate"; then
      return 0
    fi
  done

  setup_shared_storage_permission

  for candidate in \
    "/storage/emulated/0/SillyTavern/default-user" \
    "/storage/emulated/0/SillyTavern/data/default-user"; do
    if try_prepare_data_path "$candidate"; then
      return 0
    fi
  done

  for candidate in /storage/*-*/SillyTavern/default-user /storage/*-*/SillyTavern/data/default-user; do
    [ -d "$candidate" ] || continue
    if try_prepare_data_path "$candidate"; then
      return 0
    fi
  done

  if fallback_data_path; then
    return 0
  fi

  echo "ERROR: unable to find writable SillyTavern data path"
  exit 1
}

bootstrap_stage() {
  echo "[1/4] Install base packages (compat mode)"
  install_base_packages

  echo "[2/4] Pull latest code from GitHub"
  sync_repo_from_github

  echo "[3/4] Configure access mode"
  prompt_access_mode

  echo "[4/4] Switch to deploy stage"
  exec env INSTALL_STAGE=deploy \
    REPO_URL="$REPO_URL" \
    BRANCH="$BRANCH" \
    APP_DIR="$APP_DIR" \
    ST_MANAGER_HOST="$HOST" \
    PORT="$PORT" \
    DATA_PATH="$DATA_PATH_INPUT" \
    FORCE_NPM_INSTALL="$FORCE_NPM_INSTALL" \
    NPM_CACHE_DIR="$NPM_CACHE_DIR" \
    NPM_HEARTBEAT_SECONDS="$NPM_HEARTBEAT_SECONDS" \
    NPM_INSTALL_TIMEOUT_SECONDS="$NPM_INSTALL_TIMEOUT_SECONDS" \
    NPM_FETCH_RETRIES="$NPM_FETCH_RETRIES" \
    NPM_FETCH_RETRY_MINTIMEOUT="$NPM_FETCH_RETRY_MINTIMEOUT" \
    NPM_FETCH_RETRY_MAXTIMEOUT="$NPM_FETCH_RETRY_MAXTIMEOUT" \
    NPM_FETCH_TIMEOUT="$NPM_FETCH_TIMEOUT" \
    NPM_LOG_TAIL_LINES="$NPM_LOG_TAIL_LINES" \
    NPM_INSTALL_RETRY_COUNT="$NPM_INSTALL_RETRY_COUNT" \
    NPM_INSTALL_RETRY_DELAY_SECONDS="$NPM_INSTALL_RETRY_DELAY_SECONDS" \
    NPM_REGISTRY_PRIMARY="$NPM_REGISTRY_PRIMARY" \
    NPM_REGISTRY_FALLBACK="$NPM_REGISTRY_FALLBACK" \
    bash "$APP_DIR/install-termux.sh"
}

deploy_stage() {
  prompt_access_mode

  echo "[1/6] Prepare storage access (lazy mode)"
  echo "Shared storage permission will only be requested if /storage path is used."

  echo "[2/6] Resolve writable data path"
  resolve_data_path
  echo "Using DATA_PATH=$DATA_PATH"

  cat >"$APP_DIR/app-config.json" <<CONFIG_EOF
{
  "dataPath": "$DATA_PATH"
}
CONFIG_EOF

  echo "[3/6] Install Node dependencies for mobile runtime"
  install_node_dependencies
  ensure_webpack_runtime

  echo "[4/6] Apply executable permissions"
  chmod +x "$APP_DIR/install-termux.sh"
  chmod +x "$APP_DIR"/scripts/*.sh
  chmod +x "$APP_DIR/termux/runit/st-manager/run" "$APP_DIR/termux/runit/st-manager/log/run"

  echo "[5/6] Start service and run healthcheck"
  PORT="$PORT" bash "$APP_DIR/scripts/stop.sh" >/dev/null 2>&1 || true
  if ! ST_MANAGER_HOST="$HOST" PORT="$PORT" NODE_ENV=production DATA_ROOT="$DATA_PATH" bash "$APP_DIR/scripts/start.sh"; then
    echo
    echo "Initial start failed. Dumping diagnostics..."
    show_runtime_diagnostics

    local latest_log
    latest_log="$(ls -1t "$APP_DIR"/logs/app-*.log 2>/dev/null | head -n 1 || true)"
    if [ -n "${latest_log:-}" ] && grep -Eq "EADDRINUSE|address already in use" "$latest_log"; then
      echo
      echo "Detected port conflict, attempting one automatic restart..."
      PORT="$PORT" bash "$APP_DIR/scripts/stop.sh" >/dev/null 2>&1 || true
      sleep 1
      ST_MANAGER_HOST="$HOST" PORT="$PORT" NODE_ENV=production DATA_ROOT="$DATA_PATH" bash "$APP_DIR/scripts/start.sh"
    else
      exit 1
    fi
  fi

  if ! ST_MANAGER_HOST="$HOST" PORT="$PORT" RETRY_COUNT=12 RETRY_DELAY=2 bash "$APP_DIR/scripts/healthcheck.sh"; then
    echo
    echo "Healthcheck failed. Dumping quick diagnostics..."
    show_runtime_diagnostics
    echo "--- curl /api/config ---"
    curl -i -sS --max-time 10 "http://127.0.0.1:${PORT}/api/config" || true
    echo
    echo "Installer aborting due to unhealthy server."
    exit 1
  fi

  echo "[6/6] Enable runit supervision (optional but recommended)"
  if command -v sv-enable >/dev/null 2>&1; then
    sv-enable || true
  fi
  if command -v sv >/dev/null 2>&1; then
    bash "$APP_DIR/scripts/install-runit-service.sh" || true
  fi

  echo
  echo "Install complete."
  echo "LISTEN_HOST: $HOST"
  echo "URL(Local): http://127.0.0.1:${PORT}"
  if [ "$HOST" = "0.0.0.0" ]; then
    echo "URL(LAN/Public): http://<your-ip>:${PORT}"
  fi
  echo "APP_DIR: $APP_DIR"
  echo "DATA_PATH: $DATA_PATH"
  echo "Status: bash $APP_DIR/scripts/status.sh"
  echo "Stop:   bash $APP_DIR/scripts/stop.sh"
}

main() {
  if [ "$INSTALL_STAGE" = "bootstrap" ]; then
    bootstrap_stage
  fi
  deploy_stage
}

main "$@"
