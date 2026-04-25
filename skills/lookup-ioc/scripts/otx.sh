#!/usr/bin/env bash
# otx.sh <type> <value>
#
# AlienVault OTX direct indicator lookup. Prints JSON to stdout.
# <type> must be one of: IPv4, IPv6, domain, hostname, url, file, cve (case-sensitive).
# <value> is the indicator itself.
#
# Requires OTX_API_KEY in the environment.

set -euo pipefail

if [[ $# -ne 2 || -z "${1:-}" || -z "${2:-}" ]]; then
  echo "usage: $(basename "$0") <type> <value>" >&2
  echo "  <type>: IPv4 | IPv6 | domain | hostname | url | file | cve" >&2
  exit 2
fi

if [[ -z "${OTX_API_KEY:-}" ]]; then
  echo "error: OTX_API_KEY not set" >&2
  exit 1
fi

type="$1"
value="$2"

case "$type" in
  IPv4|IPv6|domain|hostname|url|file|cve) ;;
  *)
    echo "error: type must be one of IPv4, IPv6, domain, hostname, url, file, cve (case-sensitive); got '$type'" >&2
    exit 2
    ;;
esac

# URL-encode the value
encoded_value=$(jq -rn --arg v "$value" '$v|@uri')

curl --silent --show-error --fail-with-body \
  --max-time 15 \
  -H "X-OTX-API-KEY: ${OTX_API_KEY}" \
  "https://otx.alienvault.com/api/v1/indicators/${type}/${encoded_value}/general"
