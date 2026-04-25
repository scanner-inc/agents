---
name: threat-hunt
description: Run a proactive threat hunt against historical Scanner logs using fresh threat intelligence. With no argument, picks the most environmentally relevant CVE from CISA KEV and hunts its IOCs across all available log sources. With an argument (CVE id, malware family, threat actor, IOC), hunts that specific topic. Use when the user types `/threat-hunt`, `/threat-hunt [topic]`, or asks Claude to "hunt", "do a threat hunt", "look for evidence of [CVE / malware / actor]", or "sweep logs for [IOC]". Requires Scanner MCP plus optionally OTX_API_KEY and ABUSECH_AUTH_KEY for richer threat-intel.
---

# threat-hunt

## Workflow

Follow the full procedure in `references/methodology.md`. The 5 phases:

1. **Environment discovery** — Scanner MCP `get_scanner_context`. Identifies what's searchable.
2. **Threat-intel gathering** — pick a hunt target, gather IOCs.
3. **Historical log analysis** — IOC sweeps first, pivot only on hits. 3-6 queries total for a clean hunt.
4. **Correlation and assessment** — only if hits.
5. **Final output** — the structured report template at the bottom of `references/methodology.md`.

## Picking a hunt target

If the user passed a topic argument, use it directly. The topic might be:

- A CVE id (e.g. `CVE-2024-3400`) — go straight to ThreatFox `taginfo` for IOCs.
- A malware family or threat actor name — go to OTX Pulse Search.
- A concrete indicator (IP, domain, hash) — invoke the `lookup-ioc` skill first to get reputation, then sweep historical logs for the indicator using a `**: "<value>"` query.

If the user passed no topic, run:

```
scripts/cisa_kev_top.sh 5
```

The script prints the 5 most recently added CISA KEV entries as JSON. Pick the single most environmentally-relevant one based on what `get_scanner_context` told you. Skip CVEs whose vendor/product has no matching log source — there's nothing to hunt.

## Scanner query syntax

Read `references/scanner_query.md` before composing log queries. The two most common gotchas:

- Group OR'd values for the same field in parentheses: `field: ("a" "b" "c")`. **Never** use bare `OR`.
- For cheap IOC sweeps, use the all-fields wildcard: `**: "<IOC>"`.

## Threat-intel resources

- `lookup-ioc` skill (`../lookup-ioc/scripts/lookup_ioc.sh`) — fan-out across ThreatFox + OTX + Feodo for a single indicator. The simplest path when you already have a concrete IOC.
- `scripts/cisa_kev_top.sh [N]` — top N (default 5) recently-added CISA Known Exploited Vulnerabilities. Public feed, no auth.
- ThreatFox `taginfo`: POST `https://threatfox-api.abuse.ch/api/v1/` with body `{"query":"taginfo","tag":"<CVE-or-tag>","limit":50}`, header `Auth-Key: $ABUSECH_AUTH_KEY`. Use to enumerate IOCs tied to a CVE / malware family.
- OTX Pulse Search: GET `https://otx.alienvault.com/api/v1/search/pulses?q=<keyword>&limit=10`, header `X-OTX-API-KEY: $OTX_API_KEY`. Use for free-text keyword (campaign / actor names) — for concrete indicators use `lookup-ioc` instead.
- Feodo Tracker IP blocklist: `https://feodotracker.abuse.ch/downloads/ipblocklist.json`, header `Auth-Key: $ABUSECH_AUTH_KEY`. Pull once for network-heavy environments and sweep against CloudTrail / VPC flow / firewall logs.

## Required environment

- Scanner MCP configured.
- Optional: `OTX_API_KEY` (OTX queries), `ABUSECH_AUTH_KEY` (ThreatFox + Feodo). If absent, fall back to CISA KEV + Scanner-only hunting.

## Output

Terminal markdown only — see the template in `references/methodology.md`. Begin with `🔍 Threat Hunt Report`. End with the final "Recommended Next Questions" bullet.
