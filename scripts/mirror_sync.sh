#!/bin/bash
# Mirror sync: porta gli aggiornamenti dagli upstream ai mirror Zarathos30,
# ma NON lascia mai morire i commit vecchi — ogni punta di branch aggiornata
# viene prima salvata in un ref di backup (refs/keep/*), così i pin dello
# scout restano validi per sempre anche dopo force-push upstream.
set -eo pipefail

GH_TOKEN="${GH_TOKEN:?GH_TOKEN not set}"
MIRROR_BASE="https://x-access-token:${GH_TOKEN}@github.com/Zarathos30"

# name|upstream_git_url|branches (space separated)
COMPONENTS=(
  "KernelSU-Next|https://github.com/pershoot/KernelSU-Next.git|dev-susfs"
  "KernelSU-Next-Dev|https://github.com/KernelSU-Next/KernelSU-Next.git|dev"
  "SukiSU-Ultra|https://github.com/SukiSU-Ultra/SukiSU-Ultra.git|main builtin"
  "ReSukiSU|https://github.com/ReSukiSU/ReSukiSU.git|main"
  "susfs4ksu|https://gitlab.com/simonpunk/susfs4ksu.git|gki-android15-6.6-dev"
)

# Map manifest key -> mirror repo name
KEY_TO_REPO=(
  "ksunext_susfs:KernelSU-Next"
  "ksunext_root:KernelSU-Next-Dev"
  "sukisu_root:SukiSU-Ultra"
  "sukisu_susfs:SukiSU-Ultra"
  "resukisu_root:ReSukiSU"
  "resukisu_susfs:ReSukiSU"
  "susfs4ksu:susfs4ksu"
)

MANIFEST="${GITHUB_WORKSPACE}/builder/scripts/checkpoint/manifest.json"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

seed_pins() {
  local name="$1" upstream="$2"
  local mirror="${MIRROR_BASE}/${name}.git"
  local keys=() map k r

  for map in "${KEY_TO_REPO[@]}"; do
    k="${map%%:*}" r="${map##*:}"
    [ "$r" = "$name" ] && keys+=("$k")
  done
  [ ${#keys[@]} -gt 0 ] || return 0
  [ -f "$MANIFEST" ] || return 0

  local key pins=() pin
  for key in "${keys[@]}"; do
    pins=()
    while IFS= read -r pin; do pins+=("$pin"); done < <(jq -r ".${key}.good, .${key}.history[]?" "$MANIFEST" 2>/dev/null | sort -u)

    for pin in "${pins[@]}"; do
      [ -n "$pin" ] && [ "$pin" != "null" ] || continue
      if git ls-remote "$mirror" "refs/keep/pin-${key}-${pin}" 2>/dev/null | grep -q "$pin"; then
        echo "[=] keep ref gia' esiste per ${key} ${pin:0:12} — skip"
        continue
      fi
      echo "[*] seeding ${key} pin ${pin:0:12} on ${name}..."
      if (cd "$WORK/$name.git" && timeout 60 git fetch --quiet "$upstream" "$pin" 2>/dev/null) || \
         (cd "$WORK/$name.git" && timeout 60 git fetch --quiet "$mirror" "$pin" 2>/dev/null); then
        git -C "$WORK/$name.git" push "$mirror" "FETCH_HEAD:refs/keep/pin-$key-$pin" > /dev/null 2>&1 \
          && echo "    saved refs/keep/pin-$key-${pin:0:12}" \
          || echo "[!] backup push failed for ${pin:0:12}"
      else
        echo "[!] pin ${pin:0:12} not fetchable (upstream o mirror) — skip"
      fi
    done
  done
}

for entry in "${COMPONENTS[@]}"; do
  IFS='|' read -r name upstream branches <<< "$entry"
  mirror="${MIRROR_BASE}/${name}.git"

  echo "=== ${name} ==="
  git clone --mirror "$upstream" "$WORK/$name.git" || { echo "[!] clone failed for ${name}"; continue; }
  cd "$WORK/$name.git"

  # Freeze every pinned SHA into refs/keep/* before touching branches,
  # so pins survive even if upstream already force-pushed them away.
  seed_pins "$name" "$upstream"

  for branch in $branches; do
    new_sha="$(git rev-parse --verify "refs/heads/$branch" 2>/dev/null || true)"
    [ -n "$new_sha" ] || { echo "[!] branch ${branch} not in upstream — skip"; continue; }

    old_sha="$(git ls-remote "$mirror" "refs/heads/$branch" | awk '{print $1}' || true)"

    if [ -n "$old_sha" ] && [ "$old_sha" != "$new_sha" ]; then
      if git merge-base --is-ancestor "$old_sha" "$new_sha" 2>/dev/null; then
        echo "[+] ${branch}: ${old_sha:0:8} -> ${new_sha:0:8} (fast-forward)"
      else
        stamp="$(date -u +%Y%m%d-%H%M%S)"
        echo "[!] ${branch}: force-push detected (${old_sha:0:8} -> ${new_sha:0:8}) — saving backup ref"
        git push "$mirror" "$old_sha:refs/keep/$branch-$stamp" > /dev/null 2>&1 || echo "[!] backup push failed (old head may be unreachable)"
        echo "    backup: refs/keep/$branch-$stamp"
      fi
      git push --force "$mirror" "refs/heads/$branch:refs/heads/$branch" 2>&1 | grep -v "^\s*$" || true
    elif [ -z "$old_sha" ]; then
      echo "[+] ${branch}: new branch, pushing ${new_sha:0:8}"
      git push "$mirror" "refs/heads/$branch:refs/heads/$branch" 2>&1 | grep -v "^\s*$" || true
    else
      echo "[=] ${branch}: up to date at ${new_sha:0:8}"
    fi
  done

  cd - > /dev/null
done

echo "=== All mirrors synced ==="
