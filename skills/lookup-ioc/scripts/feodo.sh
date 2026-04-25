#!/usr/bin/env bash
# feodo.sh <ip>
#
# Look up an IPv4 in the Feodo Tracker botnet C2 IP blocklist.
# Prints JSON to stdout. On a hit, returns the matching record (malware family,
# AS info, first/last seen). On a miss, returns {"hit": false}.
#
# Requires ABUSECH_AUTH_KEY in the environment.
#
# The full feed is fetched and filtered locally because Feodo Tracker exposes
# the blocklist as a single JSON array, not a per-IP query endpoint.

set -euo pipefail

if [[ $# -ne 1 || -z "${1:-}" ]]; then
  echo "usage: $(basename "$0") <ip>" >&2
  exit 2
fi

if [[ -z "${ABUSECH_AUTH_KEY:-}" ]]; then
  echo "error: ABUSECH_AUTH_KEY not set" >&2
  exit 1
fi

ip="$1"

# Only IPv4 is supported by Feodo Tracker's blocklist; bail early if it doesn't look like one.
if ! [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
  jq -nc --arg ip "$ip" '{hit:false, reason:"feodo blocklist is IPv4-only", ip:$ip}'
  exit 0
fi

feed=$(curl --silent --show-error --fail-with-body \
  --max-time 20 \
  -H "Auth-Key: ${ABUSECH_AUTH_KEY}" \
  https://feodotracker.abuse.ch/downloads/ipblocklist.json)

match=$(printf '%s' "$feed" | jq -c --arg ip "$ip" '[.[] | select(.ip_address == $ip)] | first // null')

if [[ "$match" == "null" ]]; then
  jq -nc --arg ip "$ip" '{hit:false, ip:$ip}'
else
  jq -nc --argjson m "$match" '{hit:true, record:$m}'
fi
