#!/bin/bash

TOKEN="${TELEGRAM_TOKEN:?}"
CHAT_ID="${TELEGRAM_CHAT_ID:?}"
ESTIMATED_TOTAL=${1:-2400}
BUILD_START=${2:-$(date +%s)}

send() {
  local pct=$1
  local remaining=$2
  local mins=$((remaining / 60))
  local secs=$((remaining % 60))
  curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
    -d chat_id="${CHAT_ID}" \
    -d parse_mode="HTML" \
    -d disable_notification=true \
    -d text="🔄 <b>Build ${pct}%</b> — ⏱️ ~${mins}m ${secs}s remaining" > /dev/null
}

# 0% immediately
send 0 "$((ESTIMATED_TOTAL / 60 * 60))"

for pct in 25 50 75; do
  TARGET=$((BUILD_START + ESTIMATED_TOTAL * pct / 100))
  SLEEP=$((TARGET - $(date +%s)))
  [ "$SLEEP" -gt 0 ] && sleep "$SLEEP"

  elapsed=$(($(date +%s) - BUILD_START))
  actual_total=$((elapsed * 100 / pct))
  remaining=$((actual_total - elapsed))
  [ "$remaining" -lt 0 ] && remaining=0

  send "$pct" "$remaining"
done
