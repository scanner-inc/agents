#!/usr/bin/env bash
# fetch_detection_rule.sh --name "Rule Name" | --id <uuid>
#
# Look up a single detection rule from the Scanner Detection Rule API and emit
# its full JSON record. Useful for `tune-detection` when the rule was created
# via the Scanner UI (and therefore isn't in any local repo).
#
# Required env:
#   SCANNER_API_URL    e.g. https://api.example.scanner.dev (no trailing slash)
#   SCANNER_API_KEY    Bearer token with read access to /v1/detection_rule
#   SCANNER_TENANT_ID  Tenant UUID
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

for var in SCANNER_API_URL SCANNER_API_KEY SCANNER_TENANT_ID; do
  if [[ -z "${!var:-}" ]]; then
    echo "error: $var not set" >&2; exit 3
  fi
done

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
