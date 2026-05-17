---
name: migrate-detection
description: Translate a **single** detection rule from another SIEM (Splunk, Sigma, Chronicle YARA-L, Panther, Azure Sentinel, Elastic) into a Scanner detection-rule YAML. The user provides the source rule by **pasting it in chat** (full YAML / Python / KQL, or even just name + description + query) or by **giving a file path** to it. Auto-detects the source format from content (not filename or path), maps the source's data model to Scanner's source-type fields, iteratively tests the translated query against real Scanner logs via MCP (this is the heart of the workflow — `scanner-cli validate` alone is not enough), seeds inline unit tests from source fixtures or sampled real events, and validates with `scanner-cli`. For rules that use vendor lookup tables (Splunk lookups, Sentinel watchlists, Chronicle reference lists), routes the user to `/write-vrl` for ingest-time enrichment then consumes the enriched field. Always writes migrated rules with `enabled: Staging`. Use when the user types `/migrate-detection`, pastes a vendor rule, asks Claude to "migrate this Splunk rule", "convert this Sigma rule", "translate this Chronicle YARA-L into Scanner", "port this Panther detection", or "convert this Sentinel KQL rule". This skill does NOT walk vendor repos or recommend rules to port — that's not its job; it takes whatever single rule the user hands it and translates it. Requires Scanner MCP, `SCANNER_API_URL` + `SCANNER_API_KEY` for `scanner-cli`, and `SCANNER_DETECTIONS_DIR` (comma-separated paths to the user's Scanner detection-rule repos — destination for the migrated YAML).
---

# migrate-detection

## When to invoke

Trigger on any of:
- The user types `/migrate-detection` with or without an argument.
- The user pastes vendor rule content directly into chat (full YAML / Python / KQL, or even just the rule's name + description + query — the skill works with whatever it gets).
- The user gives a single file path to a vendor rule on disk.
- The user asks to migrate, convert, translate, or port a single rule from another SIEM.

If the user wants to author a brand-new rule, route to `/write-detection`.
If they want a correlation rule, route to `/write-correlation`.

## Input modes

This skill translates **one rule at a time**. Two ways the user provides it:

1. **Pasted content in chat** — the user pastes the source rule (full content, or just `name` + `description` + `query`) directly. The skill auto-detects format from content.
2. **A file path** — `~/path/to/some_rule.yml` (or `.yaral` / `.py` / `.toml` / `.json`). The skill reads the file and processes it the same way.

**Not in scope:**
- This skill does **not** walk vendor rule trees (Sigma, security_content, etc.) and pick rules to migrate. It doesn't recommend "which rules from Splunk would be valuable to port" — that's `recommend-detections`' domain, and even there, recommendations come from analysing the user's tenant, not from crawling vendor repos.
- This skill does **not** bulk-migrate a directory of rules in one shot. If the user wants 3 rules migrated, that's 3 separate `/migrate-detection` invocations.

**Pattern for "migrate this directory":** if the user has a directory of vendor rules and wants several migrated, they can ask Claude (the main conversation, not this skill) to "run `/migrate-detection` on each file in `<dir>`". Claude then loops, invoking this skill per rule and aggregating per-rule pass/fail. The skill itself stays single-rule.

## Supported source formats (v1)

Format detection works on **file content**, not filename / extension / path. Heuristics:

| Source | Content fingerprint | Cheat-sheet |
|---|---|---|
| **Splunk security_content** | `analytic_story:` key, `search:` field with SPL | `references/translation_splunk.md` |
| **Sigma** | `logsource:` block, `detection: { selection_*, condition: … }` | `references/translation_sigma.md` |
| **Chronicle YARA-L 2.0** | `rule X { meta: … events: … condition: … }` | `references/translation_chronicle.md` |
| **Panther** | `def rule(event):` (paired metadata YAML often alongside) | `references/translation_panther.md` |
| **Azure Sentinel** | ARM JSON with `"kind": "Scheduled"`, or YAML with `properties.query` (KQL) | `references/translation_sentinel.md` |
| **Elastic** | TOML/JSON with `query: { language: kuery }` / `risk_score:` / `[rule]` block | `references/translation_elastic.md` |

The `scanner-cli migrate-elastic-rules` command exists but is beta and unreliable — this skill performs **all** migrations through the model + MCP, not via that command.

## Required environment

- **Scanner MCP** configured. Iterative testing against real logs is the heart of this skill — `scanner-cli` alone won't catch field-mapping drift.
- `SCANNER_API_URL`, `SCANNER_API_KEY` — for `scanner-cli validate` / `run-tests`.
- `SCANNER_DETECTIONS_DIR` (recommended) — comma-separated absolute paths to write migrated YAML to. Falls back to asking per-invocation.
- `scanner-cli` on PATH.

## Workflow

Follow the full procedure in `references/methodology.md`. The short version:

1. **Detect source format** by extension + content heuristics.
2. **Grep the corpus** in `corpus/` for the closest worked example (matching source × log family). If a near-match exists, use it as the starting template. This is faster and more accurate than translating from scratch.
3. **Map data source → Scanner index/source-type.** Ask the user once per session. Confirm fields with `get_top_columns`.
4. **Translate the query** using the per-source cheat-sheets in `references/translation_<source>.md`.
5. **MCP iterative testing** — the heart of the skill. For each migrated rule: filter-clause sanity check, full query, observe results, adjust mappings, re-query. Loop until firings make sense. Many compilable migrations silently fail on field-mapping drift; only real-data tests catch this.
6. **Lookup tables → VRL hand-off.** If the source rule references a lookup / list / watchlist / reference list, the data must be enriched at Scanner *ingest* time, not query time. Invoke `/write-vrl` separately to author the transformation; consume the enriched field in the migrated rule and document the dependency in `description`.
7. **Map severity, tags, MITRE.** Source severity → one of Scanner's 8 OCSF strings. Source MITRE → canonical Scanner tag (`techniques.tNNNN.subtechnique_slug`); never display names. Always add `source.<slug>` (e.g., `source.cloudtrail`).
8. **Seed inline tests** from source-repo fixtures where available (most repos ship example events). Translate into Scanner `dataset_inline` JSONL. Panther test fixtures are Python dicts; the model converts.
9. **Stage everything.** All migrated rules → `enabled: Staging`, regardless of source state. The user promotes to `Active` after monitoring `_detections`.
10. **Bulk validate.** `scanner-cli validate -d <dir> -r` and `scanner-cli run-tests -d <dir> -r`. Table of file → pass/fail.
11. **Hand off** via the GitHub-app sync flow (below).

## Three patterns the cheat-sheets cover

- **1:1 translation** — vendor rule → Scanner rule, no lookups, no decomposition.
- **VRL-enriched** — vendor uses a lookup/list; Scanner consumes an enriched field added via `/write-vrl`.
- **Decomposed + correlated** — a compound vendor rule (multiple distinct behaviours, temporal logic, sequence) becomes two or three Scanner rules plus a correlation rule via `/write-correlation`. Document the trade-off in `description` (not strictly equivalent; catches what you need).

See the corpus for one example of each pattern.

## Sync flow (always use this hand-off)

The Scanner GitHub app watches `main` and syncs on green. Never recommend `scanner-cli sync`. Hand-off:

> 1. Commit the migrated YAMLs to your detection-rules repo.
> 2. Push to `main` (or open a PR and merge).
> 3. For VRL-dependent rules: separately install the VRL transformation in the Scanner UI under Library → Transformations so the enriched field exists by the time the rule queries it. Lookup tables go under Library → Lookup Tables (or via the beta Lookup Tables API: https://docs.scanner.dev/scanner/using-scanner-complete-feature-reference/unstable/lookup-tables).
> 4. The GitHub app validates and syncs.
> 5. The rules start in `Staging`. Watch `_detections` for a few days, then promote individually to `Active`.

## Output

Respond to the user with:

1. **The detected source format** and which cheat-sheet was used.
2. **The corpus example** used as a template, if any (or "no close match — translated from scratch").
3. **Per-rule status table** if migrating multiple rules: file → ✓/✗ → backtest fire-rate (if backtested) → notes.
4. **The validate + run-tests result** for the migrated YAML.
5. **The expected fire rate** from the MCP backtest, regime-appropriate window per `write-detection/references/backtesting.md`.
6. **VRL dependencies** (if any) — explicit instruction to invoke `/write-vrl` and install the transformation before the rules can fire correctly.
7. **The GitHub-app sync flow.**

Keep it tight. The YAML files are the deliverable; everything else is verification + dependency context.

## Layout

```
migrate-detection/
├── SKILL.md                          # this file
├── references/
│   ├── methodology.md                # full procedure with MCP iterative loop
│   ├── source_repos.md               # paths and layout of local source-SIEM repos
│   ├── translation_splunk.md         # SPL → Scanner cheat-sheet
│   ├── translation_sigma.md          # Sigma YAML → Scanner cheat-sheet
│   ├── translation_chronicle.md      # YARA-L 2.0 → Scanner cheat-sheet
│   ├── translation_panther.md        # Panther Python → Scanner cheat-sheet
│   ├── translation_sentinel.md       # Sentinel KQL → Scanner cheat-sheet
│   ├── translation_elastic.md        # Elastic KQL/EQL → Scanner cheat-sheet
│   └── mitre_tags.md                 # canonical Scanner-supported MITRE tags
└── corpus/                           # worked side-by-side examples
    ├── corpus_index.md
    └── <source>_<source-type>_<rule-name>/
        ├── source.<ext>              # original vendor rule
        ├── scanner_rule.yml          # Scanner equivalent
        ├── README.md                 # what changed, gotchas
        ├── enrich.vrl                # only when VRL enrichment is needed
        └── lookup_*.csv              # fixtures only when needed
```
