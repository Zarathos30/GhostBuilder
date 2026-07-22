#!/bin/bash
set -e

LOG_FILE="${GITHUB_WORKSPACE}/build.log"
RUN_URL="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
FAIL_LOG="${GITHUB_WORKSPACE}/build-failure.log"

{
  echo "GhostKernel Build Failure Log"
  echo "Run: ${RUN_URL}"
  echo "========================================"
  echo ""
  if [ -f "$LOG_FILE" ]; then
    cat "$LOG_FILE"
  else
    echo "Build log file not found."
  fi
} > "$FAIL_LOG"

CAPTION="❌ <b>Build Failed!</b>
<a href=\"${RUN_URL}\">🔗 Full log on GitHub Actions</a>"

curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendDocument" \
  -F chat_id="${TELEGRAM_CHAT_ID}" \
  -F parse_mode="HTML" \
  -F caption="$CAPTION" \
  -F document=@"${FAIL_LOG}" > /dev/null
