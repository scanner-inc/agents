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

Emit the report in terminal markdown. Substitute bracketed placeholders.

````
🔍 Threat Hunt Report

> <One-line headline verdict in plain English. The most important sentence in the report — the one a reader who reads nothing else would walk away with. State the result *and* the most consequential nuance, e.g. "🟢 No evidence of SimpleHelp exploitation across 180 days; the real story is that 4 of 5 KEV entries target log sources we don't ingest — coverage gap, not detection gap.">

Hunt: <CVE ID(s)> — <vulnerability or threat name> | <vendor/product or threat family>
Range: <start date> → <end date> · Confidence: NN% (High | Medium | Low) · Result: 🟢 NO EVIDENCE FOUND | 🟡 INCONCLUSIVE | 🔴 EVIDENCE OF COMPROMISE
Intel: CISA KEV (added <date>) + <ThreatFox / OTX / Feodo as applicable>

IOCs searched — <one-line summary, e.g. "all clean, 786 GB scanned">
```
162.243.103.246   Emotet C2   DigitalOcean        seen 2026-03-07
50.16.16.211      QakBot C2   AWS EC2 (online)    seen 2025-12-30
api.malicious.example   Akira C2   first-seen 2026-01-12
```
<1-2 lines of prose context — what each threat-intel tool returned, e.g. "ThreatFox had no IOCs for CVE-2024-57726; OTX Akira pulse yielded contextual TTPs only.">

[Pick exactly one of the two sections below — *Why this came back clean* for hunts with no hits, *Findings* for hunts with positive hits. Don't emit both.]

Why this came back clean:
<1-3 sentences explaining the analytical insight — *why* nothing matched. Examples: "Four of five KEV entries target on-prem appliances not represented in this cloud-native environment." or "Hunt scope necessarily pivoted to generic C2 sweeps because ThreatFox had no IOCs seeded for these CVEs.">

Findings:
- ✓ or ✗ <What was searched and what was or was not found, with `technical details`>
- ✓ or ✗ <Next finding>

Timeline (only if suspicious activity found; omit the whole section if not):
- `<timestamp>` <event>
- `<timestamp>` <event>

MITRE ATT&CK: <Tactics and techniques hunted for, cited by canonical tag: `tactics.ta0002.execution`, `techniques.t1190.exploit_public_facing_application`, etc.>

Visibility gaps (in order of fixability — closable gaps first, environmental facts last; cap at 4):
- *<Most-actionable gap>* — <what hunting capability it would unlock; name the specific IOC or TTP it relates to, e.g. "would have caught egress C2 to AWS-hosted QakBot node `50.16.16.211`">
- <Next gap, same structure>

Next questions (cap at 2; only include if they would actually unblock further work):
- <Follow-up that would close the most actionable visibility gap or confirm an applicability question>
- <Follow-up about scope or broader context>
````

Output rules:
- The verdict blockquote leads. There is no other blockquote in the report — don't scatter `>` lines across sections.
- IOCs go in a fenced code block with aligned columns (indicator, family/role, hosting/context, last-seen). One-line summary on the section header. Tables-as-prose ("`162.243.103.246` (Emotet C2, DigitalOcean), `50.16.16.211` (QakBot C2, AWS), …") is harder to scan; use the fenced block.
- Pick exactly one of *Why this came back clean* OR *Findings* — never both. Clean hunts deserve analytical insight, not an empty findings section.
- Cap *Visibility gaps* at 4, ordered by fixability. Environmental facts ("we're a cloud-native shop, this CVE targets on-prem appliances") go last — they're context, not action items.
- Cap *Next questions* at 2, and skip the section if the only follow-ups would be filler.
- Keep the report compact — aim for one screen, not a blog post.
