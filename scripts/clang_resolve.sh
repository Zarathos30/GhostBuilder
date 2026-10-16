#!/bin/bash
# Print the latest "ref" for a clang variant on stdout (logs go to stderr).
#   cirrus / weebx / zyc -> latest tarball URL
#   aosp                 -> <android-tag>/<clang-rNNNNNN>  (newest tag, newest clang in it)
# setup_clang.sh and the cache key in action.yml both consume this value.
set -eo pipefail

V="${1:?usage: clang_resolve.sh <cirrus|weebx|zyc|aosp>}"
AOSP_BASE="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86"
AOSP_FALLBACK="android-17.0.0_r1/r596125"   # used only if AOSP lookup fails

log()   { echo "[clang_resolve] $*" >&2; }
fetch() { curl -fsSL --max-time 30 --retry 3 --retry-delay 5 --retry-all-errors "$@"; }

aosp_latest() {
  local tag ver
  tag=$(fetch "${AOSP_BASE}/+refs/tags?format=TEXT" \
        | grep -oE 'android-[0-9]+\.[0-9]+\.[0-9]+_r[0-9]+' | sort -uV | tail -1) || return 1
  [ -n "$tag" ] || return 1
  ver=$(fetch "${AOSP_BASE}/+/refs/tags/${tag}/?format=JSON" | python3 -c '
import sys, json, re
raw = sys.stdin.read()
data = json.loads(raw[raw.index("{"):])
best = None
for e in data.get("entries", []):
    m = re.fullmatch(r"clang-r(\d+)([a-z]*)", e.get("name", ""))
    if m:
        k = (int(m.group(1)), m.group(2))
        if best is None or k > best[0]:
            best = (k, "r%s%s" % (m.group(1), m.group(2)))
if not best:
    sys.exit(1)
print(best[1])
') || return 1
  [ -n "$ver" ] || return 1
  echo "${tag}/${ver}"
}

case "$V" in
  cirrus)
    auth=()
    [ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    fetch "${auth[@]}" https://api.github.com/repos/greenforce-project/greenforce_clang/releases/latest \
      | python3 -c '
import sys, json
d = json.load(sys.stdin)
url = next((a["browser_download_url"] for a in d.get("assets", []) if a["name"].endswith(".tar.gz")), "")
if not url:
    sys.exit(1)
print(url)
'
    ;;
  weebx)
    url=$(fetch https://raw.githubusercontent.com/XSans0/WeebX-Clang/main/main/link.txt | tr -d '[:space:]')
    [ -n "$url" ] || { log "WeebX link.txt is empty"; exit 1; }
    echo "$url"
    ;;
  zyc)
    url=$(fetch https://raw.githubusercontent.com/ZyCromerZ/Clang/main/Clang-main-link.txt | tr -d '[:space:]')
    [ -n "$url" ] || { log "ZyC link is empty"; exit 1; }
    echo "$url"
    ;;
  aosp)
    if ref=$(aosp_latest); then
      echo "$ref"
    else
      log "WARN: AOSP latest lookup failed, falling back to ${AOSP_FALLBACK}"
      echo "$AOSP_FALLBACK"
    fi
    ;;
  *)
    log "unknown variant: $V"; exit 1 ;;
esac
