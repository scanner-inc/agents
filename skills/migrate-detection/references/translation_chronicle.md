# Chronicle YARA-L 2.0 → Scanner translation

Chronicle (now Google SecOps) uses YARA-L 2.0 — a procedural rule language with `meta:`, `events:`, `outcome:`, and `condition:` blocks. The main translation challenge is **UDM field paths** (Chronicle's Unified Data Model) → source-native field paths.

## Top-level structure

```yaral
rule <rule_name> {
  meta:    # key/value attributes — like Sigma's frontmatter
    …
  events:  # filter clauses — like Sigma's detection.selection_*
    …
  outcome: # fields to surface in the detection event — like Scanner's alert_template
    …
  condition: # combiner — like Sigma's detection.condition
    …
}
```

→ Scanner detection rule YAML.

## meta block → Scanner top-level fields

| YARA-L `meta` key | Scanner field |
|---|---|
| `rule_name` | `name` |
| `description` | `description` (preserve, append `## References` if `reference` present) |
| `severity` | `severity` (`"High"` → `High`) |
| `data_source` | Use to determine `%ingest.source_type` and `@index` |
| `mitre_attack_tactic` (display name) | Look up tactic ID; e.g., `"Defense Evasion"` → `tactics.ta0005.defense_evasion` |
| `mitre_attack_technique_id` | `techniques.tNNNN.snake_name` (look up in `mitre_tags.md`) |
| `type = "Alert"` | (already implied by Scanner rules) |
| `rule_id`, `author`, `mitre_attack_url` | (drop or preserve in `description`) |
| `platform` | (drop — `data_source` carries this) |

## events block → query_text filter

YARA-L events look like:

```yaral
events:
  $cloudtrail.metadata.vendor_name = "AMAZON"
  $cloudtrail.metadata.product_name = "AWS CloudTrail"
  $cloudtrail.metadata.product_event_type = "DeleteDetector"
  $cloudtrail.security_result.action = "ALLOW"
```

These are **AND**'d by default. Each line uses an event variable (`$cloudtrail`) and UDM field paths.

### UDM → CloudTrail-native field mapping

Chronicle normalises to UDM; Scanner usually has the raw source schema. Common CloudTrail mappings:

| UDM path | CloudTrail-native path |
|---|---|
| `$cloudtrail.metadata.vendor_name` | (implicit) — replace with `%ingest.source_type="aws:cloudtrail"` |
| `$cloudtrail.metadata.product_name` | (implicit) — same as above |
| `$cloudtrail.metadata.product_event_type` | `eventName` |
| `$cloudtrail.metadata.event_type` | (often `NETWORK_CONNECTION`, `USER_LOGIN`, etc. — translate behaviour, not the literal value) |
| `$cloudtrail.metadata.id` | `eventID` |
| `$cloudtrail.principal.user.email` | `userIdentity.userName` (when ARN-shaped) or note in description |
| `$cloudtrail.principal.user.user_display_name` | `userIdentity.userName` |
| `$cloudtrail.principal.ip` | `sourceIPAddress` |
| `$cloudtrail.principal.location.name` | `awsRegion` |
| `$cloudtrail.principal.ip_geo_artifact.location.country_or_region` | Requires GeoIP enrichment — hand off to `/write-vrl` with an MMDB lookup, or drop |
| `$cloudtrail.target.resource.name` | `requestParameters.<resourceType>Name` or `resources[0].ARN` (resource-specific) |
| `$cloudtrail.target.resource.attribute.labels["enable"]` | `requestParameters.enable` (or wherever the attribute lives in raw) |
| `$cloudtrail.security_result.action` | (implicit — non-failed CloudTrail events) or `errorCode:*` for failures |
| `$cloudtrail.network.http.user_agent` | `userAgent` |
| `$cloudtrail.additional.fields["recipientAccountId"]` | `recipientAccountId` |

For non-CloudTrail sources, the UDM paths are usually documented in Chronicle's UDM Field List. Sample real events from the Scanner index via MCP `head 3` and read the actual paths.

### Translating array attribute access

```yaral
$cloudtrail.target.resource.attribute.labels["enable"] = "false"
```

These nested labels are usually stored in Scanner as `requestParameters.<labelKey>`. Pull a real event to confirm. Often:

```scanner
requestParameters.enable="false"
```

## outcome block → alert_template

YARA-L `outcome` fields are surfaced on the detection. Map them to Scanner's `alert_template.info` array, pulling values from `results_table.rows[0].*`:

```yaral
outcome:
  $risk_score = max(75)
  $principal_user_display_name = $cloudtrail.principal.user.user_display_name
  $principal_ip = array_distinct($cloudtrail.principal.ip)
  $aws_region = $cloudtrail.principal.location.name
```

→

```yaml
alert_template:
  info:
    - label: User
      value: "{{results_table.rows[0].userIdentity.userName}}"
      use_for_dedup: true
    - label: Source IP
      value: "{{results_table.rows[0].sourceIPAddress}}"
    - label: Region
      value: "{{results_table.rows[0].awsRegion}}"
```

`max()` / `array_distinct()` are YARA-L aggregations; Scanner can express them in `stats` (`max(...)`, no built-in `array_distinct` — closest is `countdistinct`).

## condition block → query post-aggregation

| YARA-L condition | Scanner translation |
|---|---|
| `condition: $cloudtrail` | (no extra clause — filter events suffice) |
| `condition: #cloudtrail > 5` | `| stats count() as eventCount | where eventCount > 5` |
| `condition: $cloudtrail and #ip > 10 over 1h` | `time_range_s: 3600` + `stats countdistinct(sourceIPAddress) as ipCount | where ipCount > 10` |
| Multi-event (`$cloudtrail.id != $other.id`) | Often requires decomposition + correlation rule |
| Time-window correlation (`$a.ts < $b.ts within 5m`) | Use `write-correlation` skill — Scanner correlation rules can express most temporal patterns by querying `_detections` |

## Match section (optional)

YARA-L's `match:` section groups events by a key over a window:

```yaral
match:
  $principal_user_display_name over 10m
```

This becomes the `by` clause of a Scanner `stats`:

```scanner
| stats count() as eventCount by userIdentity.userName
| where eventCount > <threshold>
```

…with `time_range_s: 600` matching the `over 10m`.

## Severity mapping

YARA-L `severity` is a free-form string but conventionally one of:

```
Informational | Low | Medium | High | Critical
```

Maps 1:1 to Scanner's severity values (capital-case is preserved).

`priority:` is informational; drop.

## Worked example

**YARA-L source:** `aws_guardduty_disabled.yaral` from the public Chronicle community rules at <https://github.com/chronicle/detection-rules/tree/main/rules/community/aws/cloudtrail>.

```yaral
rule aws_guardduty_disabled {
  meta:
    description = "Detects when a GuardDuty Detector is disabled or suspended."
    rule_id = "mr_22495d55-…"
    rule_name = "AWS GuardDuty Disabled"
    mitre_attack_tactic = "Defense Evasion"
    mitre_attack_technique = "Impair Defenses"
    severity = "High"
    data_source = "AWS CloudTrail"

  events:
    $cloudtrail.metadata.vendor_name = "AMAZON"
    $cloudtrail.metadata.product_name = "AWS CloudTrail"
    $cloudtrail.metadata.product_event_type = "DeleteDetector" or
      ($cloudtrail.metadata.product_event_type = "UpdateDetector" and
       $cloudtrail.target.resource.attribute.labels["enable"] = "false")
    $cloudtrail.security_result.action = "ALLOW"

  outcome:
    $risk_score = max(75)
    $principal_ip = array_distinct($cloudtrail.principal.ip)
    $principal_user_display_name = $cloudtrail.principal.user.user_display_name
    $aws_region = $cloudtrail.principal.location.name

  condition:
    $cloudtrail
}
```

**Scanner translation:**

```yaml
# schema: https://scanner.dev/schema/scanner-detection-rule.v1.json
name: AWS GuardDuty Disabled
enabled: Staging
description: |-
  Detects when a GuardDuty Detector is disabled or suspended — a defense-evasion
  step that blinds AWS-side anomaly detection.

  Migrated from Chronicle YARA-L rule `mr_22495d55-…`.
severity: High
query_text: |-
  %ingest.source_type="aws:cloudtrail"
  eventSource="guardduty.amazonaws.com"
  (
    eventName="DeleteDetector"
    or (eventName="UpdateDetector" and requestParameters.enable="false")
  )
  not errorCode:*
  | stats
      min(@scnr.datetime) as firstTime,
      max(@scnr.datetime) as lastTime,
      count() as eventCount
      by userIdentity.arn, eventName, awsRegion
time_range_s: 300
run_frequency_s: 60
event_sink_keys:
  - high_severity_alerts
tags:
  - source.cloudtrail
  - tactics.ta0005.defense_evasion
  - techniques.t1562.impair_defenses
alert_template:
  info:
    - label: User
      value: "{{results_table.rows[0].userIdentity.arn}}"
      use_for_dedup: true
    - label: Region
      value: "{{results_table.rows[0].awsRegion}}"
    - label: Action
      value: "{{results_table.rows[0].eventName}}"
tests:
  - name: Fires on DeleteDetector
    now_timestamp: "2026-05-15T00:03:00.000Z"
    dataset_inline: |
      {"timestamp":"2026-05-15T00:02:30.000Z","%ingest.source_type":"aws:cloudtrail","eventSource":"guardduty.amazonaws.com","eventName":"DeleteDetector","userIdentity":{"arn":"arn:aws:iam::123456789012:user/JohnDoe"},"awsRegion":"us-west-2"}
    expected_detection_result: true
  - name: Fires on UpdateDetector that disables
    now_timestamp: "2026-05-15T00:03:00.000Z"
    dataset_inline: |
      {"timestamp":"2026-05-15T00:02:30.000Z","%ingest.source_type":"aws:cloudtrail","eventSource":"guardduty.amazonaws.com","eventName":"UpdateDetector","requestParameters":{"enable":"false"},"userIdentity":{"arn":"arn:aws:iam::123456789012:user/JohnDoe"},"awsRegion":"us-west-2"}
    expected_detection_result: true
  - name: Does not fire on UpdateDetector that enables
    now_timestamp: "2026-05-15T00:03:00.000Z"
    dataset_inline: |
      {"timestamp":"2026-05-15T00:02:30.000Z","%ingest.source_type":"aws:cloudtrail","eventSource":"guardduty.amazonaws.com","eventName":"UpdateDetector","requestParameters":{"enable":"true"},"userIdentity":{"arn":"arn:aws:iam::123456789012:user/JohnDoe"},"awsRegion":"us-west-2"}
    expected_detection_result: false
```

Key translation moves:
1. UDM `$cloudtrail.metadata.product_event_type` → CloudTrail-native `eventName`.
2. UDM `$cloudtrail.target.resource.attribute.labels["enable"]` → `requestParameters.enable`.
3. `security_result.action = "ALLOW"` → `not errorCode:*` (Scanner's idiom for "non-failed").
4. `outcome:` block → `alert_template.info`.
5. Implicit `eventSource="guardduty.amazonaws.com"` (UDM doesn't have a separate eventSource, but Scanner's CloudTrail data does — adding it tightens the filter).
