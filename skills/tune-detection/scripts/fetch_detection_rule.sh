#!/usr/bin/env bash
# fetch_detection_rule.sh --name "Rule Name" | --id <uuid>
#
# Look up a single detection rule from the Scanner Detection Rule API and emit
# its full JSON record. Useful for `tune-detection` when the rule was created
# via the Scanner UI (and therefore isn't in any local repo).
#
# Required env:
#   SCANNER_API_URL    e.g. https://api.example.scanner.dev (no trailing slash).
#                      Scanner UI: Settings > API Keys.
#   SCANNER_API_KEY    Bearer token with read access to /v1/detection_rule.
#                      Scanner UI: Settings > API Keys.
#   SCANNER_TEAM_ID    Required for --name only (the list-and-filter path).
#                      Your Team ID: Settings > General > "Team ID". It is also
#                      the UUID in the settings URL,
#                      app.scanner.dev/teams/<TEAM_ID>/settings/overview.
#                      SCANNER_TENANT_ID is accepted as a fallback for now.
#                      The REST API parameter is still spelled tenant_id on the
#                      wire; "Team ID" is the name the product is moving to.
#
# Resolution order:
#   --id <uuid>      → GET /v1/detection_rule/{id} directly
#   --name "<name>"  → list all rules via list_detection_rules.sh, jq-filter to
#                      the one with matching name (case-sensitive, exact match)
#
# Exit codes:
#   0  success — JSON on stdout
#   1  not found
#   2  ambiguous (multiple matches by name) — JSON array on stdout
#   3  bad env or args

set -euo pipefail

mode=""
arg=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --id)   mode="id";   arg="$2"; shift 2 ;;
    --name) mode="name"; arg="$2"; shift 2 ;;
    -h|--help)
      sed -n '1,/^set -euo/p' "$0" | grep '^#' | sed 's/^# //; s/^#//'
      exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 3 ;;
  esac
done

if [[ -z "$mode" || -z "$arg" ]]; then
  echo "error: must pass either --id <uuid> or --name \"<name>\"" >&2
  exit 3
fi

# The Team ID is only consumed by the --name path (it delegates to
# list_detection_rules.sh). Don't block a --id lookup on it.
# SCANNER_TEAM_ID is the preferred name; SCANNER_TENANT_ID still works.
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
if [[ "$mode" == "name" && -z "$team_id" ]]; then
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
                     Needed here only for --name; --id works without it.
MSG
  exit 3
fi

base="${SCANNER_API_URL%/}"

if [[ "$mode" == "id" ]]; then
  body=$(curl --silent --show-error --fail-with-body --max-time 30 \
    -H "Authorization: Bearer ${SCANNER_API_KEY}" \
    "${base}/v1/detection_rule/${arg}") || { echo "error: API call failed" >&2; cat <<< "$body" >&2; exit 1; }
  echo "$body" | jq '.detection_rule'
  exit 0
fi

# --name path: list all rules, filter.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
all=$("${script_dir}/list_detection_rules.sh" 2>/dev/null)
matches=$(jq --arg name "$arg" '[.rules[] | select(.name == $name)]' <<<"$all")
n=$(jq 'length' <<<"$matches")

if [[ "$n" -eq 0 ]]; then
  echo "error: no rule with name $arg" >&2
  exit 1
elif [[ "$n" -gt 1 ]]; then
  echo "$matches"
  echo "error: ambiguous — $n rules match name $arg" >&2
  exit 2
fi

jq '.[0]' <<<"$matches"
