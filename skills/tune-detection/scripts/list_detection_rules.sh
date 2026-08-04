#!/usr/bin/env bash
# list_detection_rules.sh [--max-pages N]
#
# Page through Scanner's detection rules REST API and emit a single JSON
# object on stdout of the shape:
#
#   { "rules":     [ ...all detection_rules from every page, flattened... ],
#     "truncated": <bool>,   # true if we stopped at --max-pages before
#                            # exhausting next_page_token
#     "pages":     <int> }   # number of pages fetched
#
# The flat `rules` array is the main payload; `truncated` and `pages` are
# metadata so callers can tell whether they got the full inventory or a
# capped slice.
#
# Required env:
#   SCANNER_API_URL    e.g. https://api.example.scanner.dev (no trailing slash).
#                      Scanner UI: Settings > API Keys.
#   SCANNER_API_KEY    Bearer token with read access to /v1/detection_rule.
#                      Scanner UI: Settings > API Keys.
#   SCANNER_TEAM_ID    Your Team ID: Settings > General > "Team ID". It is also
#                      the UUID in the settings URL,
#                      app.scanner.dev/teams/<TEAM_ID>/settings/overview.
#                      SCANNER_TENANT_ID is accepted as a fallback for now.
#                      The REST API parameter is still spelled tenant_id on the
#                      wire; "Team ID" is the name the product is moving to.
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

# Team ID. SCANNER_TEAM_ID is the preferred name; SCANNER_TENANT_ID is the older
# spelling and still works. The API query parameter stays tenant_id until the API
# itself renames it.
team_id="${SCANNER_TEAM_ID:-${SCANNER_TENANT_ID:-}}"
if [[ -z "${SCANNER_TEAM_ID:-}" && -n "${SCANNER_TENANT_ID:-}" ]]; then
  echo "note: using SCANNER_TENANT_ID. The preferred name is now SCANNER_TEAM_ID (same value)." >&2
fi

missing=""
for var in SCANNER_API_URL SCANNER_API_KEY; do
  if [[ -z "${!var:-}" ]]; then
    missing="${missing:+$missing }$var"
  fi
done
if [[ -z "$team_id" ]]; then
  missing="${missing:+$missing }SCANNER_TEAM_ID"
fi
if [[ -n "$missing" ]]; then
  cat >&2 <<MSG
error: missing required environment variable(s): $missing

Where to find each value in the Scanner web app (app.scanner.dev):

  SCANNER_API_URL    Settings > API Keys (the "team API URL"),
                     e.g. https://api.us-east-1.scanner.dev  (no trailing slash)

  SCANNER_API_KEY    Settings > API Keys. Needs read access to
                     /v1/detection_rule.

  SCANNER_TEAM_ID    Settings > General > "Team ID". Fastest way to get it: copy
                     it out of the settings URL in the address bar:
                       app.scanner.dev/teams/<TEAM_ID>/settings/overview
                     SCANNER_TENANT_ID is still read as a fallback if that is
                     what you already have set. The REST API parameter is spelled
                     tenant_id on the wire, but it is the same value, and the
                     product is standardising on "Team ID".

Note: rule lookup by --id and all local-repo / scanner-cli / Scanner MCP work
does not need the Team ID. Only listing rules and lookup by --name do.
MSG
  exit 1
fi

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
      --data-urlencode "tenant_id=${team_id}" \
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
