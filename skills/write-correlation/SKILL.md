---
name: write-correlation
description: Author a Scanner correlation detection rule — one that fires when multiple other rules co-fire on the same entity (user, IP, host) within a time window. Joins constituent rules via a custom `correlation.<label>` tag (which the skill writes onto each constituent rule's YAML), pivots on an entity column from each rule's `results_table.rows[0].*`, and uses `countdistinct(name)` to count distinct rule names — never the opaque `detection_rule_id`. Falls back to joining by rule `name` when a constituent is an out-of-the-box rule the user can't edit. Verifies the firing rate against `_detections` via Scanner MCP before recommending the user push. Use when the user types `/write-correlation`, asks Claude to "write a correlation rule", or says "alert me when rules X, Y, Z fire on the same user in 10 minutes". Requires Scanner MCP configured, `SCANNER_API_URL` + `SCANNER_API_KEY` for `scanner-cli`, and `SCANNER_DETECTIONS_DIR` (comma-separated paths to local rules repos).
---

# write-correlation

## When to invoke

Trigger on any of:
- The user types `/write-correlation` with or without a list of rule names.
- The user says "write a correlation rule", "alert when these rules fire together", "if rule A fires before rule B".
- The user describes a pattern like "two privilege-escalation rules firing on the same user in 10 minutes is worth a Critical alert".

If the user wants to write a brand-new single detection rule (not a correlation), route to `/write-detection`.
If they want to tune a noisy existing rule, route to `/tune-detection`.

## Required environment

- **Scanner MCP** configured.
- `SCANNER_API_URL`, `SCANNER_API_KEY` — for `scanner-cli validate`.
- `SCANNER_DETECTIONS_DIR` (recommended) — comma-separated absolute paths to local rule repos.
- `scanner-cli` on PATH.

## The pattern (verified)

The correlation rule queries `_detections`, filters by a custom tag the user owns, and groups by an entity shared across the constituent rules:

```scanner
@index={ <_detections-uuid> | "_detections" }
tags[*]:correlation.<custom_label>
| stats countdistinct(name) as rule_count by results_table.rows[0].<entity>
| where rule_count >= <N>
```

Why this shape:
- `tags[*]:correlation.<label>` matches across all positional `tags[N]` fields of `_detections` events. Verified during planning: 53 hits over 7d on `tags[*]:source.cloudtrail`.
- `results_table.rows[0].<entity>` exposes the constituent rule's grouping key (the first result row's value). Common pivots: `userIdentity.arn`, `sourceIPAddress`, `@ecs.user.name`, `@ecs.source.ip`.
- `countdistinct(name)` counts distinct rule **names** (human-readable, present in YAML) — **never** `detection_rule_id` (opaque, not in YAML, brittle).

Use `[*]` (single bracket-level wildcard), **not** `[**]` (which is for deep-path matching through nested objects/arrays — overkill for a flat array of strings).

## Workflow

Follow the full procedure in `references/methodology.md`. The short version:

1. **Identify the constituent rules.** Two paths:
   - The user names them (most common). Locate each YAML by searching, in order: every path in `SCANNER_DETECTIONS_DIR`; then `curl` raw GitHub for the matching `scanner-inc/detection-rules-<source>` pack (each pack is its own GitHub repo — see `recommend-detections/references/oob_packs.md` for the list); then the Detection Rule API for UI-created rules. If the user has cloned individual OOB packs locally and gives you a path, you can also grep there.
   - The skill suggests candidates by querying `_detections` and clustering rules that co-fire on the same `results_table.rows[0].<entity>`.

2. **Pick the correlation handle for each constituent.** Two paths:
   - **User-controlled rule** (under any path in `SCANNER_DETECTIONS_DIR`): add a custom `correlation.<custom_label>` tag to the rule's `tags:` block. The skill edits the YAML and remembers to include it in the hand-off list.
   - **Out-of-the-box rule** (sourced from a `scanner-inc/detection-rules-*` pack — read-only whether the user cloned the OOB tree locally or not): recommend the **fork-and-disable** workflow. See "OOB rules — fork and disable" below.

3. **Pick the pivot entity.** Query `get_top_columns(["_detections"])` to see which `results_table.rows[0].*` columns are populated. Common pivots: `userIdentity.arn`, `sourceIPAddress`, `@ecs.user.name`. Pick the one shared by all constituent rules.

4. **Pick the time window.** `time_range_s` defaults to 600 (10 minutes). `run_frequency_s` defaults to 60.

5. **Draft the correlation YAML.** See `references/correlation_patterns.md` for the full template. Resolve the `_detections` UUID via the MCP query `@index=_detections | head 1 | table(@index, @index_id)` — the `@index_id` field is the UUID. Severity defaults to **one level above** the loudest constituent (Medium constituents → High correlation). Always `enabled: Staging`. Tags = union of constituent tags + `correlation.<custom_label>`.

6. **Sanity-check via MCP.** Run the correlation query over the last 14–30 days. Report:
   - Expected daily fire rate.
   - Top 5 entities by `rule_count` — these are the historical hits the rule would have flagged.
   If too noisy: raise `rule_count >= N` threshold, or narrow the tag set.

7. **Validate.** `scanner-cli validate -f <correlation-rule-path>`.

8. **Hand off** via the GitHub-app sync flow — see "Sync flow" below. The user must commit **all** modified files: the new correlation rule YAML + every constituent rule YAML the skill added the `correlation.<custom_label>` tag to.

## OOB rules — fork and disable

When a constituent is an OOB rule (from a `scanner-inc/detection-rules-*` pack — see `recommend-detections/references/oob_packs.md`), **the user can't edit the YAML in place** (it's read-only, owned by Scanner). Two options, in preference order:

### Preferred — fork-and-disable

1. **Obtain the OOB YAML.** Default: `curl -sSL "https://raw.githubusercontent.com/scanner-inc/detection-rules-<source>/main/rules/<file>.yml"` (list available files via the GitHub contents API if needed). Or, if the user gives you a local path to the cloned pack, read it from there. **Copy** the YAML into one of the user's private repos in `SCANNER_DETECTIONS_DIR`. The skill writes the copy and inserts the `correlation.<custom_label>` tag.
2. Tell the user: *"You'll need to **disable the original OOB rule in the Scanner UI** (Settings → Detection Rules → search for `<name>` → toggle off). The Scanner UI is the only place the OOB toggle exists. Once disabled, your private clone takes over."*
3. The private clone is now a normal user-controlled rule — it can be tuned, re-tagged, etc.

### Lighter-weight — match by `name`

If the user doesn't want to clone, skip the cloning and have the correlation rule filter by rule `name` instead of tag:

```scanner
@index={UUID|"_detections"}
( name:"<OOB Rule A name>" or name:"<OOB Rule B name>" or … )
| stats countdistinct(name) as rule_count by results_table.rows[0].<entity>
| where rule_count >= 2
```

Document in the correlation rule's `description`: *"This rule joins by name, which is fragile to OOB rule renames. If a constituent rule is renamed in the OOB repo, this correlation will silently stop matching it."*

## Sync flow (always use this hand-off)

The Scanner GitHub app watches `main` and syncs on green. Never recommend `scanner-cli sync`. Hand-off:

> 1. Commit the new correlation rule YAML **plus** every constituent rule YAML the skill modified (added the `correlation.<label>` tag, or cloned from OOB).
> 2. Push to `main` (or open a PR and merge).
> 3. For OOB rules: separately disable the originals in the Scanner UI.
> 4. The GitHub app validates and syncs.
> 5. The correlation rule starts in `Staging`. Watch `_detections` for a few days, then flip `enabled: Active` and push.

## Output

Respond to the user with:

1. The **list of files modified or created**, with absolute paths. Clearly separate "new correlation rule" from "constituent rules with new `correlation.<label>` tag" from "cloned-from-OOB" cases.
2. The `scanner-cli validate` result.
3. The **historical hit-rate** from step 6 — one line with expected fire rate.
4. The exact `scanner-cli validate -f <path>` command for re-running.
5. The hand-off flow (numbered above).
6. For any OOB rules in scope: the explicit UI step to disable them.

Keep it tight. The YAMLs are the deliverables; everything else is the verification context.

## Layout

```
write-correlation/
├── SKILL.md                          # this file
└── references/
    ├── methodology.md                # full procedure with self-critique
    ├── correlation_patterns.md       # tag-join template, name-fallback, entity-pivot recipes
    └── detections_index_schema.md    # _detections fields actually populated, with examples
```
