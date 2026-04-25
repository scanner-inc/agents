#!/usr/bin/env bash
# lookup_ioc.sh <indicator>
#
# Detect the IOC type from <indicator>, then fan out to ThreatFox, OTX, and
# Feodo Tracker in parallel and merge the results into a single JSON object on
# stdout:
#
#   {
#     "indicator": "...",
#     "type": "IPv4|IPv6|domain|url|file|cve|unknown",
#     "threatfox": <threatfox response or {error: ...} or {skipped: ...}>,
#     "otx":       <otx response or {error: ...} or {skipped: ...}>,
#     "feodo":     <feodo response or {error: ...} or {skipped: ...}>
#   }
#
# Each source is best-effort: a failure in one does not abort the others. If
# ABUSECH_AUTH_KEY or OTX_API_KEY is missing, the corresponding source is
# reported as {"skipped": "<env var> not set"} instead of {"error": ...}.
#
# Feodo only applies to IPv4. CVE indicators only go to OTX.

set -uo pipefail

if [[ $# -ne 1 || -z "${1:-}" ]]; then
  echo "usage: $(basename "$0") <indicator>" >&2
  exit 2
fi

indicator="$1"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

# --- Type detection ---------------------------------------------------------
detect_type() {
  local v="$1"
  if [[ "$v" =~ ^CVE-[0-9]{4}-[0-9]{4,7}$ ]] || [[ "$v" =~ ^cve-[0-9]{4}-[0-9]{4,7}$ ]]; then
    echo "cve"; return
  fi
  if [[ "$v" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    echo "IPv4"; return
  fi
  if [[ "$v" == *:* && "$v" =~ ^[0-9a-fA-F:]+$ ]]; then
    echo "IPv6"; return
  fi
  if [[ "$v" =~ ^[a-fA-F0-9]{32}$ ]] || [[ "$v" =~ ^[a-fA-F0-9]{40}$ ]] || [[ "$v" =~ ^[a-fA-F0-9]{64}$ ]]; then
    echo "file"; return
  fi
  if [[ "$v" =~ ^[a-zA-Z]+://[^[:space:]]+$ ]]; then
    echo "url"; return
  fi
  if [[ "$v" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)+$ ]]; then
    echo "domain"; return
  fi
  echo "unknown"
}

ioc_type=$(detect_type "$indicator")

# Normalize CVE casing for OTX
otx_value="$indicator"
if [[ "$ioc_type" == "cve" ]]; then
  otx_value=$(printf '%s' "$indicator" | tr '[:lower:]' '[:upper:]')
fi

# --- Run lookups in parallel -----------------------------------------------
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

run_threatfox() {
  if [[ "$ioc_type" == "cve" ]]; then
    jq -nc '{skipped:"ThreatFox IOC lookup is not used for CVE IDs; use threat-hunt instead"}' > "$tmp/threatfox.json"
    return
  fi
  if [[ -z "${ABUSECH_AUTH_KEY:-}" ]]; then
    jq -nc '{skipped:"ABUSECH_AUTH_KEY not set"}' > "$tmp/threatfox.json"
    return
  fi
  if out=$("$script_dir/threatfox.sh" "$indicator" 2> "$tmp/threatfox.err"); then
    printf '%s' "$out" > "$tmp/threatfox.json"
  else
    jq -nc --rawfile e "$tmp/threatfox.err" '{error:$e}' > "$tmp/threatfox.json"
  fi
}

run_otx() {
  if [[ "$ioc_type" == "unknown" ]]; then
    jq -nc '{skipped:"unknown indicator type"}' > "$tmp/otx.json"
    return
  fi
  if [[ -z "${OTX_API_KEY:-}" ]]; then
    jq -nc '{skipped:"OTX_API_KEY not set"}' > "$tmp/otx.json"
    return
  fi
  if out=$("$script_dir/otx.sh" "$ioc_type" "$otx_value" 2> "$tmp/otx.err"); then
    printf '%s' "$out" > "$tmp/otx.json"
  else
    jq -nc --rawfile e "$tmp/otx.err" '{error:$e}' > "$tmp/otx.json"
  fi
}

run_feodo() {
  if [[ "$ioc_type" != "IPv4" ]]; then
    jq -nc --arg t "$ioc_type" '{skipped:("feodo blocklist is IPv4-only; type was " + $t)}' > "$tmp/feodo.json"
    return
  fi
  if [[ -z "${ABUSECH_AUTH_KEY:-}" ]]; then
    jq -nc '{skipped:"ABUSECH_AUTH_KEY not set"}' > "$tmp/feodo.json"
    return
  fi
  if out=$("$script_dir/feodo.sh" "$indicator" 2> "$tmp/feodo.err"); then
    printf '%s' "$out" > "$tmp/feodo.json"
  else
    jq -nc --rawfile e "$tmp/feodo.err" '{error:$e}' > "$tmp/feodo.json"
  fi
}

run_threatfox &
run_otx &
run_feodo &
wait

# --- Merge ------------------------------------------------------------------
jq -n \
  --arg indicator "$indicator" \
  --arg type "$ioc_type" \
  --slurpfile tf "$tmp/threatfox.json" \
  --slurpfile otx "$tmp/otx.json" \
  --slurpfile feodo "$tmp/feodo.json" \
  '{indicator:$indicator, type:$type, threatfox:$tf[0], otx:$otx[0], feodo:$feodo[0]}'
