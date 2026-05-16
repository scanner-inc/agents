# Panther → Scanner: AWS root console login

**Source:** [`source.py`](./source.py) + [`source.yml`](./source.yml) — Panther rule `AWS.CloudTrail.RootConsoleLogin` from `~/src/panther-analysis/rules/aws_cloudtrail_rules/`.

**Target:** [`scanner_rule.yml`](./scanner_rule.yml) — modelled after Scanner's `aws_root_account_usage.yml` but narrowed to the specific successful-console-login behaviour Panther's rule catches.

## What changed in translation

| Panther | Scanner |
|---|---|
| `def rule(event): event.get("eventName") != "ConsoleLogin": return False` (short-circuit) | `eventName="ConsoleLogin"` |
| `deep_get(event, "userIdentity", "type") != "Root": return False` | `userIdentity.type="Root"` |
| `deep_get(event, "responseElements", "ConsoleLogin") == "Success"` | `responseElements.ConsoleLogin="Success"` |
| YAML `Severity: High` | `severity: High` + `event_sink_keys: [high_severity_alerts]` |
| YAML `LogTypes: [AWS.CloudTrail]` | `@scnr.source_type="aws:cloudtrail"` |
| YAML `Reports.MITRE ATT&CK: [TA0001:T1078, TA0003:T1078]` | `tags: [tactics.ta0001.initial_access, tactics.ta0003.persistence, techniques.t1078.valid_accounts]` |
| `def alert_context(event): return aws_rule_context(event)` | `alert_template.info` with `sourceIPAddress`, `recipientAccountId`, `awsRegion` |
| YAML `Tests` block (Python dicts) | `tests` array with `dataset_inline` JSONL — added a `timestamp` to each event (Panther test events don't always include one; Scanner requires it). |

## Key idioms to learn from this example

- **Python guards → AND'd filter predicates.** Each `if event.get(...) != X: return False` becomes one `field=X` predicate in the Scanner filter. Order doesn't matter (Scanner AND's all top-level predicates).
- **`deep_get(event, "a", "b", "c")` → `a.b.c`.** Panther's `deep_get` is null-safe nested-field access; Scanner's dotted field paths return null on missing path automatically.
- **Pivot choice.** The Panther rule has no aggregation — every matching event is its own alert. The Scanner version adds `| stats … by sourceIPAddress, awsRegion, recipientAccountId`. Pivoting on `sourceIPAddress` (not `userIdentity.arn`) is a deliberate choice: root logins all have the same ARN-like identifier per account, so the IP and account are the more informative grouping keys.
- **`alert_context` → `alert_template`.** Panther's `alert_context(event)` returns a context dict that Panther's UI surfaces on the alert. Scanner does the same thing with the YAML `alert_template.info[]` array.
- **Test fixtures need timestamps.** Panther's tests omit `timestamp`; the migration adds canonical ones.

## When a Panther rule is too complex for 1:1 translation

This rule was simple — three guards, one boolean return. For more complex Panther rules (state, regex, helper-call chains), see `translation_panther.md`'s "When the Python is too complex" section. Options:

1. Skip and flag the rule as un-migratable.
2. Migrate a simplified approximation (catches 80% of the behaviour) and note the trade-off.
3. Decompose into multiple Scanner rules + a correlation via `/write-correlation`.

## What this corpus entry doesn't cover

- `panther_base_helpers` and other shared utilities. When migrating other Panther rules, open `~/src/panther-analysis/global_helpers/` and inline the helper's logic into the Scanner filter.
- Panther's data-model layer (`~/src/panther-analysis/data_models/`). For some sources, Panther normalises raw fields into a "data model" the rule accesses via `event.udm("dest_ip")`. Scanner doesn't have a query-time normalisation layer; either consume the raw field, or hand off to `/write-vrl` to add the same field at ingest.
