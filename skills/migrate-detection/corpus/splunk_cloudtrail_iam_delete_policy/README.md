# Splunk → Scanner: AWS IAM Delete Policy

**Source:** [`source.yml`](./source.yml) — Splunk `security_content` rule `ec3a9362-92fe-11eb-99d0-acde48001122` from `~/src/security_content/detections/cloud/aws_iam_delete_policy.yml`.

**Target:** [`scanner_rule.yml`](./scanner_rule.yml) — hand-crafted Scanner equivalent (no exact OOB match exists in `detection-rules-aws-cloudtrail`).

## What changed in translation

| Splunk SPL | Scanner |
|---|---|
| `` `cloudtrail` `` macro | `@scnr.source_type="aws:cloudtrail"` (the macro expands to `index=cloudtrail` in Splunk) |
| `eventName=DeletePolicy` | `eventName=DeletePolicy` (same) |
| `(userAgent!=*.amazonaws.com)` (Splunk: "user agent doesn't contain `.amazonaws.com`") | `not userAgent: ".amazonaws.com"` — Scanner's `:` is token-match and `.` is a token boundary, so `amazonaws` appears as a complete token in matching agents |
| `| stats count min(_time) as firstTime max(_time) as lastTime values(requestParameters.policyArn) as policyArn by src eventName eventSource aws_account_id errorCode errorMessage userAgent eventID awsRegion userIdentity.principalId userIdentity.arn` | `| stats min(@scnr.datetime) as firstTime, max(@scnr.datetime) as lastTime, count() as eventCount, countdistinct(requestParameters.policyArn) as distinctPolicies by sourceIPAddress, eventName, …` |
| Splunk's `values(...)` (collect distinct values into a list) | `countdistinct(...)` — Scanner doesn't have a 1:1 equivalent; counting distinct values is the closest |
| `_time` | `@scnr.datetime` |
| `src` | `sourceIPAddress` (Splunk CloudTrail data-model alias) |
| `aws_account_id` | `recipientAccountId` |
| `risk_score: 10` | `severity: Medium` (low-ish risk score, but `DeletePolicy` warrants Medium, not Low) |
| `mitre_attack_id: [T1098]` | `tags: [techniques.t1098.account_manipulation]` |
| `` `aws_iam_delete_policy_filter` `` tail macro | (dropped — empty tuning macro in security_content; user can add their own `and not …` clauses if needed via `tune-detection`) |
| `kill_chain_phases: [Actions on Objectives]` | `tags: [tactics.ta0005.defense_evasion]` — DeletePolicy is more accurately a defense-evasion move than impact |

## Key idioms to learn from this example

- **Splunk macro unwrapping.** The `` `name` `` syntax invokes Splunk macros that live in `~/src/security_content/macros/`. Unwrap them to their underlying SPL before translating. Common ones:
  - `` `cloudtrail` `` → `index=cloudtrail` → Scanner `@scnr.source_type="aws:cloudtrail"`.
  - `` `security_content_ctime(field)` `` → format timestamp; Scanner emits ISO timestamps natively so drop.
  - `` `<rulename>_filter` `` → tail tuning macro; usually empty by default. Drop on initial migration.
- **Splunk's `!=*.value` is leading-wildcard not-contains.** It means "the user agent does NOT contain `.value` as a substring." Scanner's `not userAgent: ".value"` does the same thing when `.` is a token boundary (which it almost always is in user-agent strings).
- **CloudTrail field aliases.** Splunk's `Add-on for AWS` aliases raw CloudTrail fields: `src` → `sourceIPAddress`, `user` → `userIdentity.userName`, `aws_account_id` → `recipientAccountId`. Scanner has the raw paths.
- **`values()` → `countdistinct()`.** Splunk's `values(field)` collects distinct values into an array; Scanner's `countdistinct(field)` counts them. You lose the actual values but keep the cardinality; usually that's enough for an alert summary.
- **Severity mapping by risk_score.** Splunk's `risk_score` is 0–100; this rule has `risk_score: 10`, which is Low — but the *behaviour* (deleting an IAM policy) is a Medium-confidence indicator. Map by behaviour, not just by the source rule's nominal score, and document the choice.

## What this corpus entry doesn't cover

- Splunk security_content rules with linked test datasets (via `tags.dataset:` URLs). Many security_content rules ship JSON test fixtures on the splunk/attack_data GitHub. The skill can `curl` these and translate them into `dataset_inline` JSONL — see methodology Phase 8.
- Rules that use `tstats` (Splunk's accelerated data model search). Translation is similar to plain `stats` but the data-model field aliases are different. For most cases the result is the same; for performance-sensitive rules, validate via MCP backtest that the Scanner query is fast enough.
