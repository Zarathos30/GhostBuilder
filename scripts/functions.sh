#!/bin/bash
log()   { echo "[+] $*"; }
warn()  { echo "[!] $*" >&2; }
error() { echo "[-] $*" >&2; exit 1; }
run_quiet() { "$@" > /dev/null 2>&1 || true; }

# Shared upstream source registry — single source of truth for scout.sh + upstream_check.sh
# NOTE: these point at our own mirrors (Zarathos30/*) synced by mirror_sync.sh,
# so upstream force-pushes never orphan our pins.
declare -A DUMPC2J_SOURCES=(
  [sukisu_root]="SukiSU-Ultra (root)|https://api.github.com/repos/Zarathos30/SukiSU-Ultra/commits/main|.sha"
  [sukisu_susfs]="SukiSU-Ultra (susfs)|https://api.github.com/repos/Zarathos30/SukiSU-Ultra/commits/builtin|.sha"
  [resukisu_root]="ReSukiSU (root)|https://api.github.com/repos/Zarathos30/ReSukiSU/commits/main|.sha"
  [resukisu_susfs]="ReSukiSU (susfs)|https://api.github.com/repos/Zarathos30/ReSukiSU/commits/main|.sha"
  [ksunext_root]="KernelSU-Next (root)|https://api.github.com/repos/Zarathos30/KernelSU-Next-Dev/commits/dev|.sha"
  [ksunext_susfs]="KernelSU-Next-susfs (pershoot)|https://api.github.com/repos/Zarathos30/KernelSU-Next/commits/dev-susfs|.sha"
  [susfs4ksu]="SUSFS4KSU (simon)|https://api.github.com/repos/Zarathos30/susfs4ksu/commits/gki-android15-6.6-dev|.sha"
)

source_label()  { local IFS='|'; local parts=(${DUMPC2J_SOURCES[$1]}); echo "${parts[0]}"; }
source_url()    { local IFS='|'; local parts=(${DUMPC2J_SOURCES[$1]}); echo "${parts[1]}"; }
source_filter() { local IFS='|'; local parts=(${DUMPC2J_SOURCES[$1]}); echo "${parts[2]}"; }
