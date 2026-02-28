#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/qishiwan16-hub/st-manager-termux-mobile.git}"
BRANCH="${BRANCH:-main}"
APP_DIR="${APP_DIR:-$HOME/apps/st-manager-termux-mobile}"
INSTALL_STAGE="${INSTALL_STAGE:-bootstrap}"
HOST="${HOSTNAME:-127.0.0.1}"
PORT="${PORT:-3456}"
DATA_PATH_INPUT="${DATA_PATH:-}"
DATA_PATH=""

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

resolve_data_path() {
  if [ -n "$DATA_PATH_INPUT" ]; then
    if try_prepare_data_path "$DATA_PATH_INPUT"; then
      return 0
    fi
    echo "ERROR: DATA_PATH is not accessible: $DATA_PATH_INPUT"
    echo "Tip: use /storage/emulated/0/SillyTavern/default-user"
    exit 1
  fi

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
  echo "Set it manually: DATA_PATH=/storage/emulated/0/SillyTavern/default-user bash install-termux.sh"
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
    HOSTNAME="$HOST" \
    PORT="$PORT" \
    DATA_PATH="$DATA_PATH_INPUT" \
    bash "$APP_DIR/install-termux.sh"
fi

echo "[1/6] Setup Android shared storage permission"
if command -v termux-setup-storage >/dev/null 2>&1; then
  termux-setup-storage || true
fi

echo "[2/6] Resolve writable data path"
resolve_data_path
echo "Using DATA_PATH=$DATA_PATH"

cat >"$APP_DIR/app-config.json" <<EOF
{
  "dataPath": "$DATA_PATH"
}
EOF

echo "[3/6] Install Node dependencies for mobile runtime"
cd "$APP_DIR"
rm -rf node_modules
npm install --omit=dev

echo "[4/6] Apply executable permissions"
chmod +x install-termux.sh
chmod +x scripts/*.sh
chmod +x termux/runit/st-manager/run termux/runit/st-manager/log/run

echo "[5/6] Start service and run healthcheck"
HOSTNAME="$HOST" PORT="$PORT" NODE_ENV=production DATA_ROOT="$DATA_PATH" bash scripts/start.sh
sleep 2
HOSTNAME="$HOST" PORT="$PORT" bash scripts/healthcheck.sh

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
