# Panther Python → Scanner translation

Panther rules are Python functions, not declarative YAML. The model has to **read** the function body and emit the equivalent Scanner filter clause. This makes Panther translation higher-effort than Sigma/YARA-L, but also more open-ended (Python can express anything).

## File layout

Each Panther rule has **two** files:

```
panther-analysis/rules/aws_cloudtrail_rules/
├── aws_root_console_login.py     # the rule function
└── aws_root_console_login.yml    # metadata + tests
```

Read both. The `.py` carries the logic; the `.yml` carries severity, tags, MITRE, and test fixtures.

## YAML metadata → Scanner top-level

```yaml
AnalysisType: rule
RuleID: AWS.CloudTrail.RootConsoleLogin
DisplayName: AWS CloudTrail Root Console Login
LogTypes:
  - AWS.CloudTrail
Severity: High         # CAPS in Panther
Tags:
  - AWS
  - Identity & Access Management
Reports:
  MITRE ATT&CK:
    - TA0001:T1078     # tactic:technique
Tests:
  - Name: ...
    ExpectedResult: true
    Log: { ... }
```

→

| Panther field | Scanner field |
|---|---|
| `DisplayName` | `name` |
| `Description` (if present) | `description` |
| `LogTypes: [AWS.CloudTrail]` | `%ingest.source_type="aws:cloudtrail"` |
| `LogTypes: [Okta.SystemLog]` | `%ingest.source_type="okta"` |
| `LogTypes: [GitHub.Audit]` | `%ingest.source_type="github"` |
| `LogTypes: [GSuite.Reports]` | `%ingest.source_type="gsuite"` |
| `Severity: HIGH` | `severity: High` (case-fixed) |
| `Severity: INFO` | `severity: Informational` |
| `Tags: [...]` | (drop or repurpose as freeform tags) |
| `Reports.MITRE ATT&CK: [TA0001:T1078]` | `tags: [tactics.ta0001.initial_access, techniques.t1078.valid_accounts]` |
| `RuleID` | preserve in `description` for traceability |

Always add `source.<slug>` based on `LogTypes`.

## Python function → query_text

This is the hard part. The function takes an event dict and returns a boolean. Common patterns:

### Pattern: single-field equality

```python
def rule(event):
    return event.get("eventName") == "ConsoleLogin"
```

→ `eventName="ConsoleLogin"`

### Pattern: chained guards (short-circuit `and`)

```python
def rule(event):
    if event.get("eventName") != "ConsoleLogin":
        return False
    if deep_get(event, "userIdentity", "type") != "Root":
        return False
    return deep_get(event, "responseElements", "ConsoleLogin") == "Success"
```

→
```scanner
eventName="ConsoleLogin"
userIdentity.type="Root"
responseElements.ConsoleLogin="Success"
```

(All three predicates are AND'd by default.)

### Pattern: `deep_get` for nested fields

`deep_get(event, "a", "b", "c")` is just `event["a"]["b"]["c"]` with null safety. Maps directly to `a.b.c` in Scanner.

### Pattern: `in` / containment

```python
if event.get("eventName") not in ("ConsoleLogin", "AssumeRole"):
    return False
```

→ `eventName: ("ConsoleLogin" "AssumeRole")` (parenthesised list).

### Pattern: regex / substring

```python
import re
if not re.search(r"admin|root", event.get("userIdentity", {}).get("userName", "")):
    return False
```

→ `userIdentity.userName: ("admin" "root")` (token-match; works if `admin` or `root` is a full token).

If the regex is more complex (capture groups, character classes), the translation is no longer 1:1. Options:
- Approximate with token-matches and accept the lower precision.
- Hand off to `/write-vrl` to add a derived field at ingest (e.g., `user.is_privileged`, or `@ecs.user.roles` if that fits) and filter on that. See methodology.md "Field namespace for enrichment output" for choosing the path.

### Pattern: numeric thresholds

```python
if event.get("statusCode") < 400:
    return False
```

→ `statusCode>=400` (Scanner uses `>=`, not `not <`).

### Pattern: helper function calls

Many Panther rules call helpers from `panther_base_helpers` or `aws_rule_context`:

```python
from panther_base_helpers import deep_get
from aws_helpers import is_console_session

def rule(event):
    if not is_console_session(event):
        return False
    return event.get("eventName") == "PassRole"
```

Open the helper — locally at `~/src/panther-analysis/global_helpers/aws_helpers.py` if cloned, otherwise `curl -sSL "https://raw.githubusercontent.com/panther-labs/panther-analysis/main/global_helpers/aws_helpers.py"` — and inline its logic. For `is_console_session`, the implementation is usually:

```python
def is_console_session(event):
    return event.get("userIdentity", {}).get("sessionContext", {}).get("attributes", {}).get("creationDate") and \
           "AWSManagementConsole" in event.get("userAgent", "")
```

→ Scanner equivalent:

```scanner
userIdentity.sessionContext.attributes.creationDate:*
userAgent: "AWSManagementConsole"
```

### Pattern: stateful logic (e.g., `event.history`)

Panther's `dedup` and `alert_context` are stateful — they reference recent events. Scanner doesn't have this exact construct. Equivalents:
- Panther `dedup` → Scanner's `dedup_window_s` + `use_for_dedup: true` on alert_template fields.
- Panther stateful counters (rare) → decompose into 2+ Scanner rules + a correlation rule via `/write-correlation`.

## alert_context → alert_template

```python
def alert_context(event):
    return aws_rule_context(event)
```

`aws_rule_context` typically returns a dict like:

```python
{
    "user_arn": deep_get(event, "userIdentity", "arn"),
    "source_ip": event.get("sourceIPAddress"),
    "event_name": event.get("eventName"),
    "aws_region": event.get("awsRegion"),
}
```

→

```yaml
alert_template:
  info:
    - label: User
      value: "{{results_table.rows[0].userIdentity.arn}}"
      use_for_dedup: true
    - label: Source IP
      value: "{{results_table.rows[0].sourceIPAddress}}"
    - label: Event
      value: "{{results_table.rows[0].eventName}}"
    - label: Region
      value: "{{results_table.rows[0].awsRegion}}"
```

## Tests block → inline tests

Panther tests are Python-dict logs:

```yaml
Tests:
  - Name: Root Console Login
    ExpectedResult: true
    Log:
      eventName: ConsoleLogin
      userIdentity:
        type: Root
      responseElements:
        ConsoleLogin: Success
  - Name: IAM User Login
    ExpectedResult: false
    Log:
      eventName: ConsoleLogin
      userIdentity:
        type: IAMUser
        userName: johndoe
      responseElements:
        ConsoleLogin: Success
```

→ Scanner inline tests:

```yaml
tests:
  - name: Root Console Login fires
    now_timestamp: "2026-05-15T00:03:00.000Z"
    dataset_inline: |
      {"timestamp":"2026-05-15T00:02:30.000Z","%ingest.source_type":"aws:cloudtrail","eventName":"ConsoleLogin","userIdentity":{"type":"Root"},"responseElements":{"ConsoleLogin":"Success"}}
    expected_detection_result: true
  - name: IAM user login does not fire
    now_timestamp: "2026-05-15T00:03:00.000Z"
    dataset_inline: |
      {"timestamp":"2026-05-15T00:02:30.000Z","%ingest.source_type":"aws:cloudtrail","eventName":"ConsoleLogin","userIdentity":{"type":"IAMUser","userName":"johndoe"},"responseElements":{"ConsoleLogin":"Success"}}
    expected_detection_result: false
```

Add the `timestamp` field (Panther test events don't always include it; Scanner requires it).

## When the Python is too complex

Some Panther rules are inscrutable for direct translation — e.g., they call out to external APIs, maintain state in `kv_store`, or do data-shape transforms. In those cases:

1. **Skip and flag.** Tell the user this rule can't be 1:1 migrated and explain why.
2. **Try a simpler approximation.** Often the Python is doing 80% of its work in the first 5 lines; the rest is alert context or polish. A simplified Scanner rule that catches the top-level behaviour may be enough.
3. **Decompose + correlate.** If the Python is doing multi-event temporal logic, break into multiple Scanner rules + a correlation rule.

## Worked example

**Panther source:** `aws_root_console_login.py` + `aws_root_console_login.yml`.

```python
from panther_base_helpers import aws_rule_context, deep_get

def rule(event):
    if event.get("eventName") != "ConsoleLogin":
        return False
    if deep_get(event, "userIdentity", "type") != "Root":
        return False
    return deep_get(event, "responseElements", "ConsoleLogin") == "Success"

def alert_context(event):
    return aws_rule_context(event)
```

```yaml
DisplayName: AWS Root Console Login
LogTypes: [AWS.CloudTrail]
Severity: High
Reports:
  MITRE ATT&CK: [TA0001:T1078, TA0003:T1078]
```

**Scanner translation:**

```yaml
# schema: https://scanner.dev/schema/scanner-detection-rule.v1.json
name: AWS Root Console Login
enabled: Staging
description: |-
  Detects successful AWS console login by the root account. Root logins should
  be exceedingly rare; investigate any occurrence.

  Migrated from Panther rule `AWS.CloudTrail.RootConsoleLogin`.
severity: High
query_text: |-
  %ingest.source_type="aws:cloudtrail"
  eventName="ConsoleLogin"
  userIdentity.type="Root"
  responseElements.ConsoleLogin="Success"
  | stats
      min(@scnr.datetime) as firstTime,
      max(@scnr.datetime) as lastTime,
      count() as eventCount
      by sourceIPAddress, awsRegion, recipientAccountId
time_range_s: 300
run_frequency_s: 60
event_sink_keys:
  - high_severity_alerts
tags:
  - source.cloudtrail
  - tactics.ta0001.initial_access
  - tactics.ta0003.persistence
  - techniques.t1078.valid_accounts
alert_template:
  info:
    - label: Source IP
      value: "{{results_table.rows[0].sourceIPAddress}}"
      use_for_dedup: true
    - label: Account
      value: "{{results_table.rows[0].recipientAccountId}}"
    - label: Region
      value: "{{results_table.rows[0].awsRegion}}"
tests:
  - name: Root console login fires
    now_timestamp: "2026-05-15T00:03:00.000Z"
    dataset_inline: |
      {"timestamp":"2026-05-15T00:02:30.000Z","%ingest.source_type":"aws:cloudtrail","eventName":"ConsoleLogin","userIdentity":{"type":"Root"},"responseElements":{"ConsoleLogin":"Success"},"sourceIPAddress":"203.0.113.5","awsRegion":"us-east-1","recipientAccountId":"123456789012"}
    expected_detection_result: true
  - name: IAM user console login does not fire
    now_timestamp: "2026-05-15T00:03:00.000Z"
    dataset_inline: |
      {"timestamp":"2026-05-15T00:02:30.000Z","%ingest.source_type":"aws:cloudtrail","eventName":"ConsoleLogin","userIdentity":{"type":"IAMUser","userName":"johndoe"},"responseElements":{"ConsoleLogin":"Success"},"sourceIPAddress":"203.0.113.5","awsRegion":"us-east-1","recipientAccountId":"123456789012"}
    expected_detection_result: false
```

Pivot to `sourceIPAddress` rather than `userIdentity.arn`: root logins don't have a useful ARN to group by (it's always the same account-level identifier), so the IP is the more informative key.
