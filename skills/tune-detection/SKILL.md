---
name: tune-detection
description: Investigate a noisy Scanner detection rule against real `_detections` data, classify recent firings as false-positive vs true-positive vs unknown, and produce a concrete tuning patch — extra filter clauses, post-aggregation thresholds, dedup windows, or severity downgrades — along with regression tests seeded from the FP events. Validates the tuned rule with `scanner-cli validate` + `run-tests` and backtests the new firing rate. For out-of-the-box rules (which can't be edited in place), recommends the fork-and-disable workflow: clone the OOB YAML into the user's private repo, tune it there, and disable the original in the Scanner UI. Use when the user types `/tune-detection <rule-id-or-name>`, says "this rule is noisy", "reduce false positives on…", or "tune <name>". Requires Scanner MCP, `SCANNER_API_URL` + `SCANNER_API_KEY` for `scanner-cli`, and `SCANNER_DETECTIONS_DIR` (comma-separated paths to local rule repos).
---

# tune-detection

## When to invoke

Trigger on any of:
- The user types `/tune-detection <rule-id-or-name>`.
- The user says "this rule is noisy", "reduce false positives on…", "tune `<name>`".
- The user shows a flood of recent detections from a single rule and asks for help.

If the user wants to write a brand-new rule, route to `/write-detection`.
If they want a correlation rule, route to `/write-correlation`.

## Required environment

- **Scanner MCP** configured.
- `SCANNER_API_URL`, `SCANNER_API_KEY` — for `scanner-cli`.
- `SCANNER_DETECTIONS_DIR` (recommended) — comma-separated absolute paths to the user's local rule repos. Falls back to asking per-invocation.
- `scanner-cli` on PATH.

## Workflow

Follow the full procedure in `references/methodology.md`. The short version:

1. **Locate the rule YAML.** Search in order: every path in `SCANNER_DETECTIONS_DIR` → OOB packs (default: `curl` the matching `scanner-inc/detection-rules-<source>` pack on GitHub — see `recommend-detections/references/oob_packs.md` for the canonical list of packs and their GitHub URLs; OR, if the user has cloned individual packs locally and gives you a path, read from there) → the Scanner Detection Rule API (via `scripts/fetch_detection_rule.sh --name "<name>"` or `--id <uuid>`). The API path covers rules created in the Scanner UI that aren't in any local repo. See `references/methodology.md` Phase 1 for the four resolution branches: **user repo → OOB → UI-created → git-synced from missing repo**. OOB rules use fork-and-disable; UI-created rules use the UI-tune workflow.

2. **Pull recent firings.** Query `_detections` for the last 14d (extend to 30d if sparse). Group by the rule's natural pivot keys (the `stats … by …` columns in its `query_text`). Show the top 10 distinct values + counts.

3. **Sample underlying events.** For the noisiest groups, pivot back from `_detections` to the source index using `detected_in_time_range` + the rule's pivot keys. Pull 3–5 raw events per loud group via Scanner MCP.

4. **Classify FP/TP/UNKNOWN.** Render a small markdown table: group key → verdict → 1-line reason. Be concrete — "this fires because the user agent contains `CloudShell`, which is normal"; not "this looks fine".

5. **Propose targeted tuning.** Pick the *smallest* change that removes the FPs without losing TP coverage:
   - **First choice:** extra filter clause that narrowly excludes the FP signature. (`and not userAgent: "CloudShell"`, `and not requestParameters.maxResults > 1000`.)
   - **Second choice:** post-aggregation threshold via `| where @q.count > N`.
   - **Third choice:** `dedup_window_s` to suppress repeats from the same dedup key.
   - **Last resort:** severity downgrade (Medium → Low; the rule becomes a signal for correlation rather than an alert).
   Avoid blanket exclude-lists when a narrower filter works.

6. **Add regression tests.** Append at least one new negative test to the rule's `tests:` array, seeded with a sanitised FP event from step 3. Update existing positive tests if the tuning changed expected behaviour.

7. **Validate.** Run `scanner-cli validate -f <path>` and `scanner-cli run-tests -f <path>`. Surface failures verbatim and iterate.

8. **Backtest the tuned query.** Re-run the *full tuned query* (filter + aggregations + threshold) via Scanner MCP over the same window as step 2. Report old vs new fire rate. Optionally also confirm the **TP groups still fire** — if any disappear, the tuning is too aggressive.

9. **Hand off** via the GitHub-app sync flow — see "Sync flow" below.

## OOB rules — fork and disable

If the rule comes from a `scanner-inc/detection-rules-*` pack (each pack is its own GitHub repo — see `recommend-detections/references/oob_packs.md`), it's **read-only**. The user cannot edit it in place. Switch to the fork-and-disable workflow:

1. **Obtain the OOB YAML.** Default: `curl -sSL "https://raw.githubusercontent.com/scanner-inc/detection-rules-<source>/main/rules/<file>.yml"`. (Or, if the user has cloned the pack locally and points you at a path, read it from there.) **Copy** the YAML into one of the paths in `SCANNER_DETECTIONS_DIR`. Suggested path: `rules/<source>/<orig_filename>`.
2. Tell the user explicitly: *"I'm tuning a clone at `<path>`. After you push, you'll need to **disable the original OOB rule in the Scanner UI** (Settings → Detection Rules → search for `<name>` → toggle off). The UI is the only place the OOB toggle exists."*
3. Continue tuning the clone in all subsequent steps.

The cloned-and-tuned rule overrides the (disabled) OOB rule once the GitHub app syncs.

## Sync flow (always use this hand-off)

The Scanner GitHub app watches `main` and syncs on green. Never recommend `scanner-cli sync`. Hand-off:

> 1. Commit the modified YAML (or the cloned-and-tuned YAML for OOB rules).
> 2. Push to `main` (or open a PR and merge).
> 3. For OOB-cloned rules: separately disable the original in the Scanner UI.
> 4. The GitHub app validates and syncs.

If the rule wasn't already in `Staging`, **do not** auto-flip it to `Staging` during tuning — that's a deliberate severity-level change and the user should decide. Just tune and re-deploy at the existing `enabled:` level.

## Output

Respond to the user with, in order:

1. **The FP/TP classification table** from step 4.
2. **The YAML diff** — show only the changed lines (or sections of `query_text`), not the whole file.
3. **The validation result.** `scanner-cli` prints `<path>: OK` from `validate` and `<test name>: OK` from `run-tests` — relay those literally, not paraphrased.
4. **The before/after backtest** — one line: `Backtest: <window>, was <N>/day → now <M>/day (-X%)`.
5. **TP coverage check** — explicit confirmation that the previously-TP groups still fire under the new query.
6. **Hand-off** — the GitHub-app sync flow steps. For OOB-cloned rules, the explicit UI disable step.

Keep it tight. The diff is the deliverable.

## Layout

```
tune-detection/
├── SKILL.md                          # this file
├── references/
│   └── methodology.md                # full procedure, FP/TP rubric, tuning toolbox, UI-tune workflow
└── scripts/
    ├── list_detection_rules.sh       # page through GET /v1/detection_rule
    └── fetch_detection_rule.sh       # find one rule by --name or --id, emit JSON
```

## Pre-flight briefing

Before the first tool call, emit 2-3 lines telling the user what's about to happen. Include the destination path if the rule is going to be modified. Example:

> Tuning `<rule name>`. I'll locate the YAML (local repo / OOB pack / Scanner UI), pull recent firings from `_detections`, sample underlying events, classify FP/TP, propose the smallest filter or threshold change that removes the FPs, add a regression test, validate, and backtest the new fire-rate. Writes to: `<path>`. ~30-90s.

If the rule turns out to be an OOB rule, mention the fork-and-disable workflow up front so the user knows the destination changes from "edit in place" to "clone into your private repo + disable in UI".
