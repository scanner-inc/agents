# Sigma → Scanner: AWS CloudTrail disable logging

**Source:** [`source.yml`](./source.yml) — Sigma rule `4db60cc0-36fb-42b7-9b58-a5b53019fb74` from the upstream `SigmaHQ/sigma` repo (`rules/cloud/aws/cloudtrail/aws_cloudtrail_disable_logging.yml`).

**Target:** [`scanner_rule.yml`](./scanner_rule.yml) — Scanner OOB rule from the `scanner-inc/detection-rules-aws-cloudtrail` pack.

## What changed in translation

| Sigma | Scanner |
|---|---|
| `title: AWS CloudTrail Important Change` | `name: AWS CloudTrail Important Change` |
| `level: medium` | `severity: Medium` + `event_sink_keys: [medium_severity_alerts]` |
| `logsource: { product: aws, service: cloudtrail }` | `@scnr.source_type="aws:cloudtrail"` |
| `tags: [attack.defense-evasion, attack.t1562.008]` | `tags: [tactics.ta0005.defense_evasion, techniques.t1562.impair_defenses, source.cloudtrail]` — subtechnique number stripped (`.008` → parent technique) |
| `detection.selection_source.eventName: [StopLogging, UpdateTrail, DeleteTrail]` | `eventName=(StopLogging UpdateTrail DeleteTrail)` — Scanner's parenthesised-list form |
| `condition: selection_source` | (no extra clause needed) |
| (none) | Added `| stats … by userIdentity.arn, eventSource, eventName, awsRegion` so the rule fires once per principal/event rather than per raw event. |
| (none) | Added `enabled: Staging` — new rules always start in staging. |

## Key idioms to learn from this example

- **Parenthesised list for OR'd values:** `eventName=(StopLogging UpdateTrail DeleteTrail)` — never bare `OR`.
- **Subtechnique tag pruning:** Sigma's `attack.t1562.008` (impair-defenses → disable-cloud-logs subtechnique) maps to Scanner's `techniques.t1562.impair_defenses` parent technique. Scanner's canonical tag list (`mitre_tags.md`) is parent-technique-level.
- **Aggregation added:** Sigma doesn't aggregate by default; Scanner rules nearly always want a `| stats … by …` clause grouping by an entity (the ARN here). Without it, the rule could fire once per CloudTrail event during a noisy admin session.
- **Source-tag convention:** Always include `source.cloudtrail` (or the analogous source slug) so coverage matrices attribute the rule to a log family.

## What this corpus entry doesn't cover

- The Sigma original has `falsepositives: [Valid change in a Trail]` — folded into the Scanner `description` as a `## False Positives` block. Worth doing for every migration so reviewers see the assumed FP scenarios.
- The Sigma original has no test fixtures; the Scanner version here also doesn't (the OOB pack version doesn't add them either). For a new migration of this same rule into a private repo, seed `tests:` from real events sampled via MCP.
