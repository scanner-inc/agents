#!/usr/bin/env bash
# cisa_kev_top.sh [N]
#
# Fetch the CISA Known Exploited Vulnerabilities feed and emit the top N
# most recently added entries as a JSON array on stdout. Default N=5.
#
# Each entry includes: cveID, vendorProject, product, vulnerabilityName,
# dateAdded, shortDescription, requiredAction, dueDate, knownRansomwareCampaignUse,
# notes, cwes.
#
# No auth needed — the feed is public.

set -euo pipefail

n="${1:-5}"
if ! [[ "$n" =~ ^[0-9]+$ ]] || [[ "$n" -lt 1 ]]; then
  echo "usage: $(basename "$0") [N]   (N is a positive integer; default 5)" >&2
  exit 2
fi

curl --silent --show-error --fail-with-body \
  --max-time 30 \
  https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json \
  | jq --argjson n "$n" '
      .vulnerabilities
      | sort_by(.dateAdded) | reverse
      | .[0:$n]
    '
