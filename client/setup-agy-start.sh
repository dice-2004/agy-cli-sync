#!/bin/bash
# ============================================================
# setup-agy-start.sh - 常時同期プロセス (プロセス監視＋直前二重チェック)
#
# 設計方針:
#   - プロセス監視方式＋同期直前の二重再チェック＋終了検知後の即時同期
#   - agy 起動時・停止時に明確なログを出力
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
SYNC_PID_FILE="${HOME}/.gemini/antigravity-cli/.sync_loop.pid"

# 重複起動のチェック (PIDロックファイル)
if [ -f "${SYNC_PID_FILE}" ]; then
  OLD_PID="$(cat "${SYNC_PID_FILE}" 2>/dev/null || echo "")"
  if [ -n "${OLD_PID}" ] && kill -0 "${OLD_PID}" 2>/dev/null; then
    echo "✓ 同期プロセスは既にバックグラウンドで起動しています。(PID: ${OLD_PID})"
    exit 0
  fi
fi

run_sync_loop() {
  echo $$ > "${SYNC_PID_FILE}"
  trap 'rm -f "${SYNC_PID_FILE}"' EXIT

  local was_running=0

  while true; do
    # 1. 一次チェック: agy プロセスが動作中なら一時停止ログを出力してスリープ
    if pgrep -x "agy" >/dev/null 2>&1 || pgrep -f "antigravity" >/dev/null 2>&1; then
      if [ "${was_running}" -eq 0 ]; then
        echo "[agy-sync] agy の起動を検出しました。同期を一時停止（ポーズ）します。"
        was_running=1
      fi
      sleep 1
      continue
    fi

    # 2. agy 終了直後の検出: 1回確定同期
    if [ "${was_running}" -eq 1 ]; then
      echo "[agy-sync] agy の終了を検出しました。会話データを即時同期中..."
      if [ -f "${AGY_KEY}" ]; then
        rsync -az --update \
          -e "ssh -p ${SYNC_PORT} -i ${AGY_KEY} -o StrictHostKeyChecking=no" \
          "${CONVERSATIONS_DIR}/" \
          "${SYNC_SERVER}:/data/brain/" 2>/dev/null || true

        rsync -az --update \
          -e "ssh -p ${SYNC_PORT} -i ${AGY_KEY} -o StrictHostKeyChecking=no" \
          "${SYNC_SERVER}:/data/brain/" \
          "${CONVERSATIONS_DIR}/" 2>/dev/null || true
      fi
      echo "[agy-sync] 会話後同期が完了しました。通常同期へ復帰します。"
      was_running=0
    fi

    # 3. 直前二次チェック: rsync 呼び出し直前に再度プロセス状態を確認
    if pgrep -x "agy" >/dev/null 2>&1 || pgrep -f "antigravity" >/dev/null 2>&1; then
      if [ "${was_running}" -eq 0 ]; then
        echo "[agy-sync] agy の起動を検出しました。同期を一時停止（ポーズ）します。"
        was_running=1
      fi
      sleep 1
      continue
    fi

    # 4. 通常同期: agy が動作していない時のみ双方向同期を実行
    if [ -f "${AGY_KEY}" ]; then
      rsync -az --update \
        -e "ssh -p ${SYNC_PORT} -i ${AGY_KEY} -o StrictHostKeyChecking=no" \
        "${CONVERSATIONS_DIR}/" \
        "${SYNC_SERVER}:/data/brain/" 2>/dev/null || true

      rsync -az --update \
        -e "ssh -p ${SYNC_PORT} -i ${AGY_KEY} -o StrictHostKeyChecking=no" \
        "${SYNC_SERVER}:/data/brain/" \
        "${CONVERSATIONS_DIR}/" 2>/dev/null || true
    fi

    sleep 2
  done
}

# インタラクティブシェル呼び出し時はバックグラウンド化、systemd 呼び出し時はフォアグラウンド実行
if [ -t 1 ] || [ -z "${INVOCATION_ID:-}" ]; then
  run_sync_loop &
  echo "✓ 常時同期プロセスをバックグラウンド起動しました。(PID: $!)"
else
  run_sync_loop
fi
