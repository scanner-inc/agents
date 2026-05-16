# Splunk SPL → Scanner translation

This file documents the most common patterns when migrating Splunk `security_content` detections (or hand-authored SPL) to Scanner detection rules.

## Macro unwrapping

Splunk SPL is dense with macros (`` `name` `` syntax). Unwrap them first:

| Splunk macro | Meaning | Scanner equivalent |
|---|---|---|
| `` `cloudtrail` `` | `index=cloudtrail` (per `security_content/macros/cloudtrail.yml`) | `@scnr.source_type="aws:cloudtrail"` (preferred). Detection rules query all readable indexes by default; only add `@index={UUID|"alias"}` if the customer needs explicit prod/staging scoping. |
| `` `okta` `` | Okta source | `%ingest.source_type="okta"` |
| `` `aws_securityhub` `` | SecurityHub source | `%ingest.source_type="aws:securityhub"` |
| `` `security_content_ctime(field)` `` | Format epoch field as readable time | Drop — Scanner emits ISO timestamps natively |
| `` `<rule_name>_filter` `` | Tail filter macro for tuning suppressions | Drop on initial migration; if the user has tuning entries in the macro, fold them into `query_text` as `and not …` clauses |

When unsure, look up the macro — locally at `~/src/security_content/macros/` if cloned, otherwise `curl -sSL "https://raw.githubusercontent.com/splunk/security_content/develop/macros/<macro>.yml"`. Most are simple text substitutions.

## Operator translation

| Splunk SPL | Scanner |
|---|---|
| `field=value` | `field:value` (token-match, preferred) or `field="value"` (exact-match) |
| `field=*value*` | `field:value` (Scanner's `:` is token-match; if `value` is a full token in the field, it'll match) |
| `field!=value` | `not field:value` |
| `field=*value` (leading wildcard, slow) | Same as `:value` — try to avoid leading wildcards |
| `field=value*` | `field:value*` (trailing wildcard, fast) |
| `field>N`, `field<N` | Same (`field>N`, `field<N`) — numeric only |
| `eventName=A OR eventName=B` | `eventName: ("A" "B")` (parenthesised list) |
| `(A AND B) OR C` | `(A and B) or C` — Scanner is lowercase + parens |

## Pipeline operators

| Splunk | Scanner |
|---|---|
| `\| stats count by user` | `\| groupbycount(user)` (auto-sorted by count desc, top 1000) OR `\| stats count() by user` |
| `\| stats count, min(_time) as firstTime, max(_time) as lastTime by user` | `\| stats count() as eventCount, min(@scnr.datetime) as firstTime, max(@scnr.datetime) as lastTime by user` |
| `\| stats values(field) as fieldList by group` | Not 1:1. Closest: `\| stats countdistinct(field) as fieldCount by group` if you only need the count |
| `\| stats dc(field) by group` (distinct count) | `\| stats countdistinct(field) by group` |
| `\| where count > 5` | `\| where @q.count > 5` or `\| where eventCount > 5` (use the alias) |
| `\| dedup user` | No direct equivalent. Use `\| stats count() by user` to get one row per user |
| `\| eval x = if(condition, a, b)` | `\| eval(x = if(condition, a, b))` (parens around the assignment) |
| `\| rename a as b` | `\| rename(a as b)` |
| `\| table f1 f2` | `\| table(f1, f2)` |
| `\| head 10` | `\| head 10` (same) |
| `\| sort -count` | No sort. Use `\| groupbycount(...)` which auto-sorts desc |

## Common idioms

### Token-match search

```
Splunk:   `cloudtrail` eventSource="iam.amazonaws.com" eventName=DeletePolicy (userAgent!=*.amazonaws.com)
Scanner:  %ingest.source_type="aws:cloudtrail"
          eventSource="iam.amazonaws.com"
          eventName=DeletePolicy
          not userAgent: ".amazonaws.com"
```

Note: `userAgent!=*.amazonaws.com` in Splunk means "user agent doesn't contain `.amazonaws.com` as a substring". In Scanner, `not userAgent: ".amazonaws.com"` works because `.` is a token boundary and `amazonaws` will appear as a complete token in matching user agents.

### Stats with grouping

```
Splunk:   ... | stats count min(_time) as firstTime max(_time) as lastTime by src eventName aws_account_id userIdentity.arn
Scanner:  ...
          | stats
              count() as eventCount,
              min(@scnr.datetime) as firstTime,
              max(@scnr.datetime) as lastTime
              by sourceIPAddress, eventName, recipientAccountId, userIdentity.arn
```

Field-name notes for CloudTrail:
- Splunk's `src` → Scanner's `sourceIPAddress`.
- Splunk's `aws_account_id` → Scanner's `recipientAccountId` or `userIdentity.accountId` depending on context.
- `_time` (Splunk's epoch timestamp) → `@scnr.datetime` (ISO string) or `@scnr.time_ns` (integer nanoseconds).

### Threshold detection

```
Splunk:   ... | stats count by user | where count > 10
Scanner:  ...
          | stats count() as eventCount by user
          | where eventCount > 10
```

### Lookup table

```
Splunk:   ... | lookup corporate_cidrs cidr OUTPUT classification | where isnull(classification)
Scanner:  Requires ingest-time enrichment. Hand off to /write-vrl.
          Migrated rule consumes the enriched field:
          ... and not @enrichment.cidr_classification:"corporate"
```

## Severity mapping

Splunk security_content uses `risk_score` (0–100) and `confidence` / `impact` (each 0–100):

| `risk_score` range | Scanner severity |
|---|---|
| 0–25 | `Low` |
| 26–50 | `Medium` |
| 51–75 | `High` |
| 76–100 | `Critical` |

For migrated rules, the skill writes `enabled: Staging` regardless of the Splunk rule's state.

## MITRE mapping

Splunk: `mitre_attack_id: [T1098]`. Scanner: `tags: [techniques.t1098.account_manipulation]`.

Subtechniques (`T1098.001`) → parent technique tag (`techniques.t1098.account_manipulation`).

Tactics aren't usually in Splunk rules; derive from `kill_chain_phases:` (`Actions on Objectives` → `tactics.ta0040.impact`, etc.) and add explicitly. Use `mitre_tags.md` for canonical strings.

## Inline tests

Splunk security_content rules typically link to test datasets via:

```yaml
tags:
  dataset:
    - https://media.githubusercontent.com/media/splunk/attack_data/master/datasets/attack_techniques/T1098/aws_iam_delete_policy/aws_iam_delete_policy.json
```

The skill can `curl` the dataset URL, sample 2–4 events, and translate them into `dataset_inline` JSONL. Sanitise account IDs/ARNs/IPs.

For rules without a dataset URL, synthesise tests from MCP-pulled real events (Phase 5 of methodology).

## Compound rules — decomposition

Some Splunk rules combine multiple distinct conditions across time (`subsearch`, `transaction`, `streamstats`). Scanner doesn't have direct equivalents. For these:

1. Decompose into 2–3 simpler Scanner rules.
2. Tag each with `correlation.<custom_label>`.
3. Author a correlation rule via `/write-correlation`.

Document the trade-off in the correlation rule's `description`:

> Decomposed from Splunk rule `<name>`. The original used `transaction` to require event A within N seconds of event B; the decomposed Scanner rules each fire on their own event, and the correlation rule promotes when both fire on the same `userIdentity.arn` in a 10-minute window. This is broader (allows the events in any order, slightly wider window) but catches the same threat with higher signal-to-noise.

## Field-name cheat-sheet (CloudTrail-focused)

| Splunk SPL field | Scanner CloudTrail field |
|---|---|
| `eventName` | `eventName` |
| `eventSource` | `eventSource` |
| `awsRegion` | `awsRegion` |
| `errorCode` | `errorCode` |
| `errorMessage` | `errorMessage` |
| `userAgent` | `userAgent` |
| `user` (common alias) | `userIdentity.userName` or `userIdentity.arn` |
| `user_arn` | `userIdentity.arn` |
| `src` / `src_ip` | `sourceIPAddress` |
| `aws_account_id` | `recipientAccountId` |
| `_time` | `@scnr.datetime` (string) / `@scnr.time_ns` (int ns) |
| `requestParameters.*` | `requestParameters.*` (same path) |
| `responseElements.*` | `responseElements.*` (same path) |
| `userIdentity.principalId` | `userIdentity.principalId` |

For non-CloudTrail sources, sample real events via MCP `head 3` and read the actual field paths — Splunk's data models often rename fields differently from raw source.
