# Scanner OOB detection-rule packs

Scanner publishes pre-built detection-rule packs on GitHub under the `scanner-inc` org, one repo per log source. The user enables a pack at **Detections → Prebuilt Rules** (left sidebar, under *Explore*): select the source tile (1Password, AWS CloudTrail, Okta, …) and Scanner syncs that repository to the team. Already-synced sources show a green check on their tile, so that page doubles as ground truth for which packs are enabled. Synced repos are then listed under **Detections → Synced Repositories**, which is also where an arbitrary (non-Scanner) rules repo gets connected.

This file hardcodes the canonical list (small, stable) so the skill can recommend packs without needing the user to have any pack cloned locally. Each pack is its own GitHub repo at `scanner-inc/detection-rules-<source>`. (Per the no-required-adjacent-repos rule.) If new packs ship, add a row here.

The table can lag the product: **Detections → Prebuilt Rules** is the authoritative list of what's available and what's already synced (each tile links to `…/prebuilt-rules/detection-rules-<source>`, and synced ones carry an added badge). Table last reconciled against that page 2026-08-05. When recommending, say "if you don't see it on the Prebuilt Rules page, tell me and I'll fetch the repo directly" rather than asserting a pack doesn't exist.

## Available packs (as of 2026-05)

| Pack | GitHub URL | Source-type / index slug | Likely MITRE tactic coverage |
|---|---|---|---|
| `detection-rules-1password` | https://github.com/scanner-inc/detection-rules-1password | `1password:audit`, `1password` | credential_access, account_manipulation |
| `detection-rules-atlassian` | https://github.com/scanner-inc/detection-rules-atlassian | `atlassian` (Jira, Confluence) | initial_access, persistence |
| `detection-rules-auth0` | https://github.com/scanner-inc/detection-rules-auth0 | `auth0:audit`, `auth0` | initial_access, credential_access |
| `detection-rules-aws-cloudtrail` | https://github.com/scanner-inc/detection-rules-aws-cloudtrail | `aws:cloudtrail` | broad — defense_evasion, privilege_escalation, persistence, exfiltration, impact |
| `detection-rules-azure` | https://github.com/scanner-inc/detection-rules-azure | `azure:*` (signin, activity, …) | initial_access, credential_access, privilege_escalation |
| `detection-rules-cisco-duo` | https://github.com/scanner-inc/detection-rules-cisco-duo | `cisco-duo`, `duo` | credential_access |
| `detection-rules-cloudflare` | https://github.com/scanner-inc/detection-rules-cloudflare | `cloudflare` | command_and_control, exfiltration |
| `detection-rules-dropbox` | https://github.com/scanner-inc/detection-rules-dropbox | `dropbox` | exfiltration, collection |
| `detection-rules-gcp` | https://github.com/scanner-inc/detection-rules-gcp | `gcp:*` | broad |
| `detection-rules-github` | https://github.com/scanner-inc/detection-rules-github | `github:audit`, `github` | initial_access, persistence (OAuth apps), exfiltration |
| `detection-rules-gsuite` | https://github.com/scanner-inc/detection-rules-gsuite | `gsuite`, `google_workspace` | initial_access, credential_access |
| `detection-rules-microsoft-365` | https://github.com/scanner-inc/detection-rules-microsoft-365 | `m365`, `office365` | credential_access, collection |
| `detection-rules-notion` | https://github.com/scanner-inc/detection-rules-notion | `notion` | collection, exfiltration |
| `detection-rules-okta` | https://github.com/scanner-inc/detection-rules-okta | `okta` | initial_access, credential_access |
| `detection-rules-salesforce` | https://github.com/scanner-inc/detection-rules-salesforce | `salesforce` | exfiltration, collection |
| `detection-rules-sentinelone` | https://github.com/scanner-inc/detection-rules-sentinelone | `sentinelone`, `s1` | execution, persistence, defense_evasion |
| `detection-rules-slack` | https://github.com/scanner-inc/detection-rules-slack | `slack` | collection, exfiltration |
| `detection-rules-snowflake` | https://github.com/scanner-inc/detection-rules-snowflake | `snowflake` | credential_access, exfiltration |
| `detection-rules-tines` | https://github.com/scanner-inc/detection-rules-tines | `tines` | (workflow / orchestration) |
| `detection-rules-windows-process-creation` | https://github.com/scanner-inc/detection-rules-windows-process-creation | `windows`, `sysmon` | execution, defense_evasion, persistence |
| `detection-rules-wiz` | https://github.com/scanner-inc/detection-rules-wiz | `wiz` | (cloud posture) |
| `detection-rules-zoom` | https://github.com/scanner-inc/detection-rules-zoom | `zoom` | initial_access |

## How to recommend a pack

1. Look at the tenant's ingested source-types (from `get_scanner_context.source_types`).
2. For each ingested source, check the table above for a matching pack.
3. Skip packs where the user's rule inventory already shows >0 rules with the matching `source.<slug>` tag (suggests the pack is already enabled or the user has private equivalents).
4. Emit a recommendation per remaining pack with:
   - Pack name + GitHub URL (hardcoded from this table — no local clone needed).
   - The matching source-type and event volume from `get_scanner_context`.
   - UI enable instruction: "Detections → Prebuilt Rules → select the `<Source>` tile to sync the pack. Start in `Staging`."

## Fetching a single OOB rule (without cloning)

If `/tune-detection` needs an OOB rule's YAML to clone-and-tune, fetch raw:

```bash
curl -sSL "https://raw.githubusercontent.com/scanner-inc/detection-rules-<source>/main/rules/<file>.yml"
```

The pack repos all use a `rules/` subdirectory. List available rule files via the GitHub API:

```bash
curl -sSL "https://api.github.com/repos/scanner-inc/detection-rules-<source>/contents/rules" | jq -r '.[].name'
```
