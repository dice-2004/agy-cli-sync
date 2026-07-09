#!/bin/bash
# ============================================================
# setup-agy-start.sh - 2回目以降のコンテナ起動時用
# （rsyncインストール・シンボリックリンク作成済みの前提）
# 実行方法: bash /workspace/.local/setup-agy-start.sh
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
SYNC_SERVER="agysync@10.10.10.51"
SYNC_PORT="2222"
CONVERSATIONS_DIR="${HOME}/.gemini/antigravity-cli/conversations"

echo "[1/3] バイナリ・認証情報のリンク確認..."
$SUDO ln -sf "${SCRATCH_DIR}/agy" /usr/local/bin/agy
mkdir -p "${HOME}/.gemini/antigravity-cli"
ln -sf "${SCRATCH_DIR}/.gemini/antigravity-cli" "${HOME}/.gemini/antigravity-cli/antigravity-cli"

echo "[2/3] 会話データのPull..."
mkdir -p "${CONVERSATIONS_DIR}"
rsync -az --update \
  -e "ssh -p ${SYNC_PORT} -i ${AGY_KEY} -o StrictHostKeyChecking=no" \
  "${SYNC_SERVER}:/data/brain/" \
  "${CONVERSATIONS_DIR}/"

echo "[3/3] 常時同期をバックグラウンドで起動..."
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

echo "✓ 起動完了。agy コマンドが使用可能です。(sync PID: $!)"
