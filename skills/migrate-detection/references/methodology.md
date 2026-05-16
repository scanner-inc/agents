# migrate-detection — methodology

Read this when the user invokes `/migrate-detection`. The skill's job is to produce a Scanner detection-rule YAML that fires on the same logical condition as the source vendor rule, validated against real Scanner logs (not just `scanner-cli`).

## Phase 1: Receive input and detect source format

### Resolve the input

The user gives you exactly **one** rule, by either:

1. **Pasted content in chat** — the source rule body (full YAML / Python / KQL / TOML, or a partial like name + description + query). Work on it directly; no file fetch needed.
2. **A file path** — read it with the Read tool.

If the user pastes / passes more than one rule, process each one separately with the rest of this methodology — don't try to batch.

### What this skill does NOT do

- It does NOT walk vendor repos to find rules to migrate. That's not its job.
- It does NOT recommend which rules to migrate. Recommendations are `recommend-detections`' domain, and even there, they come from analysing the user's Scanner tenant — not from crawling vendor trees.
- If the user asks "what rules from Splunk should I port?", route them to `/recommend-detections` (which will base its answer on the tenant's coverage gaps), not to a vendor-repo crawl.

### Detect format from content

Classify by content fingerprint, NOT by extension or path. The fingerprints:

- **Splunk security_content** → has `analytic_story:` key, `search:` key with SPL macro syntax (`` `cloudtrail` ``, etc.).
- **Sigma** → `logsource:` block, `detection: { selection_*: …, condition: … }`.
- **Chronicle YARA-L** → `rule X { meta: … events: … condition: … }` (braces and `meta`/`events`/`condition` sections).
- **Panther** → `def rule(event):` Python function. Often paired with a `.yml` metadata file in the same dir; if the user passes just the `.py`, ask for / try to locate the metadata.
- **Sentinel** → JSON ARM with `"kind": "Scheduled"` and `"query"` (KQL string), or YAML with `properties.query` / top-level `queryFrequency:`.
- **Elastic** → TOML/JSON with `[rule]` block, `query: { language: kuery }`, or top-level `risk_score:` / `type: "query"`.

If multiple files were passed, classify each independently.

If the format is one we don't support (Crowdstrike Logscale, Sumo, FireEye Helix, etc.), tell the user and stop.

## Phase 2: Grep the corpus

```bash
ls corpus/
```

Each subdirectory is named `<source>_<log-source-type>_<rule-key>`. Grep for the source + log-source pair that matches the input. If a close example exists, **read both `source.<ext>` and `scanner_rule.yml`** before drafting — the corpus encodes hard-won field mappings.

If no close match exists, fall back to the source-specific cheat-sheet (`references/translation_<source>.md`).

After successful migrations, consider proposing back to the user that the result be added to the corpus (the user has to make the actual commit; the skill just suggests).

## Phase 3: Map data source

For each source format, the mapping is:

| Source identifier | Scanner identifier |
|---|---|
| Splunk `index=foo source=bar` or `datamodel:`  | A Scanner `@scnr.source_type` or `@index` |
| Sigma `logsource: { product: …, service: … }` | A Scanner `@scnr.source_type` |
| Chronicle YARA-L `$cloudtrail.metadata.vendor_name = "AMAZON"` | A Scanner `@scnr.source_type="aws:cloudtrail"` |
| Panther `event.get("eventSource")` lookups → CloudTrail | A Scanner `@scnr.source_type` |
| Sentinel `tables: [SecurityEvent]` or KQL `SecurityEvent | …` | A Scanner index |
| Elastic `query: { language: kuery, query: "process.name : ..." }` → ECS | A Scanner index using `@ecs.*` fields |

Steps:
1. Ask the user once per session: *"This rule targets `<source's data ID>`. In Scanner that maps to index `<best guess>` / source-type `<best guess>`. Correct?"*
2. After confirmation, call `get_top_columns(["<index>"])` and confirm the source's field names exist (post-mapping).
3. If the user has multiple Scanner indices that could hold the data (dev/prod, regional shards), confirm which one to test against. Backtests should use the highest-volume.

Cache the mapping in conversation state; subsequent migrations in the same session reuse it.

## Phase 4: Translate the query

Open the matching cheat-sheet (`references/translation_<source>.md`) and apply its patterns. The cheat-sheets cover:

- Token-match equivalents (Splunk's `field=*value*` → Scanner's `field:value`).
- Aggregation translations (Splunk `| stats count by user` → Scanner `| groupbycount(user)` or `| stats count() by user`).
- Conditional logic (Sigma `selection_1 and not selection_2` → Scanner `( … ) and not ( … )`).
- Field-name normalisation (UDM `principal.user.email` → AWS `userIdentity.userName`).
- Severity mapping (Sigma `level: medium` → Scanner `Medium`).

If the source rule uses a feature Scanner doesn't have natively (lookups, watchlists, reference lists, time-series anomaly detection), see Phase 6.

## Phase 5: MCP iterative testing — the heart of the skill

`scanner-cli validate` confirms YAML syntax. `scanner-cli run-tests` confirms inline unit tests. **Neither catches field-mapping drift** — a rule can validate and pass tests while returning zero hits on real production data because a field path is subtly wrong.

For each migrated rule:

1. Run the **first filter clause alone** via Scanner MCP. Apply the backtest regime from `write-detection/references/backtesting.md`:
   - Needle-in-haystack: 30–90d.
   - Broad: 1–7d.
2. **Check `n_bytes_scanned` in the response metadata.** If it's exactly **0**, the target index has zero data over the backtest window (verified empirically: empty index = 0; populated index + filter-misses = non-zero; populated index + pre-data time range = 0). Stop and tell the user: *"`@index=<alias>` returned `n_bytes_scanned: 0` — the index has no data over <window>. The user-specified target index may be wrong, or the data's ingestion window doesn't overlap. Confirm before continuing."*
3. Read the count and a few sample events.
4. **If zero hits but `n_bytes_scanned > 0`:**
   - Re-check the field paths against `get_top_columns`. Common drift: the source rule uses `eventName` but the Scanner data has `event.name` or `@ecs.event.action`.
   - Re-check token boundaries. Splunk's `field=*foo*` is leading+trailing wildcard (slow); Scanner's `field:foo` is token-match (fast) and matches `*foo*` only when `foo` is a complete token in the field's value.
   - Re-check OR semantics: Splunk supports bare `OR`; Scanner requires `field: ("a" "b")` parenthesised lists.
4. Once the filter looks right, add the aggregations and run the **full query**. Confirm the firing rate is sane.
5. If the full query produces noise floods, surface the top firers and propose tuning (see `tune-detection`).

This iterative loop is what catches "compilable but wrong" migrations. Don't skip it.

## Phase 6: Lookup-table handoff

Source-rule features that need ingest-time enrichment:

| Source feature | Scanner equivalent |
|---|---|
| Splunk `| lookup <table>` | A VRL transformation that adds an enriched field at ingest |
| Splunk `KVStore lookup` | Same |
| Sigma's asset-list integration | Same |
| Chronicle reference list | Same |
| Sentinel watchlist | Same |
| Elastic enrich processor | Same |

If the source rule references one of these, **the migrated Scanner rule alone is not enough**. Hand off to `/write-vrl`:

> Hand-off message: *"This rule depends on `<lookup name>`. Scanner enriches at ingest, not query time. Before this rule will fire correctly, you need to:*
> *1. Invoke `/write-vrl` with your lookup CSV/MMDB to author a transformation that adds `<enriched_field>`.*
> *2. Install the transformation in the Scanner UI (Settings → Transformations).*
> *3. Wait for the next ingestion cycle so the field exists in indexed data.*
> *4. Then push the migrated rule, which consumes `<enriched_field>`.*"

Document the dependency in the migrated rule's `description`:

```yaml
description: |-
  ...
  Dependency: this rule reads the enriched field `@enrichment.ip_classification`
  (added by VRL transformation `cidr_classification_v1`). Install the
  transformation before activating this rule.
```

## Phase 7: Map severity, tags, MITRE

### Severity mapping

| Source severity | Scanner severity |
|---|---|
| Sigma `informational` | `Informational` |
| Sigma `low` | `Low` |
| Sigma `medium` | `Medium` |
| Sigma `high` | `High` |
| Sigma `critical` | `Critical` |
| Splunk `risk_score:` 0–25 | `Low` |
| Splunk `risk_score:` 25–50 | `Medium` |
| Splunk `risk_score:` 50–75 | `High` |
| Splunk `risk_score:` 75–100 | `Critical` |
| Chronicle `severity: "High"` | `High` |
| Panther `Severity: HIGH` | `High` |
| Sentinel `severity: High` | `High` |
| Elastic `risk_score:` 0–21 | `Low` |
| Elastic `risk_score:` 22–47 | `Medium` |
| Elastic `risk_score:` 48–73 | `High` |
| Elastic `risk_score:` 74–100 | `Critical` |

Always apply `write-detection/references/severity_policy.md`: Medium+ → `event_sink_keys: [<...>_severity_alerts]`; Low/Informational → no event sinks (signals for correlation).

### Tag mapping

For each MITRE tag in the source rule:
1. Extract tactic/technique IDs (Sigma `attack.t1562.008`; Splunk `mitre_attack_id: T1098`; Chronicle `mitre_attack_technique_id = "T1562"`; Sentinel `relevantTechniques: [T1190]`).
2. Look up the canonical Scanner tag in `mitre_tags.md`. The format is `techniques.tNNNN.snake_case_name`. Subtechniques (`T1562.008`) → use the parent technique tag unless the parent doesn't exist in `mitre_tags.md`; Scanner's tag list is parent-technique-level.
3. Add `source.<slug>` tag based on the Scanner index/source-type.

## Phase 8: Seed inline tests

Most source repos ship example events:

- **Splunk security_content** — `tags.dataset:` URLs point to JSON datasets on splunk/attack_data.
- **Sigma** — test events embedded as `tests:` in companion files, or in `tests/` adjacent to rules.
- **Chronicle** — sample events in `rules/community/<vendor>/tests/`.
- **Panther** — `tests: [{Name, ExpectedResult, Log}]` block embedded in the same Python file (each `Log` is a dict).
- **Sentinel** — `eventGroupingSettings.aggregationKind` and test scenarios in adjacent JSON.
- **Elastic** — `tests/` adjacent.

Translate into Scanner `dataset_inline` JSONL. Sanitise IDs, ARNs, IPs to canonical examples. Each row needs an RFC-3339 `timestamp`.

If the source has no test fixtures, synthesise based on sample events pulled from MCP in Phase 5.

Required: at least one positive + at least one negative.

## Phase 9: Stage everything

Every migrated rule starts with `enabled: Staging`. The user reviews `_detections` activity for a few days before flipping to `Active`. This applies even when the source rule was enabled-by-default — the migration is a new artifact in this environment and deserves a watch period.

Update `description:` to note the migration source:

```yaml
description: |-
  ...
  Migrated from <Source: Splunk security_content / Sigma / …>. Original
  rule ID: <id>. Original location: <path>.
```

## Phase 10: Validate

```bash
scanner-cli validate -f <path-to-migrated-yaml>
scanner-cli run-tests -f <path-to-migrated-yaml>
```

Relay scanner-cli's output verbatim (`OK` for validate; `<test name>: OK` for each unit test). If either fails, iterate on the YAML.

## Phase 11: Hand off

The hand-off **always** uses the GitHub-app sync flow from SKILL.md. For VRL-dependent rules, include the explicit "install the transformation in the UI first" instruction.

Never recommend `scanner-cli sync`.

## Self-critique before emitting

- Did I run an **MCP backtest** for each migrated rule, not just `scanner-cli`?
- For VRL dependencies: is the requirement explicitly documented in `description` AND in the hand-off message?
- Are all MITRE tags from `mitre_tags.md`, not invented?
- Is `enabled: Staging` for every migrated rule?
- Does the YAML use `@index={UUID|"alias"}` form, not bare `@index=alias`?
- For Sigma/Splunk rules with `selection_1 AND NOT selection_2` — did the not-clause translate correctly? (Common bug.)
- For Splunk lookup rules: is the lookup hand-off to `/write-vrl` explicit, not assumed?

Fix and re-emit.
