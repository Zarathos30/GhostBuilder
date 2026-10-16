#!/bin/bash
# Sync NoMount to the latest upstream before compile (only when NOMOUNT=on).
# Ref defaults to branch "dev"; override with NOMOUNT_REF (branch, tag, or SHA).
# On any failure, keep the NoMount copy already committed in the kernel tree.
set -e

if [ "$NOMOUNT" != "on" ]; then
  echo "[nomount] disabled, skipping sync"
  return 0
fi

NOMOUNT_REPO="https://github.com/maxsteeel/nomount.git"
NOMOUNT_REF="${NOMOUNT_REF:-dev}"
NOMOUNT_TMP="$(mktemp -d)"

_nomount_fallback() {
  echo "[nomount] WARN: $1 — using NoMount already in kernel tree"
  echo "NOMOUNT_SHA=in-tree" >> "$GITHUB_ENV"
  rm -rf "$NOMOUNT_TMP"
  return 0
}

echo "[nomount] syncing ${NOMOUNT_REF} from ${NOMOUNT_REPO}"

if ! timeout 120 git clone --quiet --depth=1 -b "$NOMOUNT_REF" "$NOMOUNT_REPO" "$NOMOUNT_TMP/nomount" 2>/dev/null; then
  # NOMOUNT_REF may be a bare commit SHA, which --depth=1 -b cannot clone
  rm -rf "$NOMOUNT_TMP/nomount"
  if ! { timeout 120 git clone --quiet "$NOMOUNT_REPO" "$NOMOUNT_TMP/nomount" \
         && git -C "$NOMOUNT_TMP/nomount" checkout --quiet "$NOMOUNT_REF"; } 2>/dev/null; then
    _nomount_fallback "clone/checkout of '$NOMOUNT_REF' failed"
    return 0
  fi
fi

NM_SRC="$NOMOUNT_TMP/nomount/kernel/src"
if [ ! -f "$NM_SRC/Kconfig" ] || [ ! -f "$NM_SRC/Makefile" ]; then
  _nomount_fallback "upstream kernel/src layout changed (Kconfig/Makefile missing)"
  return 0
fi

NOMOUNT_SHA="$(git -C "$NOMOUNT_TMP/nomount" rev-parse HEAD)"
NOMOUNT_VER="$(git -C "$NOMOUNT_TMP/nomount" describe --tags --always 2>/dev/null || echo "$NOMOUNT_SHA")"

# Replace in-tree copy with a clean copy of upstream kernel/src
rm -rf "$KERNEL_DIR/fs/nomount"
mkdir -p "$KERNEL_DIR/fs/nomount"
cp -a "$NM_SRC"/. "$KERNEL_DIR/fs/nomount/"

# Make sure fs/Makefile and fs/Kconfig hooks exist (same as upstream setup.sh)
if ! grep -q "nomount" "$KERNEL_DIR/fs/Makefile"; then
  printf '\nobj-$(CONFIG_NOMOUNT) += nomount/\n' >> "$KERNEL_DIR/fs/Makefile"
  echo "[nomount] added hook to fs/Makefile"
fi
if ! grep -q 'source "fs/nomount/Kconfig"' "$KERNEL_DIR/fs/Kconfig"; then
  awk '/^endmenu/ { last = NR } { l[NR] = $0 }
       END { for (i = 1; i <= NR; i++) { if (i == last) print "source \"fs/nomount/Kconfig\""; print l[i] } }' \
    "$KERNEL_DIR/fs/Kconfig" > "$KERNEL_DIR/fs/Kconfig.tmp" && mv "$KERNEL_DIR/fs/Kconfig.tmp" "$KERNEL_DIR/fs/Kconfig"
  echo "[nomount] added hook to fs/Kconfig"
fi

echo "NOMOUNT_SHA=${NOMOUNT_SHA}" >> "$GITHUB_ENV"
echo "NOMOUNT_VER=${NOMOUNT_VER}" >> "$GITHUB_ENV"
echo "[+] NoMount synced: ${NOMOUNT_VER} (${NOMOUNT_SHA:0:8})"
rm -rf "$NOMOUNT_TMP"
