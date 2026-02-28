#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/qishiwan16-hub/st-manager-termux-mobile.git}"
BRANCH="${BRANCH:-main}"
APP_DIR="${APP_DIR:-$HOME/apps/st-manager-termux-mobile}"
INSTALL_STAGE="${INSTALL_STAGE:-bootstrap}"
HOST="${ST_MANAGER_HOST:-127.0.0.1}"
PORT="${PORT:-3456}"
DATA_PATH_INPUT="${DATA_PATH:-}"
DATA_PATH=""
FORCE_NPM_INSTALL="${FORCE_NPM_INSTALL:-0}"
SHARED_STORAGE_READY=0

dependency_signature() {
  local hash_cmd=""
  local node_ver
  local npm_ver
  node_ver="$(node -v 2>/dev/null || echo unknown-node)"
  npm_ver="$(npm -v 2>/dev/null || echo unknown-npm)"

  if command -v sha256sum >/dev/null 2>&1; then
    hash_cmd="sha256sum"
  elif command -v shasum >/dev/null 2>&1; then
    hash_cmd="shasum -a 256"
  elif command -v md5sum >/dev/null 2>&1; then
    hash_cmd="md5sum"
  else
    # Last-resort fallback when hash utilities are unavailable.
    node -e 'const fs=require("fs");const crypto=require("crypto");const app=process.argv[1];const nodeV=process.argv[2];const npmV=process.argv[3];let s=`node=${nodeV}\nnpm=${npmV}\n`;for(const f of ["package.json","package-lock.json"]){const p=`${app}/${f}`;if(fs.existsSync(p))s+=fs.readFileSync(p,"utf8")}process.stdout.write(crypto.createHash("sha256").update(s).digest("hex"))' "$APP_DIR" "$node_ver" "$npm_ver"
    return 0
  fi

  {
    echo "node=$node_ver"
    echo "npm=$npm_ver"
    if [ -f "$APP_DIR/package.json" ]; then
      cat "$APP_DIR/package.json"
    fi
    if [ -f "$APP_DIR/package-lock.json" ]; then
      cat "$APP_DIR/package-lock.json"
    fi
    :
  } | sh -c "$hash_cmd" | awk '{print $1}'
}

install_node_dependencies() {
  local stamp_file="$APP_DIR/.deps-installed.sig"
  local sig_current
  local sig_saved=""
  local use_npm_ci=0

  sig_current="$(dependency_signature)"
  [ -f "$stamp_file" ] && sig_saved="$(cat "$stamp_file" 2>/dev/null || true)"

  if [ "$FORCE_NPM_INSTALL" != "1" ] && [ -d "$APP_DIR/node_modules" ] && [ "$sig_current" = "$sig_saved" ]; then
    echo "Dependencies unchanged, skipping npm install."
    return 0
  fi

  if [ -f "$APP_DIR/package-lock.json" ]; then
    use_npm_ci=1
  fi

  if [ "$use_npm_ci" = "1" ]; then
    echo "Installing dependencies with: npm ci --omit=dev"
  else
    echo "Installing dependencies with: npm install --omit=dev"
  fi

  cd "$APP_DIR"
  if [ "$use_npm_ci" = "1" ]; then
    npm ci --omit=dev
  else
    npm install --omit=dev
  fi
  echo "$sig_current" >"$stamp_file"
}

ensure_webpack_runtime() {
  local runtime_file="$APP_DIR/.next/server/webpack-runtime.js"
  if [ -f "$runtime_file" ]; then
    return 0
  fi

  echo "WARN: missing $runtime_file, creating fallback runtime"
  mkdir -p "$APP_DIR/.next/server"
  cat >"$runtime_file" <<'EOF'
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
EOF
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
    echo "ERROR: DATA_PATH is not accessible: $DATA_PATH_INPUT"
    echo "Tip: use either $HOME/.st-manager/data/default-user or /storage/emulated/0/SillyTavern/default-user"
    exit 1
  fi

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

  for mount in /storage/*-*; do
    [ -d "$mount" ] || continue
    for candidate in \
      "$mount/SillyTavern/default-user" \
      "$mount/SillyTavern/data/default-user"; do
      if try_prepare_data_path "$candidate"; then
        return 0
      fi
    done
  done

  echo "ERROR: unable to find writable SillyTavern data path"
  echo "Set it manually: DATA_PATH=$HOME/.st-manager/data/default-user bash install-termux.sh"
  exit 1
}

if [ "$INSTALL_STAGE" = "bootstrap" ]; then
  echo "[1/3] Install Termux base packages"
  pkg update -y
  pkg upgrade -y
  pkg install -y nodejs-lts git curl jq tmux termux-api termux-services lsof cronie

  echo "[2/3] Pull latest code from GitHub"
  sync_repo_from_github

  echo "[3/3] Switch to deploy stage"
  exec env INSTALL_STAGE=deploy \
    REPO_URL="$REPO_URL" \
    BRANCH="$BRANCH" \
    APP_DIR="$APP_DIR" \
    ST_MANAGER_HOST="$HOST" \
    PORT="$PORT" \
    DATA_PATH="$DATA_PATH_INPUT" \
    bash "$APP_DIR/install-termux.sh"
fi

echo "[1/6] Prepare storage access (lazy mode)"
echo "Shared storage permission will only be requested if /storage path is used."

echo "[2/6] Resolve writable data path"
resolve_data_path
echo "Using DATA_PATH=$DATA_PATH"

cat >"$APP_DIR/app-config.json" <<EOF
{
  "dataPath": "$DATA_PATH"
}
EOF

echo "[3/6] Install Node dependencies for mobile runtime"
install_node_dependencies
ensure_webpack_runtime

echo "[4/6] Apply executable permissions"
chmod +x install-termux.sh
chmod +x scripts/*.sh
chmod +x termux/runit/st-manager/run termux/runit/st-manager/log/run

echo "[5/6] Start service and run healthcheck"
ST_MANAGER_HOST="$HOST" PORT="$PORT" NODE_ENV=production DATA_ROOT="$DATA_PATH" bash scripts/start.sh
if ! ST_MANAGER_HOST="$HOST" PORT="$PORT" RETRY_COUNT=12 RETRY_DELAY=2 bash scripts/healthcheck.sh; then
  echo
  echo "Healthcheck failed. Dumping quick diagnostics..."
  echo "--- app-config.json ---"
  cat "$APP_DIR/app-config.json" || true
  echo "--- status ---"
  PORT="$PORT" bash "$APP_DIR/scripts/status.sh" || true
  latest_log="$(ls -1t "$APP_DIR"/logs/app-*.log 2>/dev/null | head -n 1 || true)"
  if [ -n "${latest_log:-}" ]; then
    echo "--- tail: $latest_log ---"
    tail -n 120 "$latest_log" || true
  fi
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
  bash scripts/install-runit-service.sh || true
fi

echo
echo "Install complete."
echo "URL: http://127.0.0.1:${PORT}"
echo "APP_DIR: $APP_DIR"
echo "DATA_PATH: $DATA_PATH"
echo "Status: bash $APP_DIR/scripts/status.sh"
echo "Stop:   bash $APP_DIR/scripts/stop.sh"
