#!/bin/bash
set -e

TOKEN="${TELEGRAM_TOKEN:?TELEGRAM_TOKEN not set}"
CHAT_ID="${TELEGRAM_CHAT_ID:?TELEGRAM_CHAT_ID not set}"

UPDATES=$(curl -s "https://api.telegram.org/bot${TOKEN}/getUpdates?timeout=5&allowed_updates=channel_post")

echo "DEBUG: Telegram response:"
echo "$UPDATES" | python3 -c "import json,sys; d=json.load(sys.stdin); print(f'ok={d.get(\"ok\")}, updates={len(d.get(\"result\",[]))}')" 2>/dev/null || echo "$UPDATES" | head -c 500
echo "DEBUG: CHAT_ID=${CHAT_ID}"

MATCHES=$(echo "$UPDATES" | python3 -c "
import json, sys
chat_id = '$CHAT_ID'
data = json.load(sys.stdin)
for r in data.get('result', []):
    cp = r.get('channel_post', {})
    cid = str(cp.get('chat', {}).get('id', ''))
    text = cp.get('text', '')
    if chat_id == cid and text:
        print(text)
")

if echo "$MATCHES" | grep -qiE '^/(build|compila)\b.*(ghost|kernel)'; then
  echo "[+] Build command detected from Telegram!"

  curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
    -d chat_id="${CHAT_ID}" \
    -d text="🚀 Build avviata! Segui qui: https://github.com/${GITHUB_REPOSITORY}/actions" \
    -d disable_notification=true > /dev/null

  curl -s -X POST \
    -H "Authorization: Bearer ${GH_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${GITHUB_REPOSITORY}/actions/workflows/build.yml/dispatches" \
    -d '{"ref":"main"}'

  echo "[+] Workflow dispatched!"
else
  echo "[-] No build command found"
fi
