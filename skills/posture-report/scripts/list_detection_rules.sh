#!/usr/bin/env bash
# list_detection_rules.sh [--max-pages N]
#
# Page through Scanner's detection rules REST API and emit the combined
# results as a single JSON array on stdout (NOT the raw paginated wrappers).
#
# Required env:
#   SCANNER_API_URL   e.g. https://api.example.scanner.dev (no trailing slash)
#   SCANNER_API_KEY    Bearer token with read access to /v1/detection_rule
#   SCANNER_TENANT_ID  Tenant UUID
#
# Optional flags:
#   --max-pages N      Stop after N pages (default 5; matches the n8n agent's cap).
#
# Page size is fixed at 1000 server-side.

set -euo pipefail

max_pages=5
while [[ $# -gt 0 ]]; do
  case "$1" in
    --max-pages)
      max_pages="$2"; shift 2
      ;;
    -h|--help)
      sed -n '1,/^set -euo/p' "$0" | grep '^#' | sed 's/^# //; s/^#//'
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

for var in SCANNER_API_URL SCANNER_API_KEY SCANNER_TENANT_ID; do
  if [[ -z "${!var:-}" ]]; then
    echo "error: $var not set" >&2
    exit 1
  fi
done

base="${SCANNER_API_URL%/}"

# Accumulate all pages' "data" arrays into one tmp file, then jq-merge at the end.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

token=""
truncated=false
for ((page=1; page<=max_pages; page++)); do
  page_file="$tmp/page-$page.json"

  if ! curl --silent --show-error --fail-with-body \
      --max-time 30 \
      --get \
      -H "Authorization: Bearer ${SCANNER_API_KEY}" \
      --data-urlencode "tenant_id=${SCANNER_TENANT_ID}" \
      --data-urlencode "pagination[page_size]=1000" \
      --data-urlencode "pagination[page_token]=${token}" \
      "${base}/v1/detection_rule" \
      > "$page_file"; then
    echo "error: page ${page} failed" >&2
    cat "$page_file" >&2 || true
    exit 1
  fi

  token=$(jq -r '.pagination.next_page_token // ""' "$page_file")
  if [[ -z "$token" ]]; then
    break
  fi
  if [[ "$page" -eq "$max_pages" ]]; then
    truncated=true
  fi
done

# Combine all detection_rules arrays from each page into a single flat array.
# The API response shape is { data: { detection_rules: [...] }, pagination: { next_page_token } }.
jq -s '{rules: (map(.data.detection_rules // []) | add), truncated: '"$truncated"', pages: length}' "$tmp"/page-*.json
