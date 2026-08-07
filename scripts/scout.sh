#!/bin/bash
set -eo pipefail

BUILDER_DIR="${GITHUB_WORKSPACE}/builder"
source "${BUILDER_DIR}/scripts/functions.sh"

MANIFEST="${BUILDER_DIR}/scripts/checkpoint/manifest.json"
[ -f "$MANIFEST" ] || error "scout: manifest.json not found at ${MANIFEST}"

RUN_MODE="${RUN_MODE:-Test}"
CANDIDATE_CLAIMED="false"

latest_sha_or_empty() {
    local label="$1" url="$2" jq_filter="$3"
    local body_file http_code curl_exit sha

    body_file="$(mktemp)"
    if http_code=$(curl -sL -o "$body_file" -w '%{http_code}' --max-time 20 -H "Authorization: Bearer ${GH_TOKEN:-}" "$url"); then
        curl_exit=0
    else
        curl_exit=$?
    fi

    if [ "$curl_exit" -ne 0 ] || [ "$http_code" != "200" ]; then
        warn "scout: couldn't reach upstream for ${label} (curl exit ${curl_exit}, HTTP ${http_code:-000}) — using pinned ref"
        rm -f "$body_file"; echo ""; return 0
    fi

    sha=$(jq -r "$jq_filter" "$body_file" 2>/dev/null)
    rm -f "$body_file"
    if [ -z "$sha" ] || [ "$sha" = "null" ]; then
        warn "scout: couldn't parse latest ${label} commit — using pinned ref"
        echo ""; return 0
    fi
    echo "$sha"
}

ref_exists() {
    local url_template="$1" sha="$2"
    local repo_base branch compare_url status
    [ -n "$sha" ] && [ "$sha" != "null" ] || return 1

    case "$url_template" in
        *api.github.com*/commits/*)
            repo_base="${url_template%/commits/*}"
            branch="${url_template##*/commits/}"
            compare_url="${repo_base}/compare/${branch}...${sha}"
            status=$(curl -sL --max-time 15 -H "Authorization: Bearer ${GH_TOKEN:-}" "$compare_url" 2>/dev/null | jq -r '.status // empty')
            if [ "$status" = "identical" ] || [ "$status" = "behind" ]; then
                return 0
            fi
            # Storia riscritta upstream (diverged): pin ancora valido se il commit esiste ancora
            if [ "$status" = "diverged" ]; then
                check_url="${repo_base}/commits/${sha}"
                http_code=$(curl -sL -o /dev/null -w '%{http_code}' --max-time 15 -H "Authorization: Bearer ${GH_TOKEN:-}" "$check_url" 2>/dev/null) || return 1
                [ "$http_code" = "200" ]
            else
                return 1
            fi
            ;;
        *)
            local check_url http_code
            check_url="${url_template%/*}/${sha}"
            http_code=$(curl -sL -o /dev/null -w '%{http_code}' --max-time 15 "$check_url" 2>/dev/null) || return 1
            [ "$http_code" = "200" ]
            ;;
    esac
}

dispatch_test_run() {
    local prefix="$1"
    [ -n "${GH_TOKEN:-}" ] || { warn "scout: GH_TOKEN not set — cannot auto-dispatch Test run"; return 1; }
    [ -n "${RUN_INPUTS_JSON:-}" ] || { warn "scout: RUN_INPUTS_JSON not set — cannot auto-dispatch Test run"; return 1; }

    local inputs payload
    inputs=$(echo "$RUN_INPUTS_JSON" | jq '.run_mode = "Test"')
    payload=$(jq -n --argjson inputs "$inputs" '{ref:"main", inputs:$inputs}')

    log "scout: semua pin mati — dispatching Test run otomatis (run_mode=Test)..."
    curl -s -o /dev/null -w "dispatch HTTP %{http_code}\n" \
        -X POST "https://api.github.com/repos/${GITHUB_REPOSITORY}/actions/workflows/build.yml/dispatches" \
        -H "Authorization: Bearer ${GH_TOKEN}" \
        -H "Accept: application/vnd.github+json" \
        -H "User-Agent: GhostBot/1.0" \
        -d "$payload" || warn "scout: dispatch failed"

    if [ -n "${TELEGRAM_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
            -d chat_id="${TELEGRAM_CHAT_ID}" \
            -d parse_mode="HTML" \
            -d "text=⚠️ <b>All pins for ${prefix} died upstream (force-push).</b> Dispatched an automatic <b>Test</b> run to re-pin. Run Release again after it finishes." > /dev/null || true
    fi
}

resolve_component() {
    local key="$1" prefix="$2" latest="$3" url_template="$4"
    local good bad_list is_bad ref candidate
    local pins=() pin valid=""

    good=$(jq -r ".${key}.good" "$MANIFEST")
    bad_list=$(jq -c ".${key}.bad" "$MANIFEST")

    [ -n "$good" ] && [ "$good" != "null" ] && pins+=("$good")
    while IFS= read -r pin; do pins+=("$pin"); done < <(jq -r ".${key}.history[]?" "$MANIFEST")

    for pin in "${pins[@]}"; do
        if [ -z "$url_template" ] || ref_exists "$url_template" "$pin"; then
            valid="$pin"; break
        fi
        warn "${prefix}: pin ${pin:0:12} udah gak ada di remote (force-push/rewrite upstream?) — coba pin history berikutnya"
    done

    if [ -z "$valid" ]; then
        good=""
        warn "${prefix}: semua pin (good + history) udah gak ada di remote"
    else
        if [ "$valid" != "$good" ]; then
            warn "${prefix}: pinned good ${good:0:12} mati — fallback ke pin history ${valid:0:12}"
            echo "${prefix}_FALLBACK=${valid}" >> "$GITHUB_ENV"
        fi
        good="$valid"
    fi

    if [ "${RUN_MODE^^}" = "RELEASE" ]; then
        if [ -n "$good" ]; then
            ref="$good"; candidate="false"
            log "${prefix}: Release mode — pinned ${ref:0:12}"
        else
            dispatch_test_run "$prefix" || warn "scout: auto-dispatch Test run gagal — jalankan run Test manual."
            error "scout: RUN_MODE=Release tapi semua pin ${key} mati (force-push upstream) — Test run otomatis diluncurkan, jalankan lagi setelah selesai."
        fi
    elif [ -z "$latest" ]; then
        ref="$good"; candidate="false"
        log "${prefix}: no candidate — pakai pinned ${good:-none}"
    elif [ "$latest" = "$good" ]; then
        ref="$good"; candidate="false"
        log "${prefix}: up to date at ${good:0:12}"
    else
        is_bad=$(echo "$bad_list" | jq --arg sha "$latest" 'any(. == $sha)')
        if [ "$is_bad" = "true" ]; then
            if [ -n "$good" ]; then
                ref="$good"; candidate="false"
                warn "${prefix}: latest ${latest:0:12} known-bad — fallback ke pinned ${good:0:12}"
            elif [ "$CANDIDATE_CLAIMED" = "true" ]; then
                ref=""; candidate="false"
                warn "${prefix}: known-bad, belum ada pin, & slot candidate run ini udah kepake komponen lain — skip komponen ini, tidak checkout apapun"
                echo "SKIP_${prefix}=true" >> "$GITHUB_ENV"
                echo "${prefix}_REF=${ref}" >> "$GITHUB_ENV"
                echo "CANDIDATE_${prefix}=${candidate}" >> "$GITHUB_ENV"
                return 0
            else
                ref="$latest"; candidate="true"
                CANDIDATE_CLAIMED="true"
                warn "${prefix}: latest ${latest:0:12} known-bad & belum ada pin — retry sbg last-resort candidate"
            fi
        else
            if [ "$CANDIDATE_CLAIMED" = "true" ]; then
                if [ -n "$good" ]; then
                    ref="$good"; candidate="false"
                    log "${prefix}: candidate baru ${latest:0:12} terdeteksi tapi ditunda — komponen lain lagi diuji run ini, pinned ${good:0:12} dulu"
                else
                    ref=""; candidate="false"
                    warn "${prefix}: candidate baru ${latest:0:12} terdeteksi tapi ditunda, dan belum ada pin sama sekali — skip komponen ini run ini"
                    echo "SKIP_${prefix}=true" >> "$GITHUB_ENV"
                    echo "${prefix}_REF=${ref}" >> "$GITHUB_ENV"
                    echo "CANDIDATE_${prefix}=${candidate}" >> "$GITHUB_ENV"
                    return 0
                fi
            else
                ref="$latest"; candidate="true"
                CANDIDATE_CLAIMED="true"
                log "${prefix}: candidate baru ${latest:0:12} (pinned: ${good:-none})"
            fi
        fi
    fi

    echo "${prefix}_REF=${ref}" >> "$GITHUB_ENV"
    echo "CANDIDATE_${prefix}=${candidate}" >> "$GITHUB_ENV"
}

scout_track() {
  local key="$1" prefix="$2"
  local label url filter latest
  label=$(source_label "$key")
  url=$(source_url "$key")
  filter=$(source_filter "$key")
  latest=$(latest_sha_or_empty "$label" "$url" "$filter")
  resolve_component "$key" "$prefix" "$latest" "$url"
}

case "$ROOT" in
  sukisu)
    if [ "$VARIANT" == "susfs" ]; then
      scout_track "sukisu_susfs" "SUKISU_SUSFS"
    else
      scout_track "sukisu_root" "SUKISU_ROOT"
    fi
    ;;
  resukisu)
    if [ "$VARIANT" == "susfs" ]; then
      scout_track "resukisu_susfs" "RESUKISU_SUSFS"
    else
      scout_track "resukisu_root" "RESUKISU_ROOT"
    fi
    ;;
  ksu-next)
    if [ "$VARIANT" == "susfs" ]; then
      scout_track "ksunext_susfs" "KSUNEXT_SUSFS"
    else
      scout_track "ksunext_root" "KSUNEXT_ROOT"
    fi
    ;;
  *)
    log "scout: ROOT=none — nothing to track"
    ;;
esac

if [ "$VARIANT" == "susfs" ]; then
  scout_track "susfs4ksu" "SUSFS4KSU"
fi
