---
name: posture-report
description: Produce a daily Scanner posture report for the analyst's terminal — covers environment, log volume, alert activity (split into actionable / correlation / uncategorized buckets), coverage gaps, and 2-5 specific recommended next moves. Use when the user types `/posture-report`, asks for the "posture report", "daily report", "Scanner digest", "coverage report", "health report", or any variant of "what's our detection coverage looking like". Requires Scanner MCP configured plus SCANNER_API_URL / SCANNER_API_KEY / SCANNER_TENANT_ID env vars for the Detection Rules REST API.
---

# posture-report

## Workflow

Follow the full procedure in `references/methodology.md`. The short version:

1. **Environment discovery** — Scanner MCP `get_scanner_context`.
2. **Rule inventory** — run `scripts/list_detection_rules.sh` and aggregate by severity, MITRE tactic/technique, log source, last-fired.
3. **Recent activity** — Scanner MCP `execute_query` for 24h log volume by source and 24h alert counts grouped by name + severity.
4. **Gap analysis & recommended next moves** — load `references/mitre_tactics.md` for canonical tag IDs and source slugs, then compute the gap categories described in `references/methodology.md` and produce 2-5 specific recommended next moves.

If `scripts/list_detection_rules.sh` reports `truncated: true`, mention it in the report.

## Required environment

The detection rules API needs these. The script will exit 1 with a clear message if any are missing — relay it verbatim.

- `SCANNER_API_URL` — e.g. `https://api.example.scanner.dev` (no trailing slash)
- `SCANNER_API_KEY` — bearer token with read access to `/v1/detection_rule`
- `SCANNER_TENANT_ID` — tenant UUID

Scanner MCP is a separate prerequisite (must be configured in Claude Code's MCP settings).

## Severity buckets

Scanner has eight severity values: *Unknown*, *Information*, *Low*, *Medium*, *High*, *Critical*, *Fatal*, *Other*. Group them into three buckets:

- **Actionable**: *Fatal*, *Critical*, *High*, *Medium* — fires that warrant raising to the team.
- **Correlation**: *Low*, *Information* — useful for stitching together evidence after the fact, not page-worthy on their own.
- **Uncategorized**: *Unknown*, *Other* — only surface this bucket if non-zero.

Report the actionable and correlation groups separately in *Alert Activity*, and lead the verdict with the actionable count: that's the number that determines whether someone gets paged.

## Output template

The report goes to the terminal as plain markdown. Use this exact structure; trim or omit sections that have no content (do not emit placeholder lines).

````
📊 Scanner Daily Posture — <YYYY-MM-DD>

> <One-line headline verdict in plain English. Lead with the actionable alert count first if any are present (that's what determines whether someone gets paged); otherwise lead with the dominant data/coverage story. e.g. "0 actionable alerts in the 24h window; ingestion healthy, but 4 of 14 MITRE tactics uncovered and 55 zombie rules need a tuning review.">

## Environment
<N> active · <N> staging · <N> paused · MITRE <N>/14 tactics · ~<N> techniques
Indices: <comma-separated list from get_scanner_context>

## Log Volume (24h)
```
source_type     events
aws:ecs         211,882,791
aws:cloudtrail  107,253,269
aws:lambda       74,427,683
```
(One row per source_type with non-zero volume, ordered by volume descending, max 5 rows. Right-align the events column with spaces.)

## Alert Activity (24h)
Actionable: <N> alerts (Fatal <N> · Critical <N> · High <N> · Medium <N>)
Correlation: <N> signals (Low <N> · Information <N>)
Uncategorized: <N> (Unknown <N> · Other <N>)     ← omit this entire line if both Unknown and Other are zero

Top firers (24h):
- `<rule name>` — <N> fires, <Severity>, <one-line context>
- `<rule name>` — <N> fires, <Severity>, <one-line context>

(Up to 3 rules, mix actionable and correlation as appropriate. Add inline context per row: "active incident", "expected sentinel", "known noise / junk rule", "investigate". If both groups have zero fires, write a single line: "No actionable alerts; no correlation signals in the 24h window.")

## Coverage Gaps
- <Each source with volume but no rules — one bullet per source, with the volume and the missing rule category, e.g. "aws:ecs — 212M events/day, zero ECS container-runtime rules">
- <MITRE tactics with zero or near-zero coverage, cited by canonical tag, e.g. "Zero rules: `tactics.ta0043.reconnaissance`, `tactics.ta0011.command_and_control`. Single rule only: `tactics.ta0008.lateral_movement`, `tactics.ta0009.collection`">
- <Zombie rules — never fired or last fired >90d ago — count plus one-line characterization, e.g. "55 zombie rules, heavily CloudTrail-focused, worth a tuning review">

## Recommended next moves
(based on 90-day rule activity)

- **<Action verb + target>** — <one-line rationale that doesn't repeat data from Coverage Gaps>
   → unlocks: <comma-separated MITRE tag IDs or detection patterns>
- **<Next action>** — <rationale>
   → unlocks: <...>

(2-5 recommendations. Each MUST be actionable: a specific source to onboard, a specific rule to write or replace, a specific paused rule to review. Recs are *moves*, not facts — don't reuse the Coverage Gaps phrasing.)
````

Cite MITRE IDs by canonical tag (`tactics.ta0011.command_and_control`, `techniques.t1568.dynamic_resolution`), not display name. Cite log sources by slug (`aws-cloudtrail`, `okta`).

Begin the response with the `📊` line; end with the final *Recommended next moves* bullet (or with the *Coverage Gaps* section if no actionable next moves exist). No preamble, no trailing commentary.
