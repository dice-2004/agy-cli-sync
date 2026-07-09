#!/bin/bash
# ============================================================
# setup-agy-init.sh - 初回セットアップ用（コンテナ初回のみ実行）
# 実行方法: bash /workspace/.local/setup-agy-init.sh
# ============================================================
set -e

# rootかどうかでsudoを切り替え
if [ "$(id -u)" = "0" ]; then
  SUDO=""
else
  SUDO="sudo"
fi

SCRATCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGY_KEY="${SCRATCH_DIR}/agy_key"
AGY_BIN="${SCRATCH_DIR}/agy"
AGY_AUTH="${SCRATCH_DIR}/.gemini/antigravity-cli"
SYNC_SERVER="agysync@10.10.10.51"
SYNC_PORT="2222"
CONVERSATIONS_DIR="${HOME}/.gemini/antigravity-cli/conversations"

echo "[1/5] バイナリのセットアップ..."
$SUDO ln -sf "${AGY_BIN}" /usr/local/bin/agy
chmod +x "${AGY_BIN}"

echo "[2/5] 認証情報のセットアップ..."
mkdir -p "${HOME}/.gemini/antigravity-cli"
ln -sf "${AGY_AUTH}" "${HOME}/.gemini/antigravity-cli/antigravity-cli"

echo "[3/5] rsyncのインストール..."
$SUDO apt-get update -qq && $SUDO apt-get install -y -qq rsync

echo "[4/5] 会話データの初回Pull..."
mkdir -p "${CONVERSATIONS_DIR}"
rsync -az --update \
  -e "ssh -p ${SYNC_PORT} -i ${AGY_KEY} -o StrictHostKeyChecking=no" \
  "${SYNC_SERVER}:/data/brain/" \
  "${CONVERSATIONS_DIR}/"

echo "[5/5] 常時同期をバックグラウンドで起動..."
while true; do
  rsync -az --update \
    -e "ssh -p ${SYNC_PORT} -i ${AGY_KEY} -o StrictHostKeyChecking=no" \
    "${CONVERSATIONS_DIR}/" \
    "${SYNC_SERVER}:/data/brain/" 2>/dev/null
  rsync -az --update \
    -e "ssh -p ${SYNC_PORT} -i ${AGY_KEY} -o StrictHostKeyChecking=no" \
    "${SYNC_SERVER}:/data/brain/" \
    "${CONVERSATIONS_DIR}/" 2>/dev/null
  sleep 2
done &

echo "✓ セットアップ完了。agy コマンドが使用可能です。(sync PID: $!)"
