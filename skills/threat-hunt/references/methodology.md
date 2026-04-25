# threat-hunt — methodology

Read this file when running `/threat-hunt`. It carries the 5-phase hunt procedure and the report template.

## Phase 1: Environment discovery

Call Scanner MCP `get_scanner_context` to discover available log sources. Identify what platforms, vendors, services, and log types exist (AWS CloudTrail? Identity provider? Endpoint EDR? Network flow?). This determines what is searchable — and therefore what threats are worth hunting for.

Note what kinds of IOCs are searchable in this environment:
- IPs in network and CloudTrail logs
- Domains in DNS / proxy logs
- File hashes in endpoint logs
- User agents, process names, etc.

## Phase 2: Threat-intelligence gathering

Pick a hunt target. The user may have passed a topic on the command line (a CVE ID, a malware family name, an IOC). If they didn't, run `scripts/cisa_kev_top.sh 5` to fetch the 5 most recently added CISA Known Exploited Vulnerabilities.

**Filter for environmental relevance.** Skip vulnerabilities for products or vendors that don't appear in the available log sources. Prioritize:
- AWS / cloud logs → cloud-relevant CVEs
- Identity provider logs → auth-related CVEs
- Network logs → CVEs in network-facing products
- Endpoint logs → workstation / server-product CVEs

Once you have picked a target, gather IOCs:

- Use `lookup-ioc` (`../lookup-ioc/scripts/lookup_ioc.sh <indicator>`) for any concrete indicator already in hand — fastest path to ThreatFox / OTX / Feodo coverage in one call.
- For a CVE, use ThreatFox's `taginfo` query (the n8n workflow's "ThreatFox Search"): POST to `https://threatfox-api.abuse.ch/api/v1/` with body `{"query":"taginfo","tag":"<CVE-ID>","limit":50}` and `Auth-Key: $ABUSECH_AUTH_KEY` header. Returns IOCs (IPs, domains, URLs, hashes) tied to that CVE.
- For a malware family / threat actor / campaign keyword, use OTX Pulse Search: GET `https://otx.alienvault.com/api/v1/search/pulses?q=<keyword>&limit=10` with `X-OTX-API-KEY: $OTX_API_KEY` header.
- For network-heavy environments, also pull current Feodo Tracker botnet C2 IPs to sweep historical network logs.

**Determine the search time range** based on threat-intel timeline:
- When was the vulnerability disclosed or added to KEV?
- When were the IOCs first reported (ThreatFox `first_seen`, OTX pulse creation date)?
- Set the search window from the earliest known threat activity to the present. Examples: a 2023 CVE with IOCs first seen 18 months ago → 2+ years. A campaign reported last month → 90 days is enough.

## Phase 3: Historical log analysis

Read `references/scanner_query.md` first if the syntax rules aren't fresh in mind.

**Strategy: IOC sweep first, then pivot.**

1. Start with broad IOC sweeps using `**: "<IOC>"` queries (one query per IOC or small batch). These are cheap because they search every field across the index range.
2. Only on a hit: pivot to a targeted behavioral query against the specific index to build context (what happened before and after, same user or source, etc.).
3. If sweeps are clean, you are done searching. Do not run speculative behavioral queries when there is nothing to investigate.

**Query budget**: 3-6 total queries for a clean hunt; more only if you find hits.

## Phase 4: Correlation and assessment

If you found hits:

- Cross-reference findings across log sources.
- Build a timeline.
- Map activity to MITRE ATT&CK tactics and techniques (cite by canonical tag like `tactics.ta0002.execution`, `techniques.t1190.exploit_public_facing_application`).
- Assess scope: affected systems, users, time range.
- Identify visibility / telemetry gaps — log sources you wished you had, time periods with no coverage.

## Phase 5: Final output

Emit the report in terminal markdown. Substitute bracketed placeholders. Omit the `Timeline` section entirely if no suspicious activity was found.

```
🔍 Threat Hunt Report

Hunt Target: <CVE ID or malware family> — <vulnerability name> | <vendor / product>
Intel Source: <CISA KEV (added <date>) + ThreatFox / OTX / Feodo as applicable>

TL;DR: <2 sentences. First: what was hunted and the scope. Second: whether evidence of exploitation was found, and the recommended action.>

IOCs Searched:
- `<IP>` — <context, e.g. "C2 server from ThreatFox, malware family X">
- `<domain>` — <context>
- `<sha256 hash>` — <context, "malware payload first seen 2026-02-10">

Hunt Results: 🟢 NO EVIDENCE FOUND | 🟡 INCONCLUSIVE | 🔴 EVIDENCE OF COMPROMISE
Confidence: NN% (High | Medium | Low)
Time Range Searched: <start date> — <end date>

Findings:
- ✓ or ✗ <Finding 1 — what was searched, what was found or not>
- ✓ or ✗ <Finding 2 with `technical details`>
- ✓ or ✗ <Finding 3>

Timeline:  (omit this whole section if there is no suspicious activity)
- `<timestamp>` <event>
- `<timestamp>` <event>

MITRE ATT&CK: <canonical tags hunted, e.g. `techniques.t1190.exploit_public_facing_application`>

> <Blockquote for the most critical finding or context>

Visibility Gaps:
- <Log source or telemetry that was missing>
- <Time periods with no coverage>

Recommended Next Questions:
- <Investigative follow-up>
- <Question about visibility gaps>
- <Question about broader context>
```

Keep the report compact — aim for one screen, not a blog post.
