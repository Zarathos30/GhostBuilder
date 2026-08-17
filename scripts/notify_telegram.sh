#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/functions.sh"

if [ -f "${GITHUB_WORKSPACE}/build_skipped.marker" ]; then
  SKIP_REPLY=$(curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
    -d chat_id="${TELEGRAM_CHAT_ID}" \
    -d parse_mode="HTML" \
    -d "text=⏭️ <b>Build skipped</b> — root/SUSFS component unavailable (pin mancante, no candidate). No kernel produced.") || true
  echo "$SKIP_REPLY" | grep -q '"ok":true' || warn "Failed to send skip notification."
  exit 0
fi

KERNEL_DIR="${GITHUB_WORKSPACE}/kernel-source"
ZIP_PATH="${KERNEL_DIR}/GhostKernel-Release/${ZIP_NAME}"

esc() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

get_raw_log() {
  local repo_dir="$1" tag_name="$2"
  (cd "$repo_dir" && git fetch origin "+refs/tags/${tag_name}:refs/tags/${tag_name}" 2>/dev/null || true)
  if (cd "$repo_dir" && git rev-parse "$tag_name" >/dev/null 2>&1); then
    (cd "$repo_dir" && git log "${tag_name}..HEAD" --no-merges --pretty=format:"%B%x1e" || true)
  else
    (cd "$repo_dir" && git log -10 --no-merges --pretty=format:"%B%x1e" || true)
  fi
}

format_changelog() {
  local raw_log="$1"
  local -A groups
  local order=(added fixed changed)
  local -A labels=( [added]="✨ Added" [fixed]="🐛 Fixed" [changed]="🔧 Changed" )
  local commit_body subject type desc key trailer_val

  while IFS= read -r -d $'\x1e' commit_body; do
    [ -z "$commit_body" ] && continue
    subject=$(head -n1 <<< "$commit_body")
    echo "$subject" | grep -qi '\[ci\]' && continue

    trailer_val=$(grep -iP '^Changelog:\s*' <<< "$commit_body" | tail -1 | sed -E 's/^Changelog:\s*//I')
    if [ -n "$trailer_val" ]; then
      shopt -s nocasematch
      if [[ "$trailer_val" == "skip" ]]; then
        shopt -u nocasematch
        continue
      fi
      shopt -u nocasematch
    fi

    type=$(echo "$subject" | grep -oP '^[a-zA-Z]+(?=(\([^)]*\))?:)' || true)
    type=$(echo "$type" | tr '[:upper:]' '[:lower:]')

    if [ -n "$trailer_val" ]; then
      desc="$trailer_val"
    else
      desc="$subject"
      while echo "$desc" | grep -qP '^[a-zA-Z]+(\([^)]*\))?:\s*'; do
        desc=$(echo "$desc" | sed -E 's/^[a-zA-Z]+(\([^)]*\))?:\s*//')
      done
    fi
    desc="$(tr '[:lower:]' '[:upper:]' <<< "${desc:0:1}")${desc:1}"
    [ -z "$desc" ] && continue
    desc=$(esc "$desc")

    case "$type" in
      feat) key="added" ;;
      fix)  key="fixed" ;;
      *)    key="changed" ;;
    esac
    groups[$key]="${groups[$key]}• ${desc}\n"
  done <<< "$raw_log"

  local out=""
  for key in "${order[@]}"; do
    if [ -n "${groups[$key]:-}" ]; then
      out="${out}<b>${labels[$key]}:</b>\n$(printf '%b' "${groups[$key]}")\n"
    fi
  done
  printf '%s' "$out"
}

KERNEL_RAW=$(get_raw_log "$KERNEL_DIR" "ghostkernel-last-notified")
KERNEL_CL=$(format_changelog "$KERNEL_RAW")

CHANGELOG_TEXT=""
[ -n "$KERNEL_CL" ]  && CHANGELOG_TEXT="${CHANGELOG_TEXT}<b>🧬 Kernel Changes:</b>\n${KERNEL_CL}"
[ -z "$CHANGELOG_TEXT" ] && CHANGELOG_TEXT="No changes since last build.\n"

case "$INPUT_VARIANT" in
  stock) VARIANT_LABEL="📦 Stock (No Root)" ;;
  root)  VARIANT_LABEL="🔓 Root Only » ${ACTUAL_ROOT:-?}" ;;
  susfs) VARIANT_LABEL="🛡️ SUSFS » ${ACTUAL_ROOT:-?}" ;;
  *)     VARIANT_LABEL="${INPUT_VARIANT:-unknown}" ;;
esac

FILE_SIZE=$(du -h "$ZIP_PATH" | cut -f1)
SHA256_FULL=$(sha256sum "$ZIP_PATH" | cut -d' ' -f1)

BUILD_DATE=$(date -u "+%Y-%m-%d %H:%M UTC")

DUR="${BUILD_DURATION_SEC:-0}"
DUR_TEXT="$((DUR / 60))m $((DUR % 60))s"

CHANGELOG_TEXT="$(printf '%b' "$CHANGELOG_TEXT" | sed '/^$/d')"

CAPTION="🔧 <b>Ghost Kernel Build</b>

📦 <code>${KERNEL_VER}</code> · ${VARIANT_LABEL}
🔢 ${HZ_ID} Hz · 🔗 LTO: ${LTO_ACTUAL}
⚙️ ${KBUILD_COMPILER_STRING}
⏱️ ${DUR_TEXT} · 💾 ${FILE_SIZE}
🔐 <code>${SHA256_FULL}</code>
${CHANGELOG_TEXT}
📅 ${BUILD_DATE}"

# Truncate if over 1024 chars (Telegram caption limit)
MAX_CAPTION=1000
if [ ${#CAPTION} -gt $MAX_CAPTION ]; then
  CAPTION="${CAPTION:0:$MAX_CAPTION}..."
fi

SEND_DOC=$(curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendDocument" \
  -F chat_id="${TELEGRAM_CHAT_ID}" \
  -F parse_mode="HTML" \
  -F caption="${CAPTION}" \
  -F document=@"${ZIP_PATH}")

update_tag() {
  local repo_dir="$1" tag_name="$2"
  (cd "$repo_dir" && git tag -f "$tag_name" && git push origin "$tag_name" --force 2>/dev/null) || warn "Failed to push tag $tag_name in $repo_dir"
}

if echo "$SEND_DOC" | grep -q '"ok":true'; then
  log "Telegram notification sent."
  update_tag "$KERNEL_DIR" "ghostkernel-last-notified"
else
  warn "Failed to send file. Response:"
  echo "$SEND_DOC"
  exit 1
fi
