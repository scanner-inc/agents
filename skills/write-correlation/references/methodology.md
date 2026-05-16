# write-correlation — methodology

Read this file when the user invokes `/write-correlation`. It carries the full procedure. The query patterns live in `correlation_patterns.md`; the `_detections` schema in `detections_index_schema.md`.

## Phase 1: Identify constituent rules

The constituents are the existing rules that, when they co-fire, should trigger the correlation. Locate each one:

1. Search every path in `SCANNER_DETECTIONS_DIR` for YAML files matching the user's names.
2. For OOB rules: default to `curl` against the matching `scanner-inc/detection-rules-<source>` pack on GitHub (each pack is its own repo — see `recommend-detections/references/oob_packs.md` for the canonical list). Raw URL pattern: `https://raw.githubusercontent.com/scanner-inc/detection-rules-<source>/main/rules/<file>.yml` (list rules in the pack via the contents API if you don't know the filename). If the user has cloned packs locally and gives you a path, grep that instead.
3. If the user didn't name any rules and instead asked "what correlations would be valuable here?", do candidate-discovery:

```scanner
@index={UUID|"_detections"}
| stats countdistinct(name) as rule_count by results_table.rows[0].userIdentity.arn
| where rule_count >= 2
```

Rank entities with high `rule_count`; for each, pull the actual rule names that fired on that entity in the window. Surface 3–5 cluster candidates back to the user and ask which one to build.

For each constituent rule, classify:
- **User-controlled** — lives in a path under `SCANNER_DETECTIONS_DIR`. We can edit it in place.
- **OOB** — comes from a `scanner-inc/detection-rules-*` pack (sourced via local clone OR `curl` raw GitHub). Read-only; needs fork-and-disable (see SKILL.md).

## Phase 2: Pick the correlation handle

Get the user to choose a **custom label** for the correlation — something like `cloud_credential_theft`, `prod_account_lateral_movement`, `github_supply_chain`. The full tag will be `correlation.<custom_label>`.

For each **user-controlled** constituent rule:
- Open the YAML.
- Add `correlation.<custom_label>` to the `tags:` array (insert it; don't replace).
- Save.

For each **OOB** constituent:
- Default recommendation: **fork-and-disable**. Copy the OOB YAML into one of the user's `SCANNER_DETECTIONS_DIR` paths (suggest a subpath like `rules/<source>/<rule_filename>`), then add the `correlation.<custom_label>` tag. Surface to the user: "*Disable the original `<rule name>` in the Scanner UI once you've pushed your private clone.*"
- Fallback (if user explicitly opts out of cloning): the correlation rule will join by `name` instead of tag. Skip the tag edits for these. Document the fallback in the correlation rule's `description`.

Track everything modified — the hand-off needs to list it all.

## Phase 3: Pick the pivot entity

The pivot is the column from each constituent rule's `results_table` that uniquely identifies the entity to correlate on (a user, an IP, a host).

1. Call `get_top_columns(["_detections"])` to see what `results_table.rows[0].*` columns are populated.
2. For the constituent rules, look at their `query_text` `stats … by …` clauses. The grouping columns become `results_table.rows[0].<col>`.
3. Find the **shared** column. Common pivots:
   - `results_table.rows[0].userIdentity.arn` (AWS)
   - `results_table.rows[0].sourceIPAddress` (AWS network)
   - `results_table.rows[0].@ecs.user.name` (normalised)
   - `results_table.rows[0].@ecs.source.ip` (normalised network)
   - `results_table.rows[0].actor.id` (Okta/SaaS)
4. If the constituents don't share a column, you may need to ask the user to add a normalised field (via VRL — route to `/write-vrl`), or pivot on a less precise field.

## Phase 4: Pick the window

- `time_range_s` (the correlation rule's lookback). Default 600 (10 min). Reasonable range: 300–3600.
- `run_frequency_s`. Default 60. Must be `<= time_range_s` and multiple of 60.

Bias short. A 10-minute correlation window is enough to catch "fire-and-pivot" attack chains and keeps false-positive rates low. Hour-long windows start to look like coincidence.

## Phase 5: Draft the correlation YAML

See `correlation_patterns.md` for the templated form. Defaults:

- `enabled: Staging` (always Staging on first push).
- `severity:` — **one level above** the loudest constituent. If the loudest is High, this is Critical. Justification: a correlation is by construction more selective than its constituents, so its findings should warrant more attention.
- `event_sink_keys:` — per `severity_policy.md` of `write-detection`: Medium+ gets sinks, Low/Info doesn't.
- `tags:` — union of all constituents' tags, plus `correlation.<custom_label>`, plus an appropriate MITRE technique like `techniques.t1078.valid_accounts` if applicable.
- `query_text` — use the tag-join template (or name-join fallback) from `correlation_patterns.md`.

Resolve the `_detections` UUID (the cleanest way — works for any index alias):

```scanner
@index=_detections | head 1 | table(@index, @index_id)
```

The `@index_id` field on every event is the index UUID. This is fast (a single-row query) and works for any alias. Use it for the rule's `@index={UUID|"alias"}` form. (Note: `get_scanner_context.available_indexes` does NOT surface UUIDs as of 2026-05 — use this MCP query instead.)

Write the YAML to a path inside `SCANNER_DETECTIONS_DIR`. Suggested location: `rules/correlations/<correlation_label_snake_case>.yml`.

## Phase 6: Sanity-check via MCP

Run the *exact* correlation query (filter + stats + where) over the last 14–30 days. Look at:

- Total firings — the headline number. If it's >1/day, that's probably too noisy for a Critical/High correlation. Suggest raising `rule_count >= N` threshold, or trimming the constituent set.
- Top 5 entities by `rule_count` — these are the historical "would-have-fired" candidates. Show them to the user as a sanity check: do they look like real incidents or noise?
- If zero firings over 30 days → the correlation is hypothetical. Tell the user, and ask whether to ship it as a future trip-wire or revisit the constituents.

## Phase 7: Validate

```bash
scanner-cli validate -f <correlation-rule-path>
```

Common failures:
- Missing `@index={UUID|"_detections"}` form — bare `@index=_detections` parse-errors.
- Tag string violates the character set (`correlation.<label>` should be `[a-zA-Z0-9._-]+`, starting with a letter).
- Severity isn't one of the eight OCSF strings.

## Phase 8: Hand off

The hand-off list **must** include every file the skill touched:

- The new correlation rule YAML.
- Each user-controlled constituent rule whose `tags:` block now has the new `correlation.<custom_label>` entry.
- Each OOB-cloned constituent (the private-repo clone, not the original).

Plus the **UI step for OOB rules**: tell the user explicitly to disable the originals in the Scanner UI. The GitHub app can't do that for them.

Render the GitHub-app sync flow with the numbered steps from `SKILL.md`.

## Self-critique before emitting

- Did I use `tags[*]:` (single bracket-level), not `tags[**]:`?
- Did I use `countdistinct(name)`, not `countdistinct(detection_rule_id)`?
- Did the `where rule_count >= N` threshold make it to the YAML? Without it, the rule fires whenever *any one* constituent fires — useless.
- Is the pivot column populated in `_detections` for *all* constituent rules? (If one rule doesn't surface that field in its `results_table`, the correlation will miss it.)
- Did I list every modified file in the hand-off?
- For OOB rules: did I include the disable-in-UI instruction?
- `enabled: Staging`?

Fix anything the critique surfaces, re-validate, re-emit.
