# Source rule repositories — layouts and idioms (informational)

This file documents how each supported source-SIEM organises its rule files and the per-source content idioms the model will encounter. **It is reference material, not a runtime dependency.** The skill does **not** require any of these repos to be cloned locally — see `methodology.md` Phase 1 for the supported input modes (pasted content, file path, dir path, raw GitHub URL).

When IS this file useful?
- The user pastes a rule and asks "what format is this?" → match the structure against the per-source sections below.
- The user has cloned one of these repos and wants to point at a specific path → the layouts below help with discoverability (e.g., "Sigma CloudTrail rules live in `rules/cloud/aws/cloudtrail/`").
- The model needs to confirm a fingerprint (Splunk macros, Sigma `logsource:` blocks, YARA-L `meta:` block, etc.) — see the per-source examples.

The upstream public GitHub URLs (you can also `curl` raw files directly from these):
- Splunk security_content: <https://github.com/splunk/security_content>
- Sigma: <https://github.com/SigmaHQ/sigma>
- Chronicle / Google SecOps community rules: <https://github.com/chronicle/detection-rules>
- Panther: <https://github.com/panther-labs/panther-analysis>
- Azure Sentinel: <https://github.com/Azure/Azure-Sentinel>
- Elastic: <https://github.com/elastic/detection-rules>

## Splunk security_content

**Typical local clone path** (only relevant if the user has cloned it): `~/src/security_content/`

**Layout:**
```
security_content/
├── detections/
│   ├── cloud/              # AWS, GCP, Azure rules — most CloudTrail rules live here
│   ├── endpoint/           # Windows / Linux / macOS host rules
│   ├── network/            # Network IDS rules
│   ├── web/                # Web traffic rules
│   ├── application/
│   └── deprecated/
├── stories/                # Composite "analytic stories" grouping multiple detections
├── data/                   # Sample event datasets
└── docs/
```

**Filename convention:** `<source>_<verb>_<object>.yml`. Examples: `aws_iam_delete_policy.yml`, `aws_console_login_failure_for_root_account.yml`.

**Per-rule file shape** (key fields the skill reads):

```yaml
name: AWS IAM Delete Policy
id: ec3a9362-92fe-11eb-99d0-acde48001122
search: '`cloudtrail` eventName=DeletePolicy (userAgent!=*.amazonaws.com) | stats count …'
type: Hunting          # or "TTP", "Anomaly", "Correlation"
tags:
  mitre_attack_id: [T1098]
  risk_score: 10
  confidence: 50
  impact: 20
  analytic_story: [AWS IAM Privilege Escalation]
how_to_implement: …
known_false_positives: …
references: [URLs]
```

The `search:` field is SPL with Splunk-specific macros (`` `cloudtrail` `` expands to `index=cloudtrail`; ``  `security_content_ctime(firstTime)` `` formats a timestamp). The skill must unwrap these macros — Splunk's `search.conf` and `macros.conf` define them, but for the purpose of migration, treat `` `cloudtrail` `` as `%ingest.source_type="aws:cloudtrail"`.

## Sigma

**Typical local clone path** (only relevant if the user has cloned it): `~/src/sigma/`

**Layout:**
```
sigma/
├── rules/
│   ├── cloud/
│   │   ├── aws/
│   │   │   ├── cloudtrail/         # AWS CloudTrail rules
│   │   │   ├── waf/
│   │   │   └── …
│   │   ├── gcp/
│   │   ├── azure/
│   │   └── m365/
│   ├── windows/
│   ├── linux/
│   ├── macos/
│   ├── network/
│   ├── web/
│   └── …
├── rules-emerging-threats/        # Newer, less battle-tested
├── rules-threat-hunting/
├── rules-compliance/
└── tests/
```

**Per-rule file shape:**

```yaml
title: AWS CloudTrail Important Change
id: 4db60cc0-36fb-42b7-9b58-a5b53019fb74
status: stable         # or test, experimental, deprecated, unsupported
description: …
references: [URLs]
author: …
date: 2020-01-21
modified: 2022-10-09
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
  filter:
    user_arn|contains: 'role/automation-'
  condition: selection_source and not filter
falsepositives: …
level: medium
```

Key Sigma idioms:
- `selection_*` blocks define filter clauses. `condition:` combines them with `and` / `or` / `not`.
- `|contains` / `|startswith` / `|endswith` modifiers on field names control match semantics.
- `attack.t1562.008` → MITRE technique `T1562.008` (subtechnique 8 of `T1562`). Scanner's tag list is parent-technique-level, so map to `techniques.t1562.impair_defenses`.

## Chronicle / SecOps YARA-L 2.0

**Typical local clone path** (only relevant if the user has cloned it): `~/src/chronicle/detection-rules/rules/`

**Layout:**
```
chronicle/detection-rules/rules/
├── community/
│   ├── aws/
│   │   └── cloudtrail/             # *.yaral files
│   ├── azure/
│   ├── gcp/
│   ├── windows/
│   └── …
├── _deprecated/
└── tools/                          # YARA-L test harnesses
```

**Per-rule file shape:**

```yaral
rule aws_guardduty_disabled {
  meta:
    author = "Google Cloud Security"
    description = "Detects when a GuardDuty Detector is disabled or suspended."
    rule_id = "mr_22495d55-…"
    rule_name = "AWS GuardDuty Disabled"
    mitre_attack_tactic = "Defense Evasion"
    mitre_attack_technique = "Impair Defenses"
    severity = "High"
    data_source = "AWS CloudTrail"

  events:
    $cloudtrail.metadata.vendor_name = "AMAZON"
    $cloudtrail.metadata.product_event_type = "DeleteDetector"
    $cloudtrail.security_result.action = "ALLOW"

  outcome:
    $risk_score = max(75)
    $principal_ip = array_distinct($cloudtrail.principal.ip)
    $principal_user_display_name = $cloudtrail.principal.user.user_display_name

  condition:
    $cloudtrail
}
```

Key YARA-L idioms:
- Event variables: `$cloudtrail`, `$dnslog`. The variable holds a stream of events; field references are `$cloudtrail.metadata.*`.
- **UDM field paths** — Chronicle normalises to its own Unified Data Model (`metadata.vendor_name`, `principal.user.email`, `target.resource.name`). The translation cheat-sheet maps UDM → CloudTrail-native (`userIdentity.userName`, `requestParameters.*`).
- `outcome:` block defines fields to surface on detection — translate to Scanner's `alert_template.info`.
- `condition: $cloudtrail` (no temporal logic) → simple Scanner filter. `condition: $cloudtrail and #count > 5` → Scanner `| stats count() | where @q.count > 5`.

## Panther

**Typical local clone path** (only relevant if the user has cloned it): `~/src/panther-analysis/`

**Layout:**
```
panther-analysis/
├── rules/                          # behavioural rules (alert on events)
│   ├── aws_cloudtrail_rules/       # *.py + paired *.yml metadata
│   ├── okta_rules/
│   ├── github_rules/
│   ├── gsuite_rules/
│   └── …
├── policies/                       # posture rules (alert on resource state)
│   └── aws_cloudtrail_policies/
├── data_models/                    # event field normalisers
├── global_helpers/                 # shared Python utilities
└── lookup_tables/
```

**Per-rule shape:**

`aws_root_console_login.py`:
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

`aws_root_console_login.yml` (paired metadata):
```yaml
AnalysisType: rule
RuleID: AWS.CloudTrail.RootConsoleLogin
DisplayName: AWS CloudTrail Root Console Login
LogTypes:
  - AWS.CloudTrail
Severity: High
Tags:
  - AWS
  - Identity & Access Management
Reports:
  MITRE ATT&CK:
    - TA0001:T1078
Tests:
  - Name: Root Console Login
    ExpectedResult: true
    Log: { eventName: ConsoleLogin, userIdentity: { type: Root }, responseElements: { ConsoleLogin: Success } }
```

Key Panther idioms:
- `rule(event)` returns boolean: `True` fires, `False` doesn't.
- `deep_get(event, "a", "b", "c")` = nested field access with null safety.
- `LogTypes:` maps to Scanner source-type.
- `Reports.MITRE ATT&CK: [TA0001:T1078]` → tactic + technique pair.
- `Tests:` array of `{Name, ExpectedResult, Log}` — `Log` is a Python dict; translate to JSONL.

Panther translation is harder than Sigma/YARA-L because the logic is Python code, not declarative. The model reasons about the function body and emits the equivalent Scanner filter clauses. Multi-condition Python rules sometimes need decomposition into multiple Scanner rules + a correlation.

## Azure Sentinel

**Typical local clone path** (only relevant if the user has cloned it): `~/src/Azure-Sentinel/`

**Note on the Azure-Sentinel repo:** the public repo is large. If the user wants to migrate a Sentinel rule and doesn't have it cloned, prefer the raw-GitHub-URL input mode — point at the specific analytic-rule YAML they want, rather than asking them to clone the whole tree.

**Expected layout once populated:**
```
Azure-Sentinel/
├── Solutions/
│   ├── <Solution Name>/
│   │   ├── Analytic Rules/       # *.yaml KQL-based scheduled rules
│   │   └── …
│   └── …
├── Detections/                   # Older / standalone detections
└── Hunting Queries/
```

**Per-rule file shape (YAML form):**
```yaml
id: <uuid>
name: Suspicious volume of failed logons
description: …
severity: Medium
requiredDataConnectors:
  - connectorId: SecurityEvents
    dataTypes: [SecurityEvent]
queryFrequency: 1h
queryPeriod: 1h
triggerOperator: gt
triggerThreshold: 10
tactics: [InitialAccess]
relevantTechniques: [T1078]
query: |
  SecurityEvent
  | where EventID == 4625
  | summarize FailedLogons = count() by Account, Computer
  | where FailedLogons > 10
```

Key idioms:
- `query` is KQL.
- `tactics:` (display names — map back to canonical IDs) and `relevantTechniques:` (T-numbers).
- `triggerThreshold:` corresponds to Scanner's `| where @q.count > N`.

## Elastic

**Typical local clone path** (only relevant if the user has cloned it): `~/src/detection-rules/`

**Layout:**
```
detection-rules/
├── rules/
│   ├── aws/
│   ├── azure/
│   ├── windows/
│   ├── linux/
│   └── …
├── tests/
└── etc/
```

Each rule is a TOML or JSON file. Key fields:

```toml
[metadata]
creation_date = "2020-09-07"
maturity = "production"
min_stack_version = "8.3.0"

[rule]
author = ["Elastic"]
description = "..."
language = "kuery"          # or "eql"
license = "Elastic License v2"
name = "AWS IAM User Creation"
note = "..."
references = ["..."]
risk_score = 47              # 0–100, maps to Scanner severity
rule_id = "<uuid>"
severity = "medium"          # vendor's own severity string
tags = ["Domain: Cloud", "Data Source: AWS", "Use Case: Identity and Access Audit"]
timestamp_override = "event.ingested"
type = "query"               # or "eql", "threshold", "threat_match"

query = '''
event.dataset:aws.cloudtrail and event.provider:iam.amazonaws.com and event.action:CreateUser
'''

[[rule.threat]]
framework = "MITRE ATT&CK"
[[rule.threat.tactic]]
id = "TA0003"
name = "Persistence"
reference = "https://attack.mitre.org/tactics/TA0003/"
[[rule.threat.technique]]
id = "T1078"
name = "Valid Accounts"
reference = "https://attack.mitre.org/techniques/T1078/"
```

`query` is KQL when `language = "kuery"`, or EQL when `language = "eql"`. ECS field paths everywhere (`event.action`, `user.name`, `source.ip`).

If the source data isn't already ECS-shaped in Scanner, the migration needs a VRL transformation step to normalise CloudTrail → ECS first (or rewrite the query to use CloudTrail-native paths). See `translation_elastic.md`.
