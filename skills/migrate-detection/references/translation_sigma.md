# Sigma → Scanner translation

Sigma is the "lingua franca" of detection rules — structured YAML that's relatively easy to translate. Most Sigma rules have a 1:1 mapping to Scanner.

## Top-level field mapping

| Sigma field | Scanner YAML field |
|---|---|
| `title` | `name` |
| `id` | (drop — Scanner assigns its own; preserve in `description` for traceability) |
| `description` | `description` (prepend `## Goal` and append `## References` from `references:`) |
| `status: stable/test/experimental` | (note in `description`; `enabled: Staging` regardless) |
| `level: informational/low/medium/high/critical` | `severity:` (`Informational`/`Low`/`Medium`/`High`/`Critical`) |
| `tags: [attack.tactic-name, attack.tNNNN, attack.tNNNN.NNN]` | `tags: [tactics.taXXXX.snake_name, techniques.tNNNN.snake_name, source.<slug>]` — strip subtechnique numbers |
| `falsepositives: [...]` | Append to `description` under `## False Positives` |
| `references: [...]` | Append to `description` under `## References` |
| `author` | (drop or note in `description`) |
| `date` / `modified` | (drop — git history tracks this) |

## logsource → Scanner index/source-type

| Sigma `logsource` | Scanner mapping |
|---|---|
| `product: aws`, `service: cloudtrail` | `@scnr.source_type="aws:cloudtrail"` (preferred — built-in source-type, works across every index carrying CloudTrail). Only add `@index={UUID|"alias"}` if the customer needs prod/staging scoping. |
| `product: aws`, `service: guardduty` | `%ingest.source_type="aws:guardduty"` |
| `product: okta` | `%ingest.source_type="okta"` |
| `product: github` | `%ingest.source_type="github"` |
| `product: gcp`, `service: gcp.audit` | `%ingest.source_type="gcp:audit"` |
| `product: azure`, `service: signinlogs` | `%ingest.source_type="azure:signin"` |
| `product: m365`, `service: …` | `%ingest.source_type="m365:…"` |
| `product: windows`, `service: security` | Depends on user's ingest path (Sysmon, WinEvent forwarder, etc.). Confirm via `get_top_columns`. |

If unsure, ask the user once per session and cache the mapping.

## detection block → query_text

Sigma's `detection:` block contains one or more `selection_*` keys plus a `condition:` that combines them.

### Simple selection

```yaml
detection:
  selection:
    eventSource: cloudtrail.amazonaws.com
    eventName:
      - StopLogging
      - UpdateTrail
      - DeleteTrail
  condition: selection
```

→

```scanner
%ingest.source_type="aws:cloudtrail"
eventSource="cloudtrail.amazonaws.com"
eventName: ("StopLogging" "UpdateTrail" "DeleteTrail")
```

### Selection + filter (and-not)

```yaml
detection:
  selection_source:
    eventName: ConsoleLogin
  filter_internal:
    sourceIPAddress|cidr: '10.0.0.0/8'
  condition: selection_source and not filter_internal
```

→

```scanner
%ingest.source_type="aws:cloudtrail"
eventName="ConsoleLogin"
not sourceIPAddress: "10."
```

Note: Scanner doesn't have native CIDR matching at query time. Options:
- Token-match on the CIDR prefix (`sourceIPAddress: "10."` matches `10.x.x.x` as the leading token). Fragile but works for /8.
- For arbitrary CIDRs, hand off to `/write-vrl` to add a classification field at ingest (e.g., `source.classification`, or `@ecs.network.type` if it fits), then filter on that. See methodology.md "Field namespace for enrichment output" for choosing the path.

### Multiple selections (and/or)

```yaml
detection:
  s1: { eventName: PutBucketAcl }
  s2: { eventName: PutBucketPolicy }
  condition: s1 or s2
```

→

```scanner
%ingest.source_type="aws:cloudtrail"
eventName: ("PutBucketAcl" "PutBucketPolicy")
```

(Prefer parenthesised list to OR'd predicates — same result, cleaner.)

## Modifier translation

Sigma uses `field|modifier:` to control match semantics:

| Sigma modifier | Scanner equivalent |
|---|---|
| `field:` (no modifier) | `field:value` (token-match) — usually fine |
| `field|contains:` | `field:value` (already token-match; if `value` is a sub-token, may need `*value*` — slow) |
| `field|startswith:` | `field:value*` (trailing wildcard, fast) |
| `field|endswith:` | `field:*value` (leading wildcard, SLOW — flag perf concern) |
| `field|re:` | No regex in Scanner queries. Either translate the regex into a token pattern, or hand off to `/write-vrl` to add a derived field |
| `field|all:` (all values must match) | Multiple `and` clauses |
| `field|cidr:` | See "Simple selection + filter" above |
| `field|exists:` | `field:*` (Scanner's "field exists" check) |
| `field|gte:` / `field|lte:` | `field>=N` / `field<=N` (numeric only) |

## level → severity + event_sink_keys

```
informational → Informational, no event_sink_keys
low           → Low,           no event_sink_keys
medium        → Medium,        event_sink_keys: [medium_severity_alerts]
high          → High,          event_sink_keys: [high_severity_alerts]
critical      → Critical,      event_sink_keys: [critical_severity_alerts]
```

Per `write-detection/references/severity_policy.md`: Medium+ alerts, Low/Info are signals.

## tags → MITRE tags

Sigma uses `attack.tactic-name-with-dashes` and `attack.tNNNN` (technique) or `attack.tNNNN.NNN` (subtechnique).

| Sigma tag form | Scanner tag |
|---|---|
| `attack.defense-evasion` | `tactics.ta0005.defense_evasion` (look up the tactic ID) |
| `attack.credential-access` | `tactics.ta0006.credential_access` |
| `attack.t1562` | `techniques.t1562.impair_defenses` (look up in `mitre_tags.md`) |
| `attack.t1562.008` (subtechnique) | `techniques.t1562.impair_defenses` (Scanner's list is parent-technique-level — drop the subtechnique number) |
| `cve.2024-XXXX` | (drop — Scanner doesn't have a CVE namespace yet; mention in `description`) |
| `detection.threat-hunting` | (drop) |

Always add `source.<slug>` based on the Sigma `logsource:`.

## Test fixtures

Most Sigma rules don't ship test fixtures. Some do (under `tests/` adjacent to the rule). For those without:

1. Sample 2–3 real events from the mapped Scanner index via MCP.
2. Sanitise (canonical account IDs, ARNs, IPs).
3. Translate into `dataset_inline` JSONL.
4. Hand-craft one negative test.

## Worked example

**Sigma source** (`aws_cloudtrail_disable_logging.yml`):

```yaml
title: AWS CloudTrail Important Change
id: 4db60cc0-36fb-42b7-9b58-a5b53019fb74
status: test
description: Detects disabling, deleting and updating of a Trail
references:
    - https://docs.aws.amazon.com/awscloudtrail/latest/userguide/best-practices-security.html
tags:
    - attack.defense-evasion
    - attack.t1562.008
logsource:
    product: aws
    service: cloudtrail
detection:
    selection_source:
        eventSource: cloudtrail.amazonaws.com
        eventName:
            - StopLogging
            - UpdateTrail
            - DeleteTrail
    condition: selection_source
falsepositives:
    - Valid change in a Trail
level: medium
```

**Scanner translation:**

```yaml
# schema: https://scanner.dev/schema/scanner-detection-rule.v1.json
name: AWS CloudTrail Important Change
enabled: Staging
description: |-
  Detects disabling, deleting, or updating of an AWS CloudTrail trail —
  attacker behaviour aimed at evading auditing.

  ## References
  - https://docs.aws.amazon.com/awscloudtrail/latest/userguide/best-practices-security.html

  ## False Positives
  - Valid administrative change to a Trail (planned audit-config update)

  Migrated from Sigma rule `4db60cc0-36fb-42b7-9b58-a5b53019fb74`.
severity: Medium
query_text: |-
  %ingest.source_type="aws:cloudtrail"
  eventSource="cloudtrail.amazonaws.com"
  eventName: ("StopLogging" "UpdateTrail" "DeleteTrail")
  | stats
      min(@scnr.datetime) as firstTime,
      max(@scnr.datetime) as lastTime,
      count() as eventCount
      by userIdentity.arn, eventName, awsRegion
time_range_s: 300
run_frequency_s: 60
event_sink_keys:
  - medium_severity_alerts
tags:
  - source.cloudtrail
  - tactics.ta0005.defense_evasion
  - techniques.t1562.impair_defenses
tests:
  - name: Test fires on StopLogging
    now_timestamp: "2026-05-15T00:03:00.000Z"
    dataset_inline: |
      {"timestamp":"2026-05-15T00:02:30.000Z","%ingest.source_type":"aws:cloudtrail","eventSource":"cloudtrail.amazonaws.com","eventName":"StopLogging","userIdentity":{"arn":"arn:aws:iam::123456789012:user/JohnDoe"},"awsRegion":"us-west-2"}
    expected_detection_result: true
  - name: Test does not fire on benign CreateTrail
    now_timestamp: "2026-05-15T00:03:00.000Z"
    dataset_inline: |
      {"timestamp":"2026-05-15T00:02:30.000Z","%ingest.source_type":"aws:cloudtrail","eventSource":"cloudtrail.amazonaws.com","eventName":"CreateTrail","userIdentity":{"arn":"arn:aws:iam::123456789012:user/JohnDoe"},"awsRegion":"us-west-2"}
    expected_detection_result: false
```

Note the `| stats … by …` aggregation was added: Sigma doesn't aggregate by default, but Scanner rules nearly always want a group-by-entity stats clause so the rule fires once per principal rather than per raw event.
