# generate-health-report — methodology

Read this file when the user invokes `/generate-health-report` (or asks for the daily Scanner digest, coverage report, detection-engineering health check, etc.). It carries the full 4-phase methodology and the gap-analysis heuristics. The output template lives in `SKILL.md` itself; this file is the *how*.

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

If `truncated` is true, note it in the report.

## Phase 3: Recent activity

Use Scanner MCP `execute_query` for two queries:

1. Log volume in the last 24h grouped by source type. Example shape (adjust to current Scanner syntax): `* | groupbycount @scnr.source_type`.
2. Detection alerts in the last 24h grouped by name and severity: `@index=_detections | groupbycount name, severity`. Capture total count, counts per severity, and the top 5 rules by fire count.

Patterns to call out:
- Rules firing unusually often (possible noise or active incident).
- Rules that historically fire but are silent today (possible ingestion gap).

## Phase 4: Gap analysis

Use `references/mitre_tactics.md` as the canonical source for MITRE tag IDs and supported source slugs. Do not guess from memory.

Compute these gap categories:

- **Log-source gaps (already ingesting, not covered)**: source types currently producing meaningful volume (>100 events / 24h) but with zero or very few rules targeting them.
- **Log-source gaps (not yet ingesting, recommended)**: 1–3 high-value candidates from the supported-sources list that the customer is not ingesting. Example: if they ingest AWS but no identity provider, flag Okta or Google Workspace.
- **MITRE tactic gaps**: tactics from the canonical list with zero covered techniques in the rule library. Cite by tag (e.g., `tactics.ta0011.command_and_control`).
- **MITRE technique gaps**: techniques relevant to the customer's ingested log sources that no rule covers. Prioritize techniques that the existing log sources can support (e.g., AWS CloudTrail → `techniques.t1098.account_manipulation`, `techniques.t1578.modify_cloud_compute_infrastructure`).
- **Zombie rules**: never fired, or last fired >90 days ago. Could be stale or well-tuned; flag for review.

Generate up to 5 actionable recommendations split into two buckets:

- **Expand log sources** (1–2): specific source slugs to onboard next, drawn from `references/mitre_tactics.md`. Cite the slug exactly.
- **Expand MITRE coverage** (2–3): specific techniques to write rules for, cited by canonical tag. Map each technique to the existing log source(s) that would support it.

Recommendations must be specific. Avoid generic advice like "improve coverage" or "add more rules". Each recommendation should answer: *which source/technique, why this one, and what existing telemetry supports it.*

## Determinism

- Always cite MITRE tactic and technique IDs by canonical tag (e.g. `tactics.ta0011.command_and_control`, not "TA0011" or "Command and Control"). The reference file has the exact strings.
- Always cite Scanner source types by slug (e.g. `aws-cloudtrail`, `okta`), not by display name.
- Today's date in the title line should be ISO YYYY-MM-DD.
