#!/bin/bash
set -e

LOG_FILE="${GITHUB_WORKSPACE}/build.log"
RUN_URL="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"

if [ -f "$LOG_FILE" ]; then
  LOG_TAIL=$(tail -c 3500 "$LOG_FILE" 2>/dev/null || echo "No log available.")
else
  LOG_TAIL="Build log file not found."
fi

LOG_TAIL="${LOG_TAIL//&/&amp;}"
LOG_TAIL="${LOG_TAIL//</&lt;}"
LOG_TAIL="${LOG_TAIL//>/&gt;}"

MSG="❌ <b>Build Failed!</b>

<pre>${LOG_TAIL}</pre>

<a href=\"${RUN_URL}\">🔗 Full log on GitHub Actions</a>"

curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
  -d chat_id="${TELEGRAM_CHAT_ID}" \
  -d parse_mode="HTML" \
  --data-urlencode text="$MSG" > /dev/null
