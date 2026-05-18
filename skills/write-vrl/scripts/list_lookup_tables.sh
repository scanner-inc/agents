#!/usr/bin/env bash
# List lookup tables available in the user's Scanner tenant.
# Used by write-vrl (when authoring an enrichment), write-detection (when an
# IOC-based rule needs to consume an existing IOC table), and recommend-detections
# (when surfacing IOC-chain recommendations).
#
# Scanner's Lookup Tables API is "unstable" (per the docs) — endpoints under
# /v1/unstable/lookup_table_file/. Treat as best-effort; degrade gracefully.
#
# Usage:
#   scripts/list_lookup_tables.sh                    # JSON, full
#   scripts/list_lookup_tables.sh --summary          # one line per table
#   scripts/list_lookup_tables.sh --ioc              # filter to IOC-looking tables
#
# Required env: SCANNER_API_URL, SCANNER_API_KEY, SCANNER_TENANT_ID
set -euo pipefail

: "${SCANNER_API_URL:?SCANNER_API_URL not set — point at your team API URL from Settings > API Keys}"
: "${SCANNER_API_KEY:?SCANNER_API_KEY not set — bearer token from Settings > API Keys}"
: "${SCANNER_TENANT_ID:?SCANNER_TENANT_ID not set — tenant UUID from Settings > General}"

if ! command -v jq &>/dev/null; then
  echo "Error: jq is required" >&2
  exit 1
fi

MODE="${1:-json}"

# Strip trailing slash on the base URL just in case.
BASE="${SCANNER_API_URL%/}/v1/unstable/lookup_table_file/tenant/${SCANNER_TENANT_ID}"

RESPONSE="$(curl -sf -G "${BASE}" -H "Authorization: Bearer ${SCANNER_API_KEY}" 2>&1)" || {
  cat >&2 <<MSG
list_lookup_tables.sh: API call failed.

The Lookup Tables API is under /v1/unstable/ and may not be enabled on every
Scanner deployment, or your API key may not have read access. Skip the
list-tables step and ask the user directly what tables they have.

raw curl output:
${RESPONSE}
MSG
  exit 2
}

case "${MODE}" in
  json)
    echo "${RESPONSE}" | jq .
    ;;
  --summary|summary)
    echo "${RESPONSE}" | jq -r '
      if .lookup_table_files == null or (.lookup_table_files | length) == 0
      then "(no lookup tables found)"
      else
        .lookup_table_files
        | sort_by(.name)
        | map("\(.name)\t\(.num_rows) rows\t\(.size_bytes) bytes\t\(.description // "")")
        | join("\n")
      end'
    ;;
  --ioc|ioc)
    # Definitive: sync_source.ThreatIntel is populated when Scanner syncs the table from
    # a threat-intel feed (AlienVault OTX, ThreatFox, etc). Schema:
    #   sync_source: { ThreatIntel: { source: "AlienVault", indicator_type: "ipv4-addr" }, is_connected: true }
    # Fallback heuristic on name/description catches manually-uploaded IOC CSVs that
    # don't have sync_source set.
    echo "${RESPONSE}" | jq -r '
      def is_threat_intel_sync(t):
        t.sync_source != null and (t.sync_source | has("ThreatIntel"));
      def is_ioc_keyword(t):
        ([t.name, (t.description // "")] | join(" ") | ascii_downcase) as $s
        | ($s | test("ioc|threat|alienvault|otx|abuse|abusech|threatfox|misp|feodo|cisa|malware|c2|tor|known.bad|blocklist|reputation|indicator"));
      def category(t):
        if is_threat_intel_sync(t) then "synced"
        elif is_ioc_keyword(t) then "uploaded"
        else "skip" end;
      def fmt_synced(t):
        "\(t.name)\t[\(t.sync_source.ThreatIntel.source) · \(t.sync_source.ThreatIntel.indicator_type) · \(if t.sync_source.is_connected then "connected" else "DISCONNECTED" end)]\t\(t.num_rows) rows\t\(t.description // "")";
      def fmt_uploaded(t):
        "\(t.name)\t[uploaded · heuristic match]\t\(t.num_rows) rows\t\(t.description // "")";
      .lookup_table_files // []
      | map({t: ., cat: category(.)})
      | map(select(.cat != "skip"))
      | if length == 0
        then "(no IOC lookup tables found — neither sync_source.ThreatIntel nor name/description match)"
        else
          sort_by(.t.name)
          | map(if .cat == "synced" then fmt_synced(.t) else fmt_uploaded(.t) end)
          | join("\n")
        end'
    ;;
  *)
    echo "usage: $0 [--summary|--ioc]" >&2
    exit 1
    ;;
esac
