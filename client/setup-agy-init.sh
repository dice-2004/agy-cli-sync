#!/bin/bash
# ============================================================
# setup-agy-init.sh - 初回セットアップ用（コンテナ初回のみ実行）
# 実行方法: bash /workspace/.local/setup-agy-init.sh
# ============================================================
set -e

SCRATCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGY_KEY="${SCRATCH_DIR}/agy_key"
AGY_BIN="${SCRATCH_DIR}/agy"
AGY_AUTH="${SCRATCH_DIR}/.gemini/antigravity-cli"
SYNC_SERVER="agysync@10.10.10.51"
SYNC_PORT="2222"
CONVERSATIONS_DIR="${HOME}/.gemini/antigravity-cli/conversations"

# ============================================================
# sudo/root判定
# ============================================================
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    SUDO="sudo"
else
    SUDO=""
fi

run_as_root() {
    if [ -n "$SUDO" ]; then
        $SUDO "$@"
    else
        "$@"
    fi
}

echo "[1/5] バイナリのセットアップ..."
run_as_root ln -sf "${AGY_BIN}" /usr/local/bin/agy
chmod +x "${AGY_BIN}"

echo "[2/5] 認証情報のセットアップ..."
mkdir -p "${HOME}/.gemini/antigravity-cli"
run_as_root ln -sf "${AGY_AUTH}" "${HOME}/.gemini/antigravity-cli/antigravity-cli"

echo "[3/5] rsyncの確認..."

if command -v rsync >/dev/null 2>&1; then
    echo "✓ rsync は既にインストールされています。"
else
    echo "rsync が見つからないためインストールします..."

    if command -v apt-get >/dev/null 2>&1; then
        if [ -n "$SUDO" ] || [ "$(id -u)" -eq 0 ]; then
            run_as_root apt-get update -qq
            run_as_root apt-get install -y -qq rsync
        else
            echo "ERROR: rsync がありません。"
            echo "この環境では sudo/root 権限がないためインストールできません。"
            echo "管理者に rsync のインストールを依頼してください。"
            exit 1
        fi
    else
        echo "ERROR: apt-get が存在しません。"
        echo "rsync を手動でインストールしてください。"
        exit 1
    fi
fi

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
