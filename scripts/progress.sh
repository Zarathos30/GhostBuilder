#!/bin/bash

TOKEN="${TELEGRAM_TOKEN:?}"
CHAT_ID="${TELEGRAM_CHAT_ID:?}"
ESTIMATED_TOTAL=${1:-2400}
BUILD_START=${2:-$(date +%s)}

send() {
  local pct=$1
  local elapsed=$(($(date +%s) - BUILD_START))
  local mins=$((elapsed / 60))
  local secs=$((elapsed % 60))
  curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
    -d chat_id="${CHAT_ID}" \
    -d parse_mode="HTML" \
    -d disable_notification=true \
    -d text="🔄 <b>Build ${pct}%</b> — ⏱️ ${mins}m ${secs}s" > /dev/null
}

send 0

for pct in 25 50 75; do
  TARGET=$((BUILD_START + ESTIMATED_TOTAL * pct / 100))
  SLEEP=$((TARGET - $(date +%s)))
  [ "$SLEEP" -gt 0 ] && sleep "$SLEEP"
  send "$pct"
done
