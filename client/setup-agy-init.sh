#!/bin/bash
# ============================================================
# setup-agy-init.sh - 初回セットアップスクリプト
# 実行方法: bash /path/to/setup-agy-init.sh
# ============================================================
set -e

SCRATCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGY_KEY="${SCRATCH_DIR}/agy_key"
if [ ! -f "${AGY_KEY}" ] && [ -f "${HOME}/.ssh/agy_key" ]; then
  AGY_KEY="${HOME}/.ssh/agy_key"
fi

SYNC_SERVER="agysync@10.10.10.51"
SYNC_PORT="2222"
CONVERSATIONS_DIR="${HOME}/.gemini/antigravity-cli/conversations"
AGY_AUTH_SOURCE="${SCRATCH_DIR}/.gemini/antigravity-cli"

# ↓ ここから追加
echo "[+] agy コマンドのリンク作成..."
if [ -f "${SCRATCH_DIR}/agy" ]; then
  chmod +x "${SCRATCH_DIR}/agy"
  if [ "$(id -u)" -eq 0 ]; then
    ln -sf "${SCRATCH_DIR}/agy" /usr/local/bin/agy
  elif command -v sudo >/dev/null 2>&1; then
    sudo ln -sf "${SCRATCH_DIR}/agy" /usr/local/bin/agy
  fi
fi

echo "[+] 認証情報のリンク作成..."
mkdir -p "${HOME}/.gemini/antigravity-cli"
if [ -d "${AGY_AUTH_SOURCE}" ]; then
  ln -sf "${AGY_AUTH_SOURCE}"/* "${HOME}/.gemini/antigravity-cli/" 2>/dev/null || true
fi
# ↑ ここまで追加

echo "[1/3] rsync の確認..."
if command -v rsync >/dev/null 2>&1; then
  echo "✓ rsync は既にインストールされています。"
else
  echo "rsync が見つからないためインストールします..."
  if command -v apt-get >/dev/null 2>&1; then
    if [ "$(id -u)" -eq 0 ]; then
      apt-get update -qq && apt-get install -y -qq rsync
    elif command -v sudo >/dev/null 2>&1; then
      sudo apt-get update -qq && sudo apt-get install -y -qq rsync
    else
      echo "ERROR: rsync がありません。手動で rsync をインストールしてください。" >&2
      exit 1
    fi
  else
    echo "ERROR: apt-get が存在しません。手動で rsync をインストールしてください。" >&2
    exit 1
  fi
fi

echo "[2/3] 会話データの初回 Pull..."
mkdir -p "${CONVERSATIONS_DIR}"
if [ -f "${AGY_KEY}" ]; then
  rsync -az --update \
    -e "ssh -p ${SYNC_PORT} -i ${AGY_KEY} -o StrictHostKeyChecking=no" \
    "${SYNC_SERVER}:/data/brain/" \
    "${CONVERSATIONS_DIR}/" 2>/dev/null || true
fi

echo "[3/3] 常時同期プロセスの起動..."
bash "${SCRATCH_DIR}/setup-agy-start.sh"
