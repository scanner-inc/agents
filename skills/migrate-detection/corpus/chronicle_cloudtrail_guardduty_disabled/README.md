# Chronicle YARA-L 2.0 → Scanner: AWS GuardDuty disabled

**Source:** [`source.yaral`](./source.yaral) — Chronicle community rule `mr_22495d55-…` from `~/src/chronicle/detection-rules/rules/community/aws/cloudtrail/aws_guardduty_disabled.yaral`.

**Target:** [`scanner_rule.yml`](./scanner_rule.yml) — Scanner OOB rule `AWS GuardDuty detector deleted` from `scanner-inc/detection-rules-aws-cloudtrail`.

## What changed in translation

| YARA-L | Scanner |
|---|---|
| `rule aws_guardduty_disabled { meta: rule_name = "AWS GuardDuty Disabled" }` | `name: AWS GuardDuty detector deleted` |
| `meta.severity = "High"` | `severity: High` + `event_sink_keys: [high_severity_alerts]` |
| `meta.mitre_attack_technique_id = "T1562"` | `tags: [techniques.t1562.impair_defenses]` |
| `meta.mitre_attack_tactic = "Defense Evasion"` | `tags: [tactics.ta0005.defense_evasion]` |
| `events: $cloudtrail.metadata.vendor_name = "AMAZON"` etc. | `@scnr.source_type:"aws:cloudtrail"` (the vendor + product UDM fields collapse into the Scanner source-type) |
| `$cloudtrail.metadata.product_event_type = "DeleteDetector"` | `eventName:DeleteDetector` |
| `$cloudtrail.metadata.product_event_type = "UpdateDetector" and $cloudtrail.target.resource.attribute.labels["enable"] = "false"` | The OOB rule simplifies to *just* `DeleteDetector`. A faithful migration of the original's full logic would be: `eventName=(DeleteDetector UpdateDetector)` + a more specific clause for the `enable=false` case (see "Faithful version" below). |
| `$cloudtrail.security_result.action = "ALLOW"` | `not errorCode:*` (Scanner idiom for "non-failed CloudTrail event") |
| `outcome: $principal_user_display_name = $cloudtrail.principal.user.user_display_name` etc. | `alert_template.info` with `{{results_table.rows[0].*}}` template values |
| `condition: $cloudtrail` | (no extra clause) |

## Key idioms to learn from this example

- **UDM → source-native field translation.** Chronicle normalises to UDM (`$cloudtrail.metadata.product_event_type`, `$cloudtrail.target.resource.attribute.labels["enable"]`); Scanner usually has raw CloudTrail field paths (`eventName`, `requestParameters.enable`). The translation cheat-sheet in `translation_chronicle.md` documents these mappings.
- **`security_result.action = "ALLOW"` → `not errorCode:*`.** Chronicle has an explicit ALLOW/DENY field; AWS CloudTrail doesn't — failed CloudTrail events instead populate `errorCode` and `errorMessage`. The idiom `not errorCode:*` filters to "field absent" = "no error" = "the call succeeded".
- **`outcome:` → `alert_template.info`.** YARA-L's outcome block surfaces values on the detection event. Scanner expresses the same thing in `alert_template.info[].value` via `{{results_table.rows[0].<col>}}` templating.
- **Simplification trade-off.** The Scanner OOB version omits the `UpdateDetector` branch that the Chronicle original includes. This is a design choice — the OOB pack prefers fewer false positives over completeness. A faithful migration into the user's private repo can re-include it.

## Faithful version (full original logic)

If you want the migrated rule to cover both `DeleteDetector` and `UpdateDetector enable=false`:

```scanner
@scnr.source_type="aws:cloudtrail"
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
```

The OOB rule trades that completeness for simplicity. When migrating, ask the user which they want.

## What this corpus entry doesn't cover

- GeoIP enrichment. The Chronicle original surfaces `$cloudtrail.principal.ip_geo_artifact.location.country_or_region` in its outcome — Scanner can do this only if a GeoIP MMDB has been wired up via `/write-vrl`. If the user wants the country, the migration produces a VRL hand-off (see the `splunk_cloudtrail_corporate_cidr_lookup_example/` corpus entry for the enrichment pattern).
- The `array_distinct($cloudtrail.principal.ip)` aggregation. Scanner can express it with `stats countdistinct(sourceIPAddress) as distinctIPs by ...`, but the OOB version doesn't.
