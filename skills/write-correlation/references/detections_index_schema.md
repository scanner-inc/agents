# `_detections` index schema

The `_detections` index holds one event per detection-rule firing. Correlation rules query this index.

Schema below is **empirical** — discovered via `get_top_columns(["_detections"])` during planning. Field availability varies per detection-rule output, so always sample real events before pivoting on a non-core field.

## Always-present core fields

| Field | Type | Notes |
|---|---|---|
| `id` | string | UUID of this specific firing event. |
| `name` | string | The constituent rule's `name:` from its YAML. **The correct join key for correlations.** |
| `description` | string | The constituent rule's `description:`. |
| `severity` | string | One of the eight OCSF severities (`Informational`, `Low`, `Medium`, …). |
| `severity_id` | int | OCSF severity ID (0–6, 99). |
| `staging` | string | `"true"` or `"false"` — whether the constituent rule was in `Staging` state when it fired. |
| `detection_rule_id` | string (UUID) | Opaque — **do not use in correlation queries**. Not present in YAML. |
| `query_text` | string | The constituent rule's `query_text:` — useful for pivoting back to source data. |
| `tenant_id` | string | Scanner tenant. |
| `timestamp` | string (RFC-3339) | When the detection event was written. |
| `@scnr.time_ns` | int (ns) | Same instant, nanosecond integer. Use for time math. |
| `@scnr.datetime` | string | Same instant, ISO string. |
| `@index` | string | Always `_detections`. |
| `detected_in_time_range.start` | RFC-3339 | The query window the rule evaluated over. |
| `detected_in_time_range.end` | RFC-3339 | |
| `tags[0]`, `tags[1]`, …, `tags[N]` | strings | Positional fields holding the constituent rule's `tags:` array. Match with `tags[*]:<value>`. |

## Results-table fields

The constituent rule's `query_text` produces a results table. Each column gets surfaced as a `_detections` field:

- `results_table.total_row_count` — how many rows the constituent's query produced.
- `results_table.columns[0]`, `results_table.columns[1]`, … — column names of the results table.
- `results_table.rows[0].<col>` — the **first row's value** for each column. This is what correlations pivot on.
- `results_table.rows[1].<col>`, etc. — additional rows. Most correlations only use `rows[0]`.

When a constituent rule uses `alert_per_row: true`, the constituent emits one `_detections` event per row, so `rows[0]` is always the (only) row.

## Common pivot columns

These show up frequently in `results_table.rows[0].*` because they're standard grouping keys for AWS/Okta/etc. rules:

| Pivot | Source family | Used for correlating across |
|---|---|---|
| `results_table.rows[0].userIdentity.arn` | AWS CloudTrail | All IAM-touching activity for a single principal. |
| `results_table.rows[0].userIdentity.userName` | AWS CloudTrail | When `arn` isn't available (root, anonymous). |
| `results_table.rows[0].sourceIPAddress` | AWS CloudTrail | Network-side correlation. |
| `results_table.rows[0].awsRegion` | AWS CloudTrail | Regional anomaly correlation. |
| `results_table.rows[0].recipientAccountId` | AWS CloudTrail | Cross-account activity. |
| `results_table.rows[0].@ecs.user.name` | ECS-normalised | Cross-source (any rule that maps to ECS). |
| `results_table.rows[0].@ecs.source.ip` | ECS-normalised | Cross-source network. |
| `results_table.rows[0].actor.id` | Okta / Auth0 / SaaS | SSO-side correlation. |

Before pivoting on a field, confirm it's populated for *all* constituent rules via:

```scanner
@index=_detections name:"<Constituent Rule Name>"
| head 1
```

…and look at the returned columns. If `results_table.rows[0].userIdentity.arn` is missing, that constituent groups by something else and won't correlate cleanly on this pivot.

## Tag matching

Tags are stored as **positional fields**, not as a single array column. To filter:

```scanner
@index=_detections tags[*]:correlation.cloud_credential_theft   # ✅ correct
@index=_detections tags:correlation.cloud_credential_theft       # ❌ zero hits (bare `tags:` doesn't span positional fields)
@index=_detections tags[**]:correlation.cloud_credential_theft   # works but is for deep-path matching
```

`tags[*]:value` is the canonical form.

## Severity field

Filter by severity for severity-aware correlations:

```scanner
@index=_detections severity=("Low" "Informational") tags[*]:correlation.<label>
```

Filter for staging vs active:

```scanner
@index=_detections staging=false        # active rule firings only
@index=_detections staging=true         # firings from rules still in Staging — useful for promotion review
```

## Joining back to source data

Each detection event carries the constituent rule's `query_text` and `detected_in_time_range.start/end`. To pull the underlying source events that triggered the firing:

1. Read `query_text` and `detected_in_time_range` from the detection.
2. Re-run the rule's filter clause (no aggregations) over `[start, end]` on the same source index.
3. Inspect the raw events.

This is the standard pattern used by `triage-alert` for investigation; correlations rarely need it directly.
