# Migration corpus — index

Six side-by-side worked examples of detection rules migrated from another SIEM into Scanner. Use these as templates when migrating similar rules. Grep the directory names by source × log-source-type to find a close match before drafting from scratch.

## Pattern A — 1:1 translation (no lookups, no decomposition)

These cover the most common case: vendor rule → Scanner rule, query syntax differs but logic is preserved.

| Directory | Source | Log family | Notes |
|---|---|---|---|
| `sigma_cloudtrail_disable_logging/` | Sigma | AWS CloudTrail | Defense-evasion: StopLogging / UpdateTrail / DeleteTrail. Pulls from Sigma's `attack.t1562.008` subtechnique → Scanner's parent technique tag. |
| `chronicle_cloudtrail_guardduty_disabled/` | Chronicle YARA-L 2.0 | AWS CloudTrail | UDM → CloudTrail-native field mapping. `$cloudtrail.target.resource.attribute.labels["enable"]` → `requestParameters.enable`. Outcome block → `alert_template.info`. |
| `panther_cloudtrail_root_console_login/` | Panther Python | AWS CloudTrail | Python function body → Scanner filter clauses. Demonstrates pivoting on `sourceIPAddress` instead of the (unhelpful) root ARN. |
| `splunk_cloudtrail_iam_delete_policy/` | Splunk security_content | AWS CloudTrail | SPL macro unwrapping, `_time` → `@scnr.datetime`, `stats count` → Scanner stats with explicit aliases. |

## Pattern B — VRL-enriched (vendor uses a lookup table)

| Directory | Source | Log family | Notes |
|---|---|---|---|
| `splunk_cloudtrail_corporate_cidr_lookup_example/` | Splunk (synthetic) | AWS CloudTrail | "Alert when an API call comes from outside the corporate CIDR ranges." Splunk uses a CSV lookup table; Scanner enriches at ingest via a VRL transformation that tags the source IP as `corporate` / `non_corporate`. Includes the lookup CSV fixture, the VRL program, and the consuming Scanner rule. |

## Pattern C — Decomposed + correlated

When a single vendor rule does temporal/sequence logic Scanner can't express in one rule.

| Directory | Source | Log family | Notes |
|---|---|---|---|
| `sentinel_kql_decomposed_into_two_plus_correlation/` | Azure Sentinel | Azure Sign-in + AAD audit | "Failed login burst followed by a sign-in from an unusual location for that user." Sentinel uses a compound KQL with `join`; Scanner uses two simpler rules + a correlation rule joining on `userPrincipalName`. Includes both half-rules and the correlation rule, with trade-off notes in the README. |

## Workflow for using the corpus

1. The skill detects the source format and looks for a directory `<source>_<log-source>_*` whose name fragment matches the input rule.
2. If a close match exists, **read** the matching `source.<ext>` and `scanner_rule.yml` to learn the per-source idioms (field mappings, query structure, severity choices, test seed format).
3. Use that template's structure for the new migration; adapt the specific query to the new rule's logic.

When a migration is successful and represents a category not yet covered, propose adding it to the corpus (the user has to make the actual commit).
