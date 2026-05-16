# Correlation rule patterns

This file documents the YAML templates and query patterns for Scanner correlation rules. All patterns were verified against real `_detections` data during planning.

## Why correlation rules always include `@index={UUID|"_detections"}`

For most Scanner detection rules, `@index=` is **optional** and we prefer source-type filtering (`@scnr.source_type=`). Correlation rules are the exception.

The reason: correlation rules join detection-firing events using fields like `tags[*]:correlation.<label>` and `results_table.rows[0].<entity>`. Those fields are specific to `_detections` events, but field-existence checks aren't precise — `tags[0]` could appear on rules that emit it as part of their result table, on `_audit` events that carry tags, etc. Without `@index=_detections`, a correlation query could accidentally pull in non-detection events and either miss real co-firings or fire spuriously.

Always scope correlation rules with `@index={UUID|"_detections"}`. Resolve the UUID via `@index=_detections | head 1 | table(@index, @index_id)` — the `@index_id` field on any event is the UUID.

## Pattern A: tag-join (preferred)

**Use when** every constituent rule is under the user's control (in a path in `SCANNER_DETECTIONS_DIR`, or cloned-from-OOB into one).

### Constituent edit

Add `correlation.<custom_label>` to each constituent's `tags:` block:

```yaml
# rules/aws/iam_user_created_high_priv.yml
tags:
  - source.cloudtrail
  - tactics.ta0004.privilege_escalation
  - techniques.t1078.valid_accounts
  - correlation.cloud_credential_theft       # ← added
```

### Correlation rule

```yaml
# schema: https://scanner.dev/schema/scanner-detection-rule.v1.json
name: Correlated cloud credential theft activity
enabled: Staging
description: |-
  Fires when two or more rules tagged `correlation.cloud_credential_theft`
  trip on the same `userIdentity.arn` within a 10-minute window.

  Constituent rules (all tagged `correlation.cloud_credential_theft`):
  - AWS IAM User Created with High-Privilege Policy Attached
  - AWS Console Login from Anomalous Country
  - AWS Access Key Created Outside Normal Hours
severity: Critical
query_text: |-
  @index={ 00000000-0000-0000-0000-000000000000 | "_detections" }
  tags[*]:correlation.cloud_credential_theft
  | stats countdistinct(name) as rule_count by results_table.rows[0].userIdentity.arn
  | where rule_count >= 2
time_range_s: 600
run_frequency_s: 60
event_sink_keys:
  - critical_severity_alerts
tags:
  - source.cloudtrail
  - tactics.ta0006.credential_access
  - techniques.t1078.valid_accounts
  - correlation.cloud_credential_theft
alert_template:
  info:
    - label: User
      value: "{{results_table.rows[0].userIdentity.arn}}"
      use_for_dedup: true
    - label: Distinct rules tripped
      value: "{{results_table.rows[0].rule_count}}"
```

Replace `00000000-…` with the real `_detections` UUID from `get_scanner_context().available_indexes`.

## Pattern B: name-join (OOB fallback)

**Use when** one or more constituents are OOB rules the user opted *not* to fork. Less robust to rule renames, but works without YAML edits to the OOB rule.

```yaml
query_text: |-
  @index={ 00000000-0000-0000-0000-000000000000 | "_detections" }
  ( name:"AWS GuardDuty disabled" or name:"AWS CloudTrail Disable Logging" or name:"AWS S3 Bucket Made Public" )
  | stats countdistinct(name) as rule_count by results_table.rows[0].userIdentity.arn
  | where rule_count >= 2
```

Document in the rule's `description`:

```yaml
description: |-
  Fires when 2+ of these OOB rules co-fire on the same userIdentity.arn:
  - AWS GuardDuty disabled
  - AWS CloudTrail Disable Logging
  - AWS S3 Bucket Made Public

  This rule joins by name (not tag) because the constituents are OOB rules
  that can't be edited in place. If Scanner renames any constituent in the
  OOB pack, this correlation will silently stop matching it. Re-check
  annually or switch to fork-and-disable if you need correlation tagging.
```

## Pattern C: tag-join with multi-entity pivot

Some correlations need to fire when *any* shared entity hits the rule_count threshold — useful when the constituent rules use different grouping keys for the same logical entity (one is `userIdentity.arn`, another is `userIdentity.userName`).

```yaml
query_text: |-
  @index={ 00000000-0000-0000-0000-000000000000 | "_detections" }
  tags[*]:correlation.<label>
  | eval entity = coalesce(
      results_table.rows[0].userIdentity.arn,
      results_table.rows[0].userIdentity.userName,
      results_table.rows[0].@ecs.user.name
    )
  | stats countdistinct(name) as rule_count by entity
  | where rule_count >= 2
```

The `coalesce` picks the first non-null among candidates. This is more permissive — it'll occasionally cross-attribute rule firings that *look* like the same entity but are technically different — so use it only when you can't make the constituents share a single column.

## Pattern D: signal-aggregation (using Low/Informational rules)

For rules that fire **per-event** at Low/Informational severity (`alert_per_row: true`), the correlation can count *event volume* rather than distinct rule names:

```yaml
query_text: |-
  @index={ 00000000-0000-0000-0000-000000000000 | "_detections" }
  tags[*]:correlation.bulk_data_access
  severity=("Low" "Informational")
  | stats count() as signal_count by results_table.rows[0].userIdentity.arn
  | where signal_count >= 50
```

This is the "promote a heap of signals into one alert" use case. The Low/Info constituents don't page anyone on their own; the correlation rule (Medium+) does.

## Severity-bump heuristic

The correlation rule's severity defaults to **one level above the loudest constituent**:

| Loudest constituent | Correlation severity |
|---|---|
| Informational, Low | Medium (now alerts) |
| Medium | High |
| High | Critical |
| Critical | Fatal (use sparingly) |

Override only with a written justification in `description`. "Multiple lower-severity rules co-firing on the same entity is, by construction, a higher-confidence signal than any single one." — this is the whole point.

## Dedup

For correlations on noisy entities, set `dedup_window_s` to suppress repeat fires for the same dedup key:

```yaml
dedup_window_s: 3600         # 1 hour
alert_template:
  info:
    - label: User
      value: "{{results_table.rows[0].userIdentity.arn}}"
      use_for_dedup: true     # this field contributes to the dedup hash
```

Without dedup, a sustained attack on one user can spam the same alert every `run_frequency_s` seconds.

## Future: `alert_per_row`

Scanner is rolling out per-row detection events (`alert_per_row: true`). When that's available on a constituent, its `_detections` events surface a single row each — making `results_table.rows[0].<entity>` always populated and unambiguous. Assume this is the direction; pattern A keeps working without changes.

## What NOT to do

- ❌ `tags[**]:` — that's for deep multi-level paths; overkill and slower than needed.
- ❌ `detection_rule_id:` — opaque, not in YAML, breaks under rule cloning. Use `name` or `tags`.
- ❌ Correlation rule with no `where rule_count >= N` clause — it'll fire whenever any one constituent fires.
- ❌ Pivoting on `tags[0]` — the rule's first-position tag can be anything; pivot on `results_table.rows[0].<entity>` instead.
- ❌ `severity: Informational` for a correlation — defeats the point. Correlations exist to promote multiple low-severity signals into one actionable alert.
