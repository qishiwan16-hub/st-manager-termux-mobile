#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

pkg update -y
pkg upgrade -y
pkg install -y nodejs-lts git curl jq tmux termux-api termux-services lsof cronie rsync
termux-setup-storage

echo "bootstrap complete"
echo "next: copy project into ~/apps/st-manager-termux-mobile and run npm install --omit=dev"
