#!/bin/bash
set -e

TOKEN="${TELEGRAM_TOKEN:?TELEGRAM_TOKEN not set}"
CHAT_ID="${TELEGRAM_CHAT_ID:?TELEGRAM_CHAT_ID not set}"

UPDATES=$(curl -s "https://api.telegram.org/bot${TOKEN}/getUpdates?timeout=5&allowed_updates=channel_post")

MATCHES=$(echo "$UPDATES" | jq -r --arg chat "$CHAT_ID" '
  .result[] |
  select(.channel_post.chat.id == ($chat | tonumber)) |
  .channel_post.text // empty
')

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
