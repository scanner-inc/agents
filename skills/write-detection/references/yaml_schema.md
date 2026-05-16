# Scanner detection rule YAML schema

Source of truth: <https://scanner.dev/schema/scanner-detection-rule.v1.json>. This file is a working cheat-sheet condensed from `~/src/gitbook-docs/.../detection-rules-as-code/writing-detection-rules.md`.

## File requirements

- One detection rule per YAML file.
- Extension `.yml` or `.yaml` — anything else is ignored by the GitHub-app sync.
- **First line must be exactly:**
  ```
  # schema: https://scanner.dev/schema/scanner-detection-rule.v1.json
  ```
  Files missing this header are silently skipped at sync time.

## Top-level fields

| Field | Required | Notes |
|---|---|---|
| `name` | yes | Short, action-oriented, human-readable. Used as the join key for correlation rules — try to keep it stable. |
| `description` | yes | `|-` multi-line block. Include what it detects, references (CVE / blog / report URLs), and known false-positive scenarios. |
| `enabled` | yes | One of `Active`, `Staging`, `Paused`. New rules → `Staging`. Legacy `true` / `false` is accepted but ambiguous; don't write it. |
| `severity` | yes | One of `Informational`, `Low`, `Medium`, `High`, `Critical`, `Fatal`, `Other`, `Unknown`. See `severity_policy.md` for which one to pick. |
| `query_text` | yes | `|-` multi-line block. Scanner query syntax. See `query_language.md`. |
| `time_range_s` | yes | Lookback window in seconds. **Must be minute granularity** (multiple of 60). Default 300. |
| `run_frequency_s` | yes | Evaluation frequency in seconds. Multiple of 60. Must be `<= time_range_s`. Default 60. |
| `tags` | recommended | Array of canonical tag strings. At least one MITRE tactic + one technique + `source.<slug>` is the baseline. See `mitre_tags.md`. |
| `event_sink_keys` | conditional | Required for Medium / High / Critical / Fatal severities (sends alerts to the matching sink). **Omit** for Low / Informational — those become signals consumed by correlation rules. |
| `dedup_window_s` | optional | Suppress repeat alerts within this window if their dedup-key hash matches. Useful for tuning noise. |
| `alert_per_row` | optional | If `true`, emit one detection event per result-table row instead of one per query batch. Default `false`. |
| `alert_template` | optional | Custom alert formatting — `info` (labelled key/value pairs) and `actions` (button links, usually runbooks). |
| `tests` | recommended | Array of inline unit tests. See "Tests" below. Sync is **all-or-nothing**: a failing test in any rule blocks the whole repo from syncing. |

## Source filtering — prefer `@scnr.source_type` / `%ingest.source_type` over `@index=`

By **default, a detection rule queries every index the user has read access to** and returns matches from any of them. So you usually want to filter by **source-type**, not by **index**.

In preference order:

1. **`@scnr.source_type="<value>"`** — set automatically by Scanner for log sources with built-in Collect rules (e.g., `aws:cloudtrail`, `okta`, `1password`, `auth0:audit`, `github:audit`, `aws:vpc_flow`). Always your first choice for natively-supported sources.
2. **`%ingest.source_type="<value>"`** — set when the user added it by hand via a custom transformation or index rule. Value is whatever they wrote.
3. **A data-derived identifier field** — when the source isn't natively supported, `@scnr.source_type` becomes `"custom:generic"` (useless for filtering). In this case, sample real events (`get_top_columns`, `| head 3`) to find a field that uniquely identifies this source — commonly `vendor`, `product`, `provider`, `log_type`, or some bespoke field the customer added.

## When `@index=` IS the right choice

Reach for `@index=` only when the source-type filter isn't enough. Three good reasons:

1. **Prod vs staging split.** Customer has `prod-cloudtrail` and `staging-cloudtrail` indexes of the same source. The rule should only fire on prod. Use `@index={UUID|"prod-cloudtrail"}`.
2. **One-source-per-index layout** (the Scanner-recommended pattern). When each log source already has its own index, `@index={UUID|"okta_logs"}` and `@scnr.source_type="okta:audit"` are roughly equivalent — pick whichever is more idiomatic in the customer's other rules.
3. **Correlation rules against `_detections`.** Correlation rules intrinsically target `_detections`; include `@index={UUID|"_detections"}` so they don't accidentally match `tags[*]:` shapes in other indexes. See `write-correlation`.

## If you do use `@index=` — full form is required

When you include an index specifier in a detection-rule query, it MUST use the full form:

```yaml
query_text: |
  @index={ 00000000-0000-0000-0000-000000000000 | "cloudtrail_logs" }
  …
```

These parse-error at sync time:

```yaml
query_text: |
  @index=cloudtrail_logs            # ❌ alias-only
  @index=00000000-0000-…             # ❌ uuid-only
```

Reason: aliases can be renamed; UUIDs are stable. The full form survives an alias rename.

**Resolving an alias to its UUID** (works for any index, including built-ins like `_detections`):

```scanner
@index=<alias> | head 1 | table(@index, @index_id)
```

The `@index_id` field is the index UUID. (`get_scanner_context.available_indexes` does NOT surface UUIDs as of 2026-05.)

For ad-hoc MCP queries (not detection rules), the alias alone is fine: `@index=cloudtrail_logs | head 3`.

## Severity values (8 total, OCSF Severity IDs)

| Severity | OCSF id | When to use | event_sink_keys |
|---|---|---|---|
| `Unknown` | 0 | Avoid. |  |
| `Informational` | 1 | Signal-only. Consumed by correlation rules. | (none) |
| `Low` | 2 | Signal-only. Consumed by correlation rules. | (none) |
| `Medium` | 3 | First severity that pages. | `medium_severity_alerts` |
| `High` | 4 | Pages. | `high_severity_alerts` |
| `Critical` | 5 | Pages with urgency. | `critical_severity_alerts` |
| `Fatal` | 6 | Pages, severity-of-last-resort. | `fatal_severity_alerts` |
| `Other` | 99 | Avoid. |  |

See `severity_policy.md` for the picking heuristic.

## Tags

- Each tag must begin with an ASCII letter; allowed chars are `[a-zA-Z0-9._-]`.
- Use the canonical Scanner MITRE tags from `mitre_tags.md` — never display names.
- Always include `source.<slug>` (e.g., `source.cloudtrail`) so coverage matrices can attribute the rule to a log source.
- For correlation participants: add `correlation.<custom_label>` (the `write-correlation` skill writes this for you).

## Tests

```yaml
tests:
  - name: <descriptive name>
    now_timestamp: "2026-05-15T00:03:00.000Z"   # optional; defaults to latest event timestamp
    dataset_inline: |
      {"timestamp":"...","field":"value"}
      {"timestamp":"...","field":"value"}
    expected_detection_result: true              # or false
```

- `dataset_inline` is **newline-delimited JSON**, one event per line. No outer array.
- Every event needs a `timestamp` in RFC-3339 (`2026-05-15T00:02:30.000Z`).
- The test window is `[now_timestamp - time_range_s, now_timestamp)` — inclusive lower bound, exclusive upper. Events with timestamp `>= now_timestamp` are NOT counted.
- `now_timestamp` is rounded up to the next `run_frequency_s` minute boundary.

Seed positive tests from real events; sanitise account IDs / ARNs / IPs. Always include at least one negative test that exercises a near-miss (similar event, different field, shouldn't fire).

## Alert template (optional)

```yaml
alert_template:
  info:
    - label: User
      value: "{{@alert.results_table.rows[0].userIdentity.arn}}"
      use_for_dedup: true
    - label: Region
      value: "{{@alert.results_table.rows[0].awsRegion}}"
  actions:
    - label: View Runbook
      value: "https://runbooks.example.com/<rule-slug>"
```

`use_for_dedup: true` adds the field to the dedup-key hash (combined with `dedup_window_s`).

`actions` render as buttons in Slack and links in Markdown. Values should be URLs; invalid URLs render as plain text.

## Sync is all-or-nothing

**Important:** When the Scanner GitHub app syncs the repo, if **any** rule is invalid or has a failing test, the **entire sync is aborted**. This is by design — rules can depend on each other (one writes to `_detections`, another reads from it), so a broken rule can break the whole detection graph. Always validate locally before pushing.

## Repository layout convention

```
my-detections/
├── .github/
│   └── workflows/
│       └── validate-detection-rules.yml   # Scanner's official GitHub Action
├── rules/
│   ├── aws/
│   │   └── cloudtrail/
│   │       ├── securityhub_findings_evasion.yml
│   │       └── …
│   ├── okta/
│   │   └── …
│   └── …
└── README.md
```

When writing a new rule, place it under `rules/<source>/<subdir>/<descriptive_snake_case>.yml`.
