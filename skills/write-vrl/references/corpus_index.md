# ECS transform corpus — quick index

These files in `../corpus/` are worked VRL examples for Scanner — most are production transforms Scanner uses to normalize popular log sources to ECS; a couple are enrichment / non-ECS-source examples. They are the canonical reference for Scanner VRL style, the `@ecs` target convention, and the kinds of fields worth mapping for each source family.

When the user asks for a transform that touches one of these sources — or anything structurally similar — **read the matching file before drafting**. The existing file shows what's already covered, the field nesting in the raw payload, and the chosen ECS targets.

| Source | File | What it covers |
|---|---|---|
| AWS CloudTrail | `aws_cloudtrail_to_ecs.vrl` | event.outcome from errorCode, cloud.{provider,region,account,service}, user identity ARN/userName fallback |
| AWS CloudFront | `aws_cloudfront_to_ecs.vrl` | HTTP access logs — request method, URL, status, bytes, source IP, user-agent |
| Azure Audit | `azure_audit_to_ecs.vrl` | Sign-in / audit events — operationName -> event.action, identity, IP |
| GCP Audit | `gcp_audit_to_ecs.vrl` | protoPayload.* -> event/user/source, methodName -> event.action |
| Microsoft 365 | `microsoft365_to_ecs.vrl` | Office activity — UserId, Operation, ClientIP |
| Google Workspace | `gsuite_to_ecs.vrl` | Admin/audit events — actor.email, ipAddress, eventName |
| Okta | `okta_to_ecs.vrl` | Auth events — eventType, outcome.result, actor/client/debugContext; handles `.detail` envelope |
| Auth0 | `auth0_to_ecs.vrl` | Tenant logs — type -> event.action, user_id/user_name, ip, user_agent |
| Cisco Duo | `cisco_duo_to_ecs.vrl` | MFA events — short, minimal mapping |
| Snowflake | `snowflake_to_ecs.vrl` | Login/query events |
| Slack | `slack_to_ecs.vrl` | Audit logs — actor.user, action, entity, context.ip_address |
| GitHub | `github_to_ecs.vrl` | Audit log — action, actor/actor_id, org, request_id, user_agent |
| SentinelOne Activities | `sentinelone_activities_to_ecs.vrl` | EDR activity events — agentDetectionInfo, threatInfo |
| SentinelOne Threats | `sentinelone_threats_to_ecs.vrl` | EDR detections — file hashes, process, host OS |
| Windows Events | `windows_to_ecs.vrl` | Event.EventData.Data.* — EventID, ProcessName, SubjectUserName, IpAddress |
| AWS ECS container logs | `aws_ecs_to_ecs.vrl` | App stdout from containers — parse-ARN-with-regex pattern, quoted-path access for flat dotted keys, container/orchestrator fields |
| IP classification enrichment | `ip_classification_enrichment.vrl` | Post-normalization enrichment — `find_enrichment_table_records` + `for_each` + `ip_cidr_contains` first-match pattern; depends on a `ip_classification` lookup table (`cidr,classification` CSV) |
| IPInfo Lite GeoIP enrichment | `ipinfo_geoip_enrichment.vrl` | Post-normalization enrichment — `get_enrichment_table_record` against an **MMDB** table backed by IPInfo Lite. Writes ECS-compliant `@ecs.source.geo.{country_iso_code,country_name,continent_code,continent_name}` and `@ecs.source.as.{number,organization.name}`. Demonstrates ASN string parsing (`"AS15169"` → `15169`) and skipping blank record fields. |

## How to use the corpus

**If the user names one of these sources directly:** open the matching file. If they want to add a new field mapping, append it in the matching section (user / source / http / etc.) and submit a minimal diff.

**If the user names a source not in this list:** find the structurally closest one and use it as a starting point. For example:
- AWS service logs not yet covered → start from `aws_cloudtrail_to_ecs.vrl`
- Containerized application stdout logs → start from `aws_ecs_to_ecs.vrl`
- Any IdP or SaaS audit log → start from `okta_to_ecs.vrl` or `auth0_to_ecs.vrl`
- EDR / endpoint telemetry → start from a `sentinelone_*` file
- Generic SaaS audit (action + actor + IP) → start from `github_to_ecs.vrl` or `slack_to_ecs.vrl`
- Cloud audit on a new provider → start from `gcp_audit_to_ecs.vrl` or `azure_audit_to_ecs.vrl`
- An enrichment step that runs after a source-specific ECS transform → start from `ip_classification_enrichment.vrl` (CSV table, multi-record filter via `find_enrichment_table_records`) or `ipinfo_geoip_enrichment.vrl` (MMDB table, single-record key lookup via `get_enrichment_table_record`)

**Patterns to lift verbatim:**
- The `is_nullish` guard before assigning every optional field
- Section comments (`# User fields`, `# Source fields`) — match the existing grouping
- Closing the program with a bare `.` on its own line
- Constant fields where the source implies them (`.@ecs.cloud.provider = "aws"`, `.@ecs.service.name = "sentinelone"`)
- The `.detail` envelope unwrap from `okta_to_ecs.vrl` for sources that sometimes nest the event one level deeper
