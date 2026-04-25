---
name: generate-health-report
description: Produce a daily Scanner detection-engineering digest for the analyst's terminal — covers environment, log volume, alert activity, coverage gaps, and 2-5 specific recommendations to expand log sources and MITRE coverage. Use when the user types `/generate-health-report`, asks for the "daily report", "health report", "Scanner digest", "coverage report", or any variant of "what's our detection coverage looking like". Requires Scanner MCP configured plus SCANNER_API_URL / SCANNER_API_KEY / SCANNER_TENANT_ID env vars for the Detection Rules REST API.
---

# generate-health-report

## Workflow

Follow the full procedure in `references/methodology.md`. The short version:

1. **Environment discovery** — Scanner MCP `get_scanner_context`.
2. **Rule inventory** — run `scripts/list_detection_rules.sh` and aggregate by severity, MITRE tactic/technique, log source, last-fired.
3. **Recent activity** — Scanner MCP `execute_query` for 24h log volume by source and 24h alert counts grouped by name + severity.
4. **Gap analysis & recommendations** — load `references/mitre_tactics.md` for canonical tag IDs and source slugs, then compute the gap categories described in `references/methodology.md` and produce 2-5 specific recommendations.

If `scripts/list_detection_rules.sh` reports `truncated: true`, mention it in the report.

## Required environment

The detection rules API needs these. The script will exit 1 with a clear message if any are missing — relay it verbatim.

- `SCANNER_API_URL` — e.g. `https://api.example.scanner.dev` (no trailing slash)
- `SCANNER_API_KEY` — bearer token with read access to `/v1/detection_rule`
- `SCANNER_TENANT_ID` — tenant UUID

Scanner MCP is a separate prerequisite (must be configured in Claude Code's MCP settings).

## Output template

The report goes to the terminal as plain markdown. Use this exact section structure; trim or omit sections that have no content (do not emit placeholder lines).

```
📊 Scanner Daily Report — <YYYY-MM-DD>

## Environment
- Active rules: N | Staging: N | Paused: N
- Indices: <comma-separated list from get_scanner_context>
- MITRE tactics covered: N of 14 | Techniques covered: N

## Log Volume (last 24h, top 5)
- `<source_type>` — N events
- `<source_type>` — N events
  (omit unused slots; do not write "(no other sources)")

## Alert Activity (last 24h)
- Total: N alerts | Critical: N | High: N | Medium: N | Low: N
- Top firing rules:
  - `<rule name>` — N fires
  - `<rule name>` — N fires
  (if zero rules fired in the window, write a single line: "No rules fired in the last 24h.")

## Coverage Gaps
- Log sources with volume but no rules: `<slug>` (N events/day), `<slug>` (N events/day)
- MITRE tactics with zero coverage: <canonical tag IDs from mitre_tactics.md>
- Zombie rules (no fire in >90 days): N rules

## Recommendations — Expand log sources
- <Specific source slug to onboard, why this one, what techniques it would unlock — cite slugs from references/mitre_tactics.md>

## Recommendations — Expand MITRE coverage
- <Specific technique tag, why it matters for this environment, which existing log source supports it>
- <Another technique>
```

Cite MITRE IDs by canonical tag (`tactics.ta0011.command_and_control`, `techniques.t1568.dynamic_resolution`), not display name. Cite log sources by slug (`aws-cloudtrail`, `okta`).
