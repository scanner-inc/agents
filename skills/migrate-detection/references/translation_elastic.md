# Elastic detection rule → Scanner translation

Elastic Security ships rules as TOML files (newer) or JSON (older). Queries are KQL ("kuery") or EQL.

**Note on the native `scanner-cli migrate-elastic-rules` command:** it exists but is beta / unreliable. **Do not use it.** All Elastic migrations go through this skill's model-driven workflow.

## File shape

```toml
[metadata]
creation_date = "2020-09-07"
maturity = "production"
min_stack_version = "8.3.0"

[rule]
author = ["Elastic"]
description = "..."
language = "kuery"          # or "eql", "lucene"
license = "Elastic License v2"
name = "AWS IAM User Creation"
note = "..."
references = ["..."]
risk_score = 47              # 0–100
rule_id = "<uuid>"
severity = "medium"          # vendor severity string
tags = ["Domain: Cloud", "Data Source: AWS", "Use Case: Identity and Access Audit"]
type = "query"               # or "eql", "threshold", "threat_match", "machine_learning"
index = ["filebeat-*", "logs-aws.cloudtrail-*"]
query = '''
event.dataset:aws.cloudtrail and event.provider:iam.amazonaws.com and event.action:CreateUser
'''

[[rule.threat]]
framework = "MITRE ATT&CK"
[[rule.threat.tactic]]
id = "TA0003"
name = "Persistence"
[[rule.threat.technique]]
id = "T1078"
name = "Valid Accounts"
```

## Top-level mapping

| Elastic field | Scanner field |
|---|---|
| `name` | `name` |
| `description` (+ `note`) | `description` |
| `severity: low/medium/high/critical` | `severity` (capital-case first letter) |
| `risk_score: 0–100` | (informational; severity carries the priority) |
| `type: query` | (a normal Scanner rule) |
| `type: eql` | EQL has sequence semantics — may need decomposition + correlation |
| `type: threshold` | Build into the Scanner query as `| stats count() | where eventCount > N` |
| `type: machine_learning` | Not directly translatable; skip with a note to the user |
| `index: ["filebeat-*", ...]` | Determines Scanner index / source-type (often via the implicit `event.dataset` field) |
| `tags: ["Domain: Cloud", "Data Source: AWS"]` | (drop or repurpose) |
| `rule.threat.tactic.id = "TA0003"` | `tactics.ta0003.persistence` |
| `rule.threat.technique.id = "T1078"` | `techniques.t1078.valid_accounts` |
| `rule_id` (UUID) | preserve in `description` |

Always add `source.<slug>` based on the inferred source-type.

## ECS field paths

Elastic rules use ECS (Elastic Common Schema) field paths everywhere: `event.action`, `event.dataset`, `event.provider`, `user.name`, `source.ip`, `host.name`, etc.

**Critical**: this only works in Scanner if the source data is already ECS-shaped. Two cases:

### Case A: Scanner data is ECS

If the user has already installed a VRL transformation that maps the source to ECS (the `write-vrl` skill is built for this), then ECS paths in the migrated rule will work — just prefix with `@ecs.`:

```
Elastic:  event.action:CreateUser
Scanner:  @ecs.event.action="CreateUser"
```

The `write-vrl` skill's corpus has CloudTrail → ECS, Okta → ECS, GitHub → ECS, and others.

### Case B: Scanner data is source-native (no ECS layer)

The migrated rule needs to use the **raw source field paths**. ECS → CloudTrail-native mapping:

| ECS path | CloudTrail-native path |
|---|---|
| `event.dataset:aws.cloudtrail` | `%ingest.source_type="aws:cloudtrail"` |
| `event.provider` | `eventSource` |
| `event.action` | `eventName` |
| `event.outcome:success` | `not errorCode:*` |
| `event.outcome:failure` | `errorCode:*` |
| `user.name` | `userIdentity.userName` |
| `user.id` | `userIdentity.principalId` or `userIdentity.arn` |
| `source.ip` | `sourceIPAddress` |
| `cloud.account.id` | `recipientAccountId` |
| `cloud.region` | `awsRegion` |
| `user_agent.original` | `userAgent` |

If unsure which case the user is in, sample real events from the Scanner index via MCP and read the field names. The presence of `@ecs.event.action` in the response means Case A; absence (with `eventName` instead) means Case B.

Best practice: **prefer Case A**. If the user is migrating Elastic rules at scale, suggest they also install the ECS-normalisation VRL via `/write-vrl` so all ECS-native rules (Elastic, future Sigma-Kibana, etc.) work without per-rule field rewriting.

## KQL → Scanner query

Elastic's KQL is broadly similar to Sentinel's KQL but with ECS field paths and Elastic-specific quirks.

| Elastic KQL | Scanner |
|---|---|
| `field:value` | `field:value` (token-match — same idea) |
| `field:"value"` | `field="value"` (exact-match) |
| `field:(a or b)` | `field: ("a" "b")` |
| `field:a and field2:b` | `field:a field2:b` (and is default) |
| `not field:value` | `not field:value` (same) |
| `field:value*` | `field:value*` |
| `field:*value` | `field:*value` (slow — flag) |
| `field > N` | `field>N` |
| `field:*` (exists) | `field:*` (same) |

The big difference: Elastic uses bare `or` (lowercase) freely; Scanner needs the parenthesised-list form for OR'd values on the same field. Other than that, KQL maps cleanly.

## EQL → Scanner

EQL is for sequence detection:

```eql
sequence by user.name
  [authentication where event.outcome == "failure"] with maxspan=10m
  [authentication where event.outcome == "success"]
```

Scanner doesn't have a native sequence operator. Two paths:

### Path A — decomposition + correlation

1. Scanner rule A on the first event (`event.outcome="failure"`).
2. Scanner rule B on the second (`event.outcome="success"`).
3. Correlation rule via `/write-correlation` joining on `user.name` within `time_range_s: 600` (10 min ≈ maxspan).

Document in the correlation rule's `description` that the temporal ordering of EQL isn't preserved — Scanner correlation matches "both fired in the window" without strict ordering. Often this is fine.

### Path B — single rule with stats

For simpler EQL patterns:

```eql
process where event.action == "execution" and process.name == "powershell.exe"
```

…just translate to a single-event filter:

```scanner
@ecs.event.action="execution"
@ecs.process.name="powershell.exe"
```

## threshold rules

```toml
type = "threshold"

[rule.threshold]
field = ["user.name", "source.ip"]
value = 10
```

The rule fires when 10+ events match the filter for the same `(user.name, source.ip)` tuple. → Scanner:

```scanner
…filter…
| stats count() as eventCount by user.name, source.ip
| where eventCount > 10
```

…with `time_range_s` matching the rule's `interval` × some multiplier.

## threat_match rules

```toml
type = "threat_match"

[[rule.threat_filters]]
...

[rule.threat_query]
"event.module:threatintel"
```

These join the user's logs against indexed threat-intel feeds. Scanner equivalent: invoke `/lookup-ioc` for one-off IOC lookups, or stand up a VRL transformation that tags IPs/domains/hashes against an MMDB at ingest. Hand off to `/write-vrl` for the ingest path; the migrated rule consumes the enriched tag.

## machine_learning rules

```toml
type = "machine_learning"
machine_learning_job_id = ["...job-id..."]
```

Not translatable. Tell the user this rule depends on an Elastic ML job and can't be migrated 1:1. Workarounds:
- If the user knows what the ML job detects (anomalous logon hours, unusual user-agent volume, etc.), draft an approximate Scanner rule using `stats` + `where` thresholds.
- Otherwise skip with a clear note.

## Severity mapping

| Elastic `severity` | Scanner `severity` |
|---|---|
| `low` | `Low` |
| `medium` | `Medium` |
| `high` | `High` |
| `critical` | `Critical` |

`risk_score` is informational; the severity carries the priority.

## Lookup tables / enrich processors

Elastic's `enrich` processor and Watcher inputs that read from indices effectively act as lookup tables. Hand off to `/write-vrl` for ingest-time enrichment (same as Splunk lookups / Sentinel watchlists).

## Worked example

**Elastic source (TOML):**

```toml
[rule]
author = ["Elastic"]
description = "Detects creation of an AWS IAM user."
name = "AWS IAM User Creation"
risk_score = 47
severity = "medium"
type = "query"
language = "kuery"
index = ["logs-aws.cloudtrail-*"]
query = '''
event.dataset:aws.cloudtrail and event.provider:iam.amazonaws.com and event.action:CreateUser and event.outcome:success
'''
rule_id = "12345678-…"

[[rule.threat]]
framework = "MITRE ATT&CK"
[[rule.threat.tactic]]
id = "TA0003"
name = "Persistence"
[[rule.threat.technique]]
id = "T1136"
name = "Create Account"
```

**Scanner translation** (assuming Case B — CloudTrail-native data in Scanner):

```yaml
# schema: https://scanner.dev/schema/scanner-detection-rule.v1.json
name: AWS IAM User Creation
enabled: Staging
description: |-
  Detects successful creation of an AWS IAM user — a step in establishing
  persistence or attacker-controlled credentials.

  Migrated from Elastic detection rule `12345678-…`.
severity: Medium
query_text: |-
  %ingest.source_type="aws:cloudtrail"
  eventSource="iam.amazonaws.com"
  eventName="CreateUser"
  not errorCode:*
  | stats
      min(@scnr.datetime) as firstTime,
      max(@scnr.datetime) as lastTime,
      count() as eventCount
      by userIdentity.arn, requestParameters.userName, awsRegion
time_range_s: 300
run_frequency_s: 60
event_sink_keys:
  - medium_severity_alerts
tags:
  - source.cloudtrail
  - tactics.ta0003.persistence
  - techniques.t1136.create_account
alert_template:
  info:
    - label: Creator
      value: "{{results_table.rows[0].userIdentity.arn}}"
      use_for_dedup: true
    - label: New user
      value: "{{results_table.rows[0].requestParameters.userName}}"
    - label: Region
      value: "{{results_table.rows[0].awsRegion}}"
tests:
  - name: Fires on successful CreateUser
    now_timestamp: "2026-05-15T00:03:00.000Z"
    dataset_inline: |
      {"timestamp":"2026-05-15T00:02:30.000Z","%ingest.source_type":"aws:cloudtrail","eventSource":"iam.amazonaws.com","eventName":"CreateUser","userIdentity":{"arn":"arn:aws:iam::123456789012:user/admin"},"requestParameters":{"userName":"new-user"},"awsRegion":"us-east-1"}
    expected_detection_result: true
  - name: Does not fire on failed CreateUser
    now_timestamp: "2026-05-15T00:03:00.000Z"
    dataset_inline: |
      {"timestamp":"2026-05-15T00:02:30.000Z","%ingest.source_type":"aws:cloudtrail","eventSource":"iam.amazonaws.com","eventName":"CreateUser","errorCode":"AccessDenied","userIdentity":{"arn":"arn:aws:iam::123456789012:user/admin"},"requestParameters":{"userName":"new-user"},"awsRegion":"us-east-1"}
    expected_detection_result: false
```

Translation notes:
- `event.dataset:aws.cloudtrail` → `%ingest.source_type="aws:cloudtrail"`.
- `event.provider:iam.amazonaws.com` → `eventSource="iam.amazonaws.com"`.
- `event.action:CreateUser` → `eventName="CreateUser"`.
- `event.outcome:success` → `not errorCode:*` (Scanner's idiom for "non-failed CloudTrail").
- Added a `stats … by …` aggregation so the rule fires once per principal/new-user combination rather than per raw event.
