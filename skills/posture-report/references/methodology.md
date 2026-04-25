# posture-report — methodology

Read this file when the user invokes `/posture-report` (or asks for the daily Scanner posture report, coverage report, detection-engineering health check, etc.). It carries the full 4-phase methodology and the gap-analysis heuristics. The output template lives in `SKILL.md` itself; this file is the *how*.

## Phase 1: Environment discovery

Call Scanner MCP `get_scanner_context` to discover available indices and source types. The tenant id is bound to credentials and does not need to be passed.

## Phase 2: Rule inventory

Run `scripts/list_detection_rules.sh` (max 5 pages by default → up to 5,000 rules). It returns:

```
{ "rules": [ {...}, {...} ], "truncated": <bool>, "pages": <N> }
```

For each rule, the relevant fields are: `name`, `severity`, `tags` (MITRE tactics/techniques like `tactics.ta0005.defense_evasion`, `techniques.t1529.system_shutdown_reboot`), `query_text`, `enabled_state_override`, `last_alerted_at`.

Aggregate over the rules:

- Total active rules, staging rules, paused rules (from `enabled_state_override`).
- MITRE tactics covered — derive from `tactics.ta*` tags.
- MITRE techniques covered — derive from `techniques.t*` tags.
- Log sources covered — infer from `@index=` clauses and `%ingest.source_type:` predicates inside `query_text`.
- Rules that have never fired — `last_alerted_at` is null.
- Rules last fired >90 days ago — candidates for the *zombie* bucket.

If `truncated` is true, note it in the report.

## Phase 3: Recent activity

Use Scanner MCP `execute_query` for two queries:

1. Log volume in the last 24h grouped by source type. Example shape (adjust to current Scanner syntax): `* | groupbycount @scnr.source_type`. Render the top 5 in the report's *Log Volume* fenced code block, right-aligned.
2. Detection alerts in the last 24h grouped by name and severity: `@index=_detections | groupbycount name, severity`. Capture total count, counts per severity, and the top 3 rules by fire count.

Apply the severity-bucket rule from `SKILL.md` when reporting alert activity:

- **Actionable**: Fatal + Critical + High + Medium fires get the headline number — that's what determines whether someone gets paged.
- **Correlation**: Low + Information fires are reported separately as "signals".
- **Uncategorized**: Unknown + Other only surface if non-zero.

For the *Top firers* section, mix actionable and correlation rules as the data warrants. Each row carries a one-line inline context tag — pick from this small vocabulary:
- `active incident` — fires correspond to a known investigation.
- `expected sentinel` — high-volume rule that fires by design (e.g. canary, baseline noise).
- `known noise / junk rule` — false-positive heavy, scheduled for tuning.
- `investigate` — anomalous volume relative to 90-day baseline.

If both buckets are zero, collapse the section to one line: `No actionable alerts; no correlation signals in the 24h window.`

## Phase 4: Gap analysis

Use `references/mitre_tactics.md` as the canonical source for MITRE tag IDs and supported source slugs. Do not guess from memory.

Compute these gap categories:

- **Log-source gaps (already ingesting, not covered)**: source types currently producing meaningful volume (>100 events / 24h) but with zero or very few rules targeting them. Each becomes its own bullet in *Coverage Gaps*, with the volume and the missing rule category folded into the bullet — e.g. `aws:ecs — 212M events/day, zero ECS container-runtime rules`.
- **Log-source gaps (not yet ingesting, recommended)**: 1–3 high-value candidates from the supported-sources list that the customer is not ingesting. Surface these as recommendations, not gaps.
- **MITRE tactic gaps**: tactics from the canonical list with zero or near-zero coverage. Cite by tag and group: `Zero rules: \`tactics.ta0043.reconnaissance\`, \`tactics.ta0011.command_and_control\`. Single rule only: \`tactics.ta0008.lateral_movement\`.`
- **MITRE technique gaps**: techniques relevant to the customer's ingested log sources that no rule covers. Surface these as recommendations, not gaps.
- **Zombie rules**: never fired, or last fired >90 days ago. One bullet in *Coverage Gaps* with a count plus a one-line characterization — e.g. `55 zombie rules, heavily CloudTrail-focused, worth a tuning review`.

## Recommended next moves

A single section. 2–5 recommendations. Each rec is a *move*, not a restatement of a gap:

- Lead with a bolded action verb + target: `**Onboard \`okta\`**`, `**Write a rule for \`techniques.t1098.account_manipulation\`**`, `**Tune the 23 zombie CloudTrail rules**`.
- Follow with a one-line rationale that does not repeat Coverage Gaps phrasing.
- Add a `   → unlocks: <comma-separated MITRE tag IDs or detection patterns>` line on the next indented line.

Recommendations should be grounded in **90-day rule activity**. Two days of quiet doesn't mean a rule is broken; 90 days does. State the time-frame assumption at the top of the section: `(based on 90-day rule activity)`.

Each recommendation must be specific. Avoid generic advice like "improve coverage" or "add more rules". Each one should answer: *which source/technique, why this one, and what existing telemetry supports it.*

## Determinism

- Always cite MITRE tactic and technique IDs by canonical tag (e.g. `tactics.ta0011.command_and_control`, not "TA0011" or "Command and Control"). The reference file has the exact strings.
- Always cite Scanner source types by slug (e.g. `aws-cloudtrail`, `okta`), not by display name.
- Today's date in the title line should be ISO YYYY-MM-DD.
- The verdict blockquote leads the report — make it the *one* thing a reader who reads nothing else would walk away with.
