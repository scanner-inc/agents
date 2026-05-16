# Azure Sentinel KQL → Scanner translation

Sentinel analytic rules use KQL (Kusto Query Language) — a piped query language with `where`, `summarize`, `extend`, `join`, etc. Translation difficulty is between Sigma (declarative) and Panther (procedural).

**Note on source acquisition:** the Azure-Sentinel repo is large (thousands of analytic rules under `Solutions/*/Analytic Rules/`). If the user wants to migrate a Sentinel rule and doesn't have it cloned, prefer the raw-GitHub-URL input mode — pass the specific analytic-rule YAML URL to `/migrate-detection`, e.g. `https://raw.githubusercontent.com/Azure/Azure-Sentinel/master/Solutions/<solution>/Analytic Rules/<rule>.yaml`.

## Rule file shapes

Sentinel ships rules in two forms — YAML (newer) and JSON ARM (older). Both work; the YAML is easier to read.

### YAML form (preferred for migration)

```yaml
id: <uuid>
name: Suspicious volume of failed logons
description: |
  …
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

### JSON ARM form

```json
{
  "kind": "Scheduled",
  "properties": {
    "displayName": "…",
    "severity": "Medium",
    "query": "SecurityEvent | …",
    "queryFrequency": "PT1H",
    "queryPeriod": "PT1H",
    "triggerOperator": "GreaterThan",
    "triggerThreshold": 10,
    "tactics": ["InitialAccess"],
    "techniques": ["T1078"]
  }
}
```

Same fields, different envelope. The `properties` object maps to the YAML root.

## Top-level mapping

| Sentinel field | Scanner field |
|---|---|
| `name` / `displayName` | `name` |
| `description` | `description` |
| `severity` (Low/Medium/High/Informational) | `severity` (same set; `Informational` → `Informational`) |
| `queryFrequency: 1h` / `PT1H` | `run_frequency_s: 3600` |
| `queryPeriod: 1h` / `PT1H` | `time_range_s: 3600` |
| `triggerOperator: gt`, `triggerThreshold: 10` | `| where <result-column> > 10` |
| `tactics: [InitialAccess]` | look up tactic ID — `tactics.ta0001.initial_access` |
| `relevantTechniques: [T1078]` | `techniques.t1078.valid_accounts` |
| `requiredDataConnectors[].dataTypes` | determines `%ingest.source_type` / `@index` |
| `id` (UUID) | preserve in `description` for traceability |

Always add `source.<slug>` based on the connector / data type.

## requiredDataConnectors → Scanner source mapping

| Sentinel data type | Likely Scanner source |
|---|---|
| `SecurityEvent` (Windows host) | Customer-specific — confirm via `get_top_columns`. Often a Sysmon/WinEventForwarder index. |
| `SigninLogs`, `AADNonInteractiveUserSignInLogs` | `%ingest.source_type="azure:signin"` |
| `AzureActivity` | `%ingest.source_type="azure:activity"` |
| `AWSCloudTrail` | `%ingest.source_type="aws:cloudtrail"` |
| `OfficeActivity` | `%ingest.source_type="m365:audit"` |
| `GoogleCloudSCC` | `%ingest.source_type="gcp:scc"` |

If the connector is one Scanner doesn't ingest in this tenant, tell the user and stop — translating a rule against unavailable data is wasted work.

## KQL → Scanner pipeline

KQL is more expressive than Splunk SPL, but the common idioms translate cleanly.

### Tables → indexes

```kql
SecurityEvent
| where EventID == 4625
```

→

```scanner
%ingest.source_type="<windows-source>"
EventID=4625
```

(Or `@index={UUID|"<source-alias>"}` if the customer needs explicit prod/staging scoping. Without `@index=`, the rule queries all readable indexes by default — source-type filtering alone is usually enough.)

### where → Scanner filter

| KQL | Scanner |
|---|---|
| `| where field == "value"` | `field="value"` |
| `| where field contains "value"` | `field:value` |
| `| where field startswith "value"` | `field:value*` |
| `| where field endswith "value"` | `field:*value` (slow — flag) |
| `| where field !contains "value"` | `not field:value` |
| `| where field in ("a", "b")` | `field: ("a" "b")` |
| `| where field !in ("a", "b")` | `not field: ("a" "b")` |
| `| where field > N` | `field>N` |
| `| where isnotempty(field)` | `field:*` |
| `| where isempty(field)` | `not field:*` |
| `| where field matches regex "pattern"` | No regex. Approximate with token-match or hand off to `/write-vrl` for a derived field. |

### summarize → stats

KQL's `summarize` is Scanner's `stats`:

```kql
| summarize FailedLogons = count() by Account, Computer
```

→

```scanner
| stats count() as FailedLogons by Account, Computer
```

Other aggregation functions map directly: `count`, `dcount` → `countdistinct`, `avg`, `min`, `max`, `sum`. The `by` clause is the same.

### triggerOperator + triggerThreshold → where

Sentinel decouples the aggregation result from the firing threshold via the `triggerOperator` and `triggerThreshold` fields. Scanner inlines this into the query:

```yaml
# Sentinel:
triggerOperator: gt
triggerThreshold: 10
query: |
  SecurityEvent
  | where EventID == 4625
  | summarize FailedLogons = count() by Account
```

→ Scanner:

```scanner
%ingest.source_type="<windows-source>"
EventID=4625
| stats count() as FailedLogons by Account
| where FailedLogons > 10
```

If the `triggerOperator` is something Scanner can't express in a single `where` (e.g., `Equal`, `LessThan` — uncommon for detection rules), translate literally.

### extend → eval

```kql
| extend ParsedUser = tostring(parse_json(UserDetails).Name)
```

→

```scanner
| eval(ParsedUser = …)
```

…but most `extend` operations are doing data shaping that Scanner doesn't need (since Scanner accesses nested fields directly via dotted paths). Often the `extend` line can be dropped, with the downstream `where` rewritten to reference the original field path.

### join → correlation rule (usually)

KQL's `join` against another table is uncommon in detection rules but does appear:

```kql
SecurityEvent
| where EventID == 4625
| join kind=inner (SigninLogs | where ResultType == 50126) on $left.Account == $right.UserPrincipalName
```

This is a cross-source correlation. Decompose:

1. Scanner rule A on `SecurityEvent` (`EventID=4625`).
2. Scanner rule B on `SigninLogs` (`ResultType=50126`).
3. Correlation rule via `/write-correlation` joining on the shared user.

Document the join semantics in the correlation rule's `description`.

### let statements

```kql
let suspiciousIPs = dynamic(["1.2.3.4", "5.6.7.8"]);
SecurityEvent
| where SourceIP in (suspiciousIPs)
```

Inline the literal list into the Scanner filter:

```scanner
%ingest.source_type="<windows-source>"
sourceIPAddress: ("1.2.3.4" "5.6.7.8")
```

If `let` references a watchlist (`_GetWatchlist("name")`), the data must be enriched at Scanner ingest time. Hand off to `/write-vrl` with the watchlist as a CSV; consume the enriched field in the migrated rule.

## tactics + techniques → MITRE tags

Sentinel uses display names for tactics (`InitialAccess`, `Persistence`, `DefenseEvasion`) and T-numbers for techniques (`T1078`, `T1059.001`).

Tactic name → look up the canonical ID:

| Sentinel tactic | Scanner tag |
|---|---|
| `Reconnaissance` | `tactics.ta0043.reconnaissance` |
| `ResourceDevelopment` | `tactics.ta0042.resource_development` |
| `InitialAccess` | `tactics.ta0001.initial_access` |
| `Execution` | `tactics.ta0002.execution` |
| `Persistence` | `tactics.ta0003.persistence` |
| `PrivilegeEscalation` | `tactics.ta0004.privilege_escalation` |
| `DefenseEvasion` | `tactics.ta0005.defense_evasion` |
| `CredentialAccess` | `tactics.ta0006.credential_access` |
| `Discovery` | `tactics.ta0007.discovery` |
| `LateralMovement` | `tactics.ta0008.lateral_movement` |
| `Collection` | `tactics.ta0009.collection` |
| `CommandAndControl` | `tactics.ta0011.command_and_control` |
| `Exfiltration` | `tactics.ta0010.exfiltration` |
| `Impact` | `tactics.ta0040.impact` |

Technique T-numbers → look up the canonical Scanner tag in `mitre_tags.md`. Drop subtechnique suffixes (Scanner's list is parent-technique-level).

## Worked example

**Sentinel YAML source:**

```yaml
id: 12345678-1234-1234-1234-123456789012
name: Failed login burst from single source
description: |
  Detects 10+ failed Azure AD sign-ins from the same source IP in 1 hour.
severity: Medium
requiredDataConnectors:
  - connectorId: AzureActiveDirectory
    dataTypes: [SigninLogs]
queryFrequency: 1h
queryPeriod: 1h
triggerOperator: gt
triggerThreshold: 10
tactics: [CredentialAccess]
relevantTechniques: [T1110]
query: |
  SigninLogs
  | where ResultType != 0
  | summarize FailureCount = count() by IPAddress, UserPrincipalName
  | where FailureCount > 10
```

**Scanner translation:**

```yaml
# schema: https://scanner.dev/schema/scanner-detection-rule.v1.json
name: Failed login burst from single source
enabled: Staging
description: |-
  Detects 10+ failed Azure AD sign-ins from the same source IP within 1 hour —
  brute-force or credential-stuffing indicator.

  Migrated from Azure Sentinel rule `12345678-1234-1234-1234-123456789012`.
severity: Medium
query_text: |-
  %ingest.source_type="azure:signin"
  not ResultType="0"
  | stats count() as FailureCount by IPAddress, UserPrincipalName
  | where FailureCount > 10
time_range_s: 3600
run_frequency_s: 3600
event_sink_keys:
  - medium_severity_alerts
tags:
  - source.azure_signin
  - tactics.ta0006.credential_access
  - techniques.t1110.brute_force
alert_template:
  info:
    - label: Source IP
      value: "{{results_table.rows[0].IPAddress}}"
      use_for_dedup: true
    - label: User
      value: "{{results_table.rows[0].UserPrincipalName}}"
    - label: Failures
      value: "{{results_table.rows[0].FailureCount}}"
tests:
  - name: Fires on 11 failures from same IP
    now_timestamp: "2026-05-15T01:01:00.000Z"
    dataset_inline: |
      (11 events with timestamp in the window, same IPAddress + UserPrincipalName, ResultType not 0)
    expected_detection_result: true
  - name: Does not fire on 5 failures
    now_timestamp: "2026-05-15T01:01:00.000Z"
    dataset_inline: |
      (5 events with same shape, below threshold)
    expected_detection_result: false
```

Translation notes:
- `ResultType != 0` (KQL) → `not ResultType="0"` (Scanner). Scanner's `!=` isn't supported; use `not field=value` form.
- `queryFrequency: 1h` and `queryPeriod: 1h` both map to `run_frequency_s: 3600` and `time_range_s: 3600`. Sentinel separates them but typically sets equal.
- KQL `summarize FailureCount = count() by ...` is Scanner's `| stats count() as FailureCount by ...` — same shape, syntax differs.
- The threshold (`triggerThreshold: 10`) is moved from rule metadata into the query body as `| where FailureCount > 10`.
