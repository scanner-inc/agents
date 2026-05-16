# recommend-detections — methodology

Read this when the user invokes `/recommend-detections`. The skill's job is to look at the user's tenant, their existing rules, and their available source material, and produce an opinionated punch-list of concrete next moves — each linked to a follow-up skill the user can run.

## Phase 1: Posture snapshot

Two paths, in preference order:

### A. Re-use a recent posture-report

If the user ran `/posture-report` recently (within the last hour, visible in the terminal context), re-use its output. Pull these data points:

- Environment: active / staging / paused rule counts, MITRE tactic coverage, list of indices.
- Log volume (24h) by source-type — top 5.
- Alert activity (24h): actionable / correlation / uncategorized.
- Top firers (24h) — these feed Track B (tuning).
- Coverage gaps surfaced by posture-report — these feed Track A (new rules).

### B. Run the queries inline

If no recent posture-report is available, run the equivalent MCP queries:

```scanner
* | groupbycount @scnr.source_type   # log volume by source
```

```scanner
@index=_detections
| groupbycount name, severity        # alert activity
```

…plus a `get_scanner_context` call to enumerate indices.

Don't burn time invoking `/posture-report` mechanically every run — if its data is fresh in context, re-use it.

## Phase 2: Build the rule inventory

Pull rules from two sources and merge:

**Source A — local repos.** For each path in `SCANNER_DETECTIONS_DIR` (comma-split):

```bash
find <path> -name '*.yml' -o -name '*.yaml'
```

For each YAML, check the first line for the schema header (`# schema: https://scanner.dev/schema/scanner-detection-rule.v1.json`). Skip files without it.

**Source B — the Scanner Detection Rule API.** Catches rules created in the Scanner UI that aren't in any local repo:

```bash
posture-report/scripts/list_detection_rules.sh
# or reuse tune-detection/scripts/list_detection_rules.sh
```

Both helpers return `{rules: [...], truncated: bool, pages: N}`. Each rule includes: `id`, `name`, `severity`, `enabled_state_override`, `tags`, `query_text`, `event_sink_ids`, **`detection_rule_sync_id`** (non-null → synced from a git repo; null → UI-created).

**Merge.** Deduplicate by `name`: if a rule appears in both a local YAML and the API, the local YAML wins (it's the editable source of truth). Note in the inventory whether each rule is *local-only*, *API-only* (UI-created → flag for the Tuning track), or *both*.

For each rule extract:
- `name`
- `severity`
- `enabled` (API: `enabled_state_override`; YAML: `enabled`)
- `tags[]` (filter to canonical MITRE tags and `source.*` tags)
- `query_text` — extract any `@scnr.source_type` literal, `@index={UUID|"alias"}` references, the field names referenced in `stats … by …` clauses.
- `event_sink_keys` (YAML) / `event_sink_ids` (API) — presence indicates alert vs signal intent.
- `detection_rule_sync_id` (API only — null means UI-created)
- `source` — one of `local`, `api-ui`, `api-synced`, `both`.

Also note **OOB rules** — these are sourced from the `scanner-inc/detection-rules-*` packs (canonical list in `references/oob_packs.md`; not user-controlled, whether the user has cloned them locally or not). Don't count them in user coverage; do count them when discovering OOB packs to enable.

**Track-B note for `api-ui` rules.** A UI-created rule that's noisy belongs in the Tuning track. UI-created rules ARE fully editable in the Scanner web UI — tuning them in place is a perfectly valid quick path. For production-grade rules the user wants under change management, route through `/tune-detection`'s UI-tune workflow option C (promote to git, but disable the UI original first to avoid duplication). Surface BOTH paths in the recommendation; don't imply git is the only way to tune.

## Phase 3: Active firing data (30d)

```scanner
@index=_detections | groupbycount name, severity
```

For the top 30 rules by fire-count, also query:

```scanner
@index=_detections name="<rule name>" | groupbycount results_table.rows[0].userIdentity.arn
```

…to see whether the rule is firing on many distinct entities (probably real signal) or few entities repeatedly (probably noise candidate).

Pull rules that **never fired in 30 days** — these are "zombies" worth either retiring or tuning. The skill surfaces these as Track B (tuning) candidates.

For co-firing patterns:

```scanner
@index=_detections
| stats countdistinct(name) as rule_count by results_table.rows[0].userIdentity.arn
| where rule_count >= 2
```

(Repeat the pivot for `sourceIPAddress` and `@ecs.user.name` if those are populated.) These entities are Track C correlation candidates — show the user "user X tripped rules A, B, and C in the last 30 days; want to correlate?"

## Phase 4: Coverage matrix

Build a tactic × source table:

| Tactic | aws-cloudtrail | okta | github | …             |
|---|---|---|---|---|
| reconnaissance | 0 | 0 | 0 | |
| initial_access | 2 | 1 | 0 | |
| defense_evasion | 5 | 0 | 0 | |
| credential_access | 3 | 2 | 0 | |
| … | | | | |

Fill cells from the user's rule inventory: a rule is "in" a cell if its `tags` contain that tactic AND the rule's `@scnr.source_type` matches that source.

**Hole heuristics** (cells worth recommending):
- **Zero cells where the source has high ingest volume** — top-priority. The user has the data and no detection coverage.
- **Zero cells where the tactic is widely covered for *other* sources** — they may have meant to write the rule but forgot.
- **Cells with 1 rule that hasn't fired in 90d** — possibly a stale rule that needs replacement.

**Don't recommend** in cells where:
- The log source isn't ingested (no point recommending Okta rules if Okta isn't onboarded).
- Scanner OOB packs already cover them (recommend enabling the pack, not writing new rules — see Phase 6).

## Phase 5: Generate three tracks

### Track A — new rules (up to 10)

For each high-priority hole in the coverage matrix:

1. Pick a concrete behaviour for that tactic × source combination.
2. Draft a one-line description.
3. Identify the relevant MITRE technique from `mitre_tags.md`.
4. Estimate the backtest regime (needle-in-haystack vs broad — see `write-detection/references/backtesting.md`).
5. Sketch the starting filter clause.
6. Emit a `/write-detection` invocation:

```
- **<one-line description>** (tactic: `<tag>`, technique: `<tag>`)
  Source: `<source>` · Filter sketch: `eventName=(...)` · Regime: needle-in-haystack
  → `/write-detection write a rule for <description> on <source>`
```

Rank by `tactic_priority × log_volume`. Tactic priorities are roughly:
- **High priority:** `initial_access`, `credential_access`, `privilege_escalation`, `defense_evasion`, `exfiltration`, `impact`.
- **Medium priority:** `execution`, `persistence`, `discovery`, `command_and_control`.
- **Lower priority:** `reconnaissance`, `resource_development`, `lateral_movement`, `collection` (often case-by-case).

### Track B — tuning (up to 5)

For each rule in the top firers list at **Medium+ severity** and >10 fires/day:

```
- **`<rule name>`** firing <N>/day at <severity> — too noisy for the severity bracket
  Top noise group: `userIdentity.arn=<sample>` (<X> fires)
  → `/tune-detection <rule name or id>`
```

Also include zombie rules (never fired or 90+ days stale):

```
- **`<rule name>`** has never fired in 30d — possibly broken filter or wrong source
  → `/tune-detection <rule name>`
```

Don't suggest tuning Low / Informational rules unless their noise is overwhelming — they're signals, noise is expected.

### Track C — correlations (up to 5)

For each co-firing pattern surfaced in Phase 3, propose a correlation rule:

```
- **<entity> tripped <N> distinct rules in 30d** (`<rule A>`, `<rule B>`, `<rule C>`)
  Pivot: `results_table.rows[0].userIdentity.arn` · Suggested label: `correlation.<scoped>`
  → `/write-correlation <rule A>, <rule B>, <rule C>`
```

Filter the candidate pairs: prefer rules of different MITRE tactics (defense-evasion + credential-access is more interesting than two credential-access rules co-firing).

## Phase 6: OOB pack discovery

**No local clone required.** Use the hardcoded pack list in `references/oob_packs.md` — it's a small, stable list of `scanner-inc/detection-rules-*` repos (each pack is its own GitHub repo).

For each ingested source-type in the tenant (from `get_scanner_context.source_types`):

1. Look up the matching pack in `oob_packs.md` by source-slug.
2. Check whether the user already has rules tagged `source.<slug>` (from the Phase 2 inventory). If yes — the pack is probably already enabled OR the user has private equivalents; skip.
3. If no rules cover this source, recommend the pack.

```
- **`detection-rules-okta` pack**
  Covers: `source.okta`, MITRE: `tactics.ta0001.initial_access`, `tactics.ta0006.credential_access`
  GitHub: https://github.com/scanner-inc/detection-rules-okta
  → In Scanner UI: Settings → Sync Sources → Add Sync Source → paste the URL.
  We recommend setting all new rules to `Staging` first to monitor for noise before promoting to `Active`.
```

Don't surface a pack if any of its rules already appear in the user's local corpus (suggests they cloned-and-disabled the OOB version intentionally). Don't surface a pack for a source-type the user doesn't ingest.

## Phase 8: Render and hand off

Apply the template in `references/recommendation_templates.md`. Trim sections that have nothing to recommend (don't emit empty headings).

The **Top 5 next moves** section is opinionated — pick the five most impactful actions across all tracks and list them first. This is the section a user reads in 30 seconds; the rest is detail.

Every actionable item ends with a `/skill-name <args>` line. Make them copy-paste ready — no further interpretation needed.

The skill writes nothing. After emitting the report, the conversation is done. The user picks an item and runs the corresponding sub-skill in a new conversation (or the same one).

## Self-critique before emitting

- Did I cite log sources by slug and MITRE tags by canonical ID?
- Did I avoid recommending rules for log sources that aren't ingested?
- Did I check that OOB packs aren't already in the user's local corpus (which would suggest they're intentionally not enabled)?
- Are the Top 5 truly the 5 most impactful, or did I just take the first item from each track? Picking the right 5 requires actual judgment.
- Did I include the GitHub URLs for OOB packs? (Users need them to enable.)
- Did I trim empty sections?

Fix and re-emit.
