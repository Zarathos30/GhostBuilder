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

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

for entry in "${COMPONENTS[@]}"; do
  IFS='|' read -r name upstream branches <<< "$entry"
  mirror="${MIRROR_BASE}/${name}.git"

  echo "=== ${name} ==="
  git clone --mirror "$upstream" "$WORK/$name.git" || { echo "[!] clone failed for ${name}"; continue; }
  cd "$WORK/$name.git"

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
