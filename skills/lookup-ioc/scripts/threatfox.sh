#!/usr/bin/env bash
# threatfox.sh <ioc>
#
# Reputation check against abuse.ch ThreatFox. Prints JSON to stdout.
# On a hit, returns the malware family, confidence, first_seen, etc.
# On a miss, returns {"query_status":"no_result"}.
#
# Requires ABUSECH_AUTH_KEY in the environment.

set -euo pipefail

if [[ $# -ne 1 || -z "${1:-}" ]]; then
  echo "usage: $(basename "$0") <ioc>" >&2
  exit 2
fi

if [[ -z "${ABUSECH_AUTH_KEY:-}" ]]; then
  echo "error: ABUSECH_AUTH_KEY not set" >&2
  exit 1
fi

ioc="$1"

curl --silent --show-error --fail-with-body \
  --max-time 15 \
  -H "Auth-Key: ${ABUSECH_AUTH_KEY}" \
  -H 'Content-Type: application/json' \
  -d "$(jq -nc --arg ioc "$ioc" '{query:"search_ioc", search_term:$ioc, exact_match:true}')" \
  https://threatfox-api.abuse.ch/api/v1/
