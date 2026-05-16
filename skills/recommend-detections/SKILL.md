---
name: recommend-detections
description: Produce a prioritised list of concrete, copy-paste-ready detection-engineering recommendations for the user's Scanner tenant — new rules to write, existing rules to tune, correlations to add, and Scanner OOB packs worth enabling. Consumes posture-report output as one input, walks every YAML in `SCANNER_DETECTIONS_DIR` AND pulls the tenant's full rule inventory via the Detection Rule API (catches UI-created rules too), queries `_detections` over 30 days to find noise / co-firing entities, and surfaces installable OOB packs from a hardcoded list of `scanner-inc/detection-rules-<source-type>` repos (no local clone needed). Each recommendation ends with the exact `/write-detection`, `/tune-detection`, or `/write-correlation` invocation needed to act on it. Read-only — writes nothing. Use when the user types `/recommend-detections`, asks "what detections should I add?", "where are my detection gaps?", "what should I be alerting on?", or "give me detection engineering ideas for this tenant". Does NOT walk foreign-SIEM rule repos to recommend migrations — recommendations are derived from the tenant's own coverage gaps and firing patterns, not from crawling Sigma/Splunk/etc. If the user has a specific vendor rule they want ported, they invoke `/migrate-detection` directly with the rule pasted or path given. Requires Scanner MCP configured, `SCANNER_API_URL` + `SCANNER_API_KEY` + `SCANNER_TENANT_ID` (for the Detection Rules REST API via posture-report), and `SCANNER_DETECTIONS_DIR` (comma-separated paths to the user's Scanner detection-rule repos).
---

# recommend-detections

## When to invoke

Trigger on any of:
- The user types `/recommend-detections`.
- The user asks "what detections should I add?", "where are my detection gaps?", "what should I be alerting on?", "give me detection-engineering ideas", "what's the next rule I should build?"
- The user just ran `/posture-report` and asks "what do I do next?"

If the user wants to author a *specific* rule, route to `/write-detection`. This skill is the **prioritiser** that decides what's worth writing — it then routes the user to `/write-detection` for the actual work.

## Required environment

- **Scanner MCP** configured.
- `SCANNER_API_URL`, `SCANNER_API_KEY`, `SCANNER_TENANT_ID` — for the Detection Rules REST API (reusing the `scripts/list_detection_rules.sh` script from `posture-report`).
- `SCANNER_DETECTIONS_DIR` (recommended) — comma-separated absolute paths to the user's detection-rule repos. Falls back to asking per-invocation.

## Workflow

Follow the full procedure in `references/methodology.md`. The short version:

1. **Posture snapshot.** Pull environment, log sources, severity distribution, recent activity. Either invoke `/posture-report` (and re-use its output) or run the equivalent MCP queries inline. Reading recent terminal context is fine if posture-report was just run.

2. **Walk local rule corpus.** For each path in `SCANNER_DETECTIONS_DIR`, walk every YAML file. Extract: `name`, `severity`, `enabled`, `tags`, `query_text` (specifically the `@scnr.source_type` or `@index` references), `event_sink_keys`. Build an in-memory rule inventory.

3. **Active firing data.** Query `_detections` over the last 30 days, grouped by rule `name` × `severity`. This reveals:
   - **Noise candidates** — top firers, especially at Medium+ severity (Track B candidates).
   - **Co-firing entities** — multiple distinct rule names firing on the same entity (`results_table.rows[0].userIdentity.arn` etc.) — Track C candidates.
   - **Zombie rules** — never-fired or last-fired-90d+-ago.

4. **Build coverage matrix.**
   - Rows: MITRE tactics × techniques (canonical IDs from `references/mitre_tags.md`).
   - Columns: log sources actually ingested (from posture-report's source-type list).
   - Cell value: number of **user-controlled** rules covering that intersection (tags-based).
   - Mark holes.

5. **Generate three tracks:**
   - **Track A — new rules** for holes in the matrix, ranked by tactic priority × log-source volume.
   - **Track B — tuning** for top noise firers.
   - **Track C — correlations** from co-firing patterns in `_detections`.

6. **OOB pack discovery.** Use the hardcoded list in `references/oob_packs.md` (the canonical `scanner-inc/detection-rules-*` packs — each pack is its own GitHub repo). For each ingested log source (from posture step 1), look up the matching pack and check whether the user already has rules tagged `source.<slug>`. If not, recommend enabling — with the GitHub URL and the Scanner UI instruction. No local clone of any OOB pack required.

8. **Render the report.** Terminal markdown in the structure documented in `references/recommendation_templates.md`. Every actionable item ends with a copy-paste-ready `/skill-name <args>` command, or — for OOB packs — the UI path plus the GitHub repo URL.

## What the skill does NOT do

- It does **not write any files**. Read-only.
- It does **not run** the recommended `/write-detection` etc. for you — those are *next* invocations the user picks.
- It does **not** modify `posture-report`; it consumes posture-report's output and uses it as one input among several.

## Output template (see `references/recommendation_templates.md` for full detail)

The report uses this skeleton:

```
🧭 Scanner Detection Recommendations — <YYYY-MM-DD>

> <One-line opinionated headline: what's the single most important move?>

## 🎯 Top 5 next moves
(the opinionated short-list — act on these this week)
1. **<action verb + target>** → `/<skill-name> <args>` — <1-line rationale>
…

## 📈 Coverage matrix
(compact heatmap: tactic × source, cells show rule count, holes marked)

## 🆕 New rule ideas (Track A)
(up to 10, ranked by tactic priority × log-source volume)
…each entry ends with `/write-detection <prompt>`…

## 🔧 Tuning opportunities (Track B)
(up to 5, top firers at Medium+ severity)
…each entry ends with `/tune-detection <rule-id-or-name>`…

## 🔗 Correlation opportunities (Track C)
(up to 5, co-firing patterns from _detections)
…each entry ends with `/write-correlation <rule-name-list>`…

## 📦 OOB packs to enable
(up to 5, matching ingested log sources)
…each entry shows: pack name + UI step + GitHub URL…
```

## House-style conventions

- Cite MITRE tags by canonical ID only (`tactics.ta0005.defense_evasion`, `techniques.t1078.valid_accounts`). Use `references/mitre_tags.md`.
- Cite log sources by slug (`aws-cloudtrail`, `okta`).
- Lead the report with the verdict blockquote — one line, opinionated.
- Trim sections that have nothing to recommend (don't emit `## 🔗 Correlation opportunities` with "no recommendations").

## Layout

```
recommend-detections/
├── SKILL.md                          # this file
└── references/
    ├── methodology.md                # full procedure
    ├── recommendation_templates.md   # markdown templates for each track + top-5
    ├── coverage_heuristics.md        # how to rank holes; what makes a good correlation candidate
    ├── oob_packs.md                  # hardcoded list of scanner-inc/detection-rules-* packs (no local clone needed)
    └── mitre_tags.md                 # canonical Scanner-supported MITRE tags
```
