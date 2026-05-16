---
name: write-detection
description: Author a new Scanner detection rule (YAML) from a natural-language description of the behaviour you want to catch. Discovers the relevant log-source schema via Scanner MCP, samples real production data to sanity-check the filter, drafts the rule with the proper YAML schema header, writes 2-4 inline unit tests seeded from real events, validates with `scanner-cli validate` + `run-tests`, backtests the full query against historical logs (needle-in-haystack regime can scan months of data), and hands off via the Scanner GitHub-app sync flow. Always writes rules in `Staging` state for first push. Use when the user types `/write-detection`, asks Claude to "write a detection rule for X", "create a Scanner rule that fires when…", or pastes an attacker behaviour and wants to detect it. Requires Scanner MCP configured, `SCANNER_API_URL` + `SCANNER_API_KEY` for `scanner-cli`, and optionally `SCANNER_DETECTIONS_DIR` (comma-separated paths to local rules repos).
---

# write-detection

## When to invoke

Trigger on any of:
- The user types `/write-detection` with or without context.
- The user asks Claude to write, author, or create a Scanner detection rule.
- The user describes attacker behaviour and wants it caught — "alert me when X happens".
- The user pastes a partial query and asks to turn it into a real rule.

If the user is migrating an existing rule from another SIEM, route them to `/migrate-detection` instead.

If the user is trying to *reduce* false positives on a rule that already exists, route them to `/tune-detection`.

If the user wants to correlate across multiple existing rules, route them to `/write-correlation`.

## Required environment

- **Scanner MCP** configured in Claude Code (the `scanner_internal_env` server).
- `SCANNER_API_URL` and `SCANNER_API_KEY` — used by `scanner-cli validate` and `scanner-cli run-tests` for offline validation. If missing, surface the error verbatim and stop.
- `SCANNER_DETECTIONS_DIR` (optional, recommended) — comma-separated absolute paths to the user's local detection-rule repos. If unset, ask the user once per invocation where to write the YAML.
- `scanner-cli` on PATH. Install via `pip install scanner-cli` (or via Poetry from the source repo at <https://github.com/scanner-inc/scanner-cli>). If the user has a local clone at `~/src/scanner-cli/`, Poetry-install from there.

## Workflow

Follow the full procedure in `references/methodology.md`. The short version:

1. **Restate the hypothesis.** One paragraph: what behaviour, in which source, with which fields. If the prompt is vague, ask **one** clarifying question; don't draft from imagination.
2. **Discover schema.** Scanner MCP `get_scanner_context`, then `get_top_columns` on the candidate index. Use the real field names — don't invent paths.
3. **Filter-clause sanity check.** Run the *first filter clause alone* via MCP. Pick the backtest window using the regime split in `references/backtesting.md`:
   - **Needle-in-haystack** (filter likely rare): 30–90d, sometimes longer — Scanner is fast on rare-event filters even at petabyte scale, and showing the user a long-range backtest is a feature.
   - **Broad** (filter hits more than a few hundred events / day): cap at 7d and warn the user that longer backtests get expensive.
   Zero hits → stop, the filter is wrong or the source isn't ingested.
4. **Draft the YAML.** Schema rules in `references/yaml_schema.md`. Always start with `# schema: https://scanner.dev/schema/scanner-detection-rule.v1.json` and `enabled: Staging` (promotion to `Active` is a human step). Severity per `references/severity_policy.md` (Medium+ → relevant `event_sink_keys`; Low/Information → no event sinks, treated as signals for correlation).
5. **Inline tests.** 2–4 tests in `dataset_inline:` JSONL form. Seed positive cases from the real sample events you pulled in step 3 (sanitised). At least one negative case.
6. **Validate offline.** Write the YAML into one of the paths in `SCANNER_DETECTIONS_DIR` (or the path the user gave). Run:
   ```bash
   scanner-cli validate -f <path>
   scanner-cli run-tests -f <path>
   ```
   Surface failures verbatim; iterate.
7. **Historical backtest.** Run the *full query* (with aggregations) via Scanner MCP over the regime-appropriate window. Report expected daily firing rate. If a Medium+ rule fires more than ~10/day, propose tuning options (extra filters, threshold with `| where @q.count > N`, `dedup_window_s`, or severity downgrade to make it a signal instead).
8. **Hand off.** Show the file path, the `scanner-cli` commands the user can re-run, and the **GitHub-app sync flow** — see "Sync flow" below. Never recommend `scanner-cli sync`.

## Sync flow (always use this hand-off)

The Scanner GitHub app watches the user's `main` branch, runs validation + unit tests server-side, and syncs only on green. The skill never pushes rules to Scanner directly. The hand-off is always:

> 1. Commit the new YAML to your detection-rules repo.
> 2. Push to `main` (or open a PR and merge).
> 3. The Scanner GitHub app validates and syncs.
> 4. The rule starts in `Staging` — watch `_detections` for a few days, then flip `enabled: Active` in the YAML and push again.

Do **not** mention `scanner-cli sync`. That's a legacy path for users without GitHub; everyone using these skills has the GitHub app.

## Lookup-table dependency

If the rule needs query-time enrichment Scanner can't do natively — CIDR membership, "is this user in the HR group", "is this account ID one of ours" — Scanner enriches at **ingest** time, not query time. Tell the user:

> This rule needs an enriched field (`<field-name>`) that doesn't exist yet. First invoke `/write-vrl` with your lookup table to add an ingest-time transformation that produces `<field-name>`. Once that VRL is installed in the Scanner UI, come back to `/write-detection` and we'll consume the enriched field.

Document the dependency in the rule's `description` so reviewers see it.

## Severity-and-staging defaults (always)

- New rules are written with `enabled: Staging`.
- Severity is chosen using the policy in `references/severity_policy.md`:
  - **Medium / High / Critical / Fatal** → `event_sink_keys` set to the matching `<severity>_severity_alerts` key. These fire alerts.
  - **Low / Informational** → **no `event_sink_keys`**. These are *signals* — consumed by correlation rules, not surfaced as alerts.
- The user can always override either choice; document the override in the rule's `description`.

## Output

Respond to the user with:

1. The path the YAML was written to.
2. The validation result. `scanner-cli` prints `<path>: OK` from `validate` and `<test name>: OK` from `run-tests` — relay those literally (don't paraphrase as "Valid" or "Passed").
3. The backtest result — one line: `Backtest: <regime>, <window>, expected ~<N> fires/day in production`.
4. The exact `scanner-cli validate -f <path>` and `scanner-cli run-tests -f <path>` commands the user can re-run themselves.
5. The GitHub-app sync flow (4 numbered steps above).
6. Any tuning suggestions if the backtest fired too often.

Keep the response tight. The YAML file itself is the deliverable; everything else is context the user needs to verify it.

## Layout

```
write-detection/
├── SKILL.md                          # this file
└── references/
    ├── methodology.md                # full 8-phase procedure
    ├── yaml_schema.md                # top-level fields, schema header, index specifier rules
    ├── query_language.md             # Scanner query syntax cheat-sheet for rule queries
    ├── severity_policy.md            # severity → event_sink_keys mapping, signal vs alert
    ├── backtesting.md                # needle-in-haystack vs broad-filter regime guidance
    └── mitre_tags.md                 # canonical Scanner-supported MITRE tags
```
