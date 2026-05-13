# Threat hunting workflow: setup

## Prerequisites

* n8n instance.
* Anthropic API key.
* Scanner account with MCP access.
* An [AlienVault OTX](https://otx.alienvault.com/) API key (free).
* An [abuse.ch](https://auth.abuse.ch/) auth key (free). Used for the ThreatFox API.
* Slack workspace connected to n8n.

## Credentials to create in n8n

Create these credentials in n8n's **Credentials** UI. Names must match what the workflow references.

1. **Anthropic account** (type: Anthropic API)
   * API Key: your Anthropic key.

2. **Scanner API/MCP Bearer Auth account** (type: HTTP Bearer Auth)
   * Bearer Token: your Scanner API key.

3. **Slack account** (type: Slack API or OAuth2)
   * Follow n8n's prompts to connect your workspace.

4. **OTX Header Auth** (type: HTTP Header Auth)
   * Name: `X-OTX-API-KEY`
   * Value: your AlienVault OTX API key.

5. **Threatfox Abuse.ch Header Credential** (type: HTTP Header Auth)
   * Name: `Auth-Key`
   * Value: your abuse.ch auth key. Used for the ThreatFox endpoint.

## Import the workflow

1. In n8n, **Workflows** → **Import from File**, select `workflow.json`.
2. Open each node and verify:
   * **Schedule Trigger**: cron is `0 */6 * * *` (every 6 hours). Adjust if you want a different cadence.
   * **CISA KEV**: URL is `https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json`. No auth required.
   * **Extract Top KEV**: Code node that sorts by `dateAdded` and keeps the 5 most recent entries.
   * **Anthropic Chat Model**: credential `Anthropic account`. Model `claude-opus-4-7`.
   * **Scanner MCP**: endpoint is your tenant's MCP URL (replace `mcp.your-env.scanner.dev`). Credential `Scanner API/MCP Bearer Auth account`.
   * **ThreatFox Search**: credential `Threatfox Abuse.ch Header Credential`.
   * **OTX Pulse Search**: credential `OTX Header Auth`.
   * **Feodo Tracker**: no auth; public JSON endpoint.
   * **Threat Hunt Agent**: system message field contains the full body of `prompts/threat-hunting-agent.md`. Paste it if the import did not populate it.
   * **Split Output**: Code node that parses the agent's final response into a Slack portion and an optional Jira block. Leave the JavaScript as-is.
   * **Send a message**: channel ID is your threat hunting Slack channel.
   * **Create Jira?** and **Create Jira Issue**: leave alone unless you want Jira ticket creation — see the next section.

## Optional: enable Jira ticket creation

Slack delivery is the default. The **Create Jira Issue** node ships disabled, so out of the box the workflow only posts to Slack. Skip this section if you do not use Jira.

When enabled, the agent will request a Jira ticket only when the hunt result is **🔴 EVIDENCE OF COMPROMISE** or **🟡 INCONCLUSIVE**. **🟢 NO EVIDENCE FOUND** runs stay Slack-only. This means on most clean weeks the Jira branch is silent; tickets only appear when there is a real lead to chase.

To enable:

1. Create a **Jira SW Cloud account** credential (type: Jira Software Cloud API) in the n8n Credentials UI. Domain, email, API token. n8n's Jira docs: <https://docs.n8n.io/integrations/builtin/credentials/jira/>.
2. Open the **Create Jira Issue** node → right-click → **Activate** (or untick "Disable").
3. In the same node:
   * Set **Project** to your Jira project key (replace `REPLACE_WITH_JIRA_PROJECT_KEY`).
   * Confirm **Issue Type** (default `Task`).
   * Confirm the **Additional Fields** mappings — Description binds to `{{ $json.jira_description_wiki }}`, Priority to `{{ $json.jira_priority }}`, Labels to `{{ $json.jira_labels }}`. The priority value the agent emits is `High` (compromise) or `Medium` (inconclusive); make sure your Jira project has those priority names (or remap in the node).
4. Activate the workflow. The next 🔴 or 🟡 hunt result will produce both a Slack post and a Jira ticket.

If your Jira instance is self-hosted (Server / Data Center) rather than Cloud, swap the credential to "Jira Server API" and adjust the node accordingly.

## Test

1. Activate the workflow.
2. Click **Execute workflow** in the n8n UI to run a hunt immediately (does not wait for the cron).
3. Watch the execution. Expected order: HTTP Request (KEV) → Code (top 5) → AI Agent (loops over Scanner MCP + threat intel tools for several minutes) → Slack.
4. Confirm the Slack message arrived and formatting renders cleanly.

## Scheduling notes

* `0 */6 * * *` = every 6 hours starting at 00:00 UTC. For a 4x daily cadence aligned to US business hours, try `0 6,12,18,0 * * *` or similar.
* If you prefer daily (once per day), use `0 10 * * *` (10:00 UTC). Less fresh intel coverage, but less Slack noise.

## Tuning knobs

* **Number of pre-fetched KEV entries**: the Code node keeps the top 5. Bump to 10 in the node's JavaScript if you want the agent to consider more candidates per run.
* **Agent max iterations**: an AI Agent node option. Cap tool calls per run if you see runaway behavior.
* **Model**: `claude-opus-4-7` by default. `claude-sonnet-4-7` runs faster and cheaper; threat hunting quality drops somewhat because the agent reasons less about environment-to-IOC relevance, but still functional.

## Troubleshooting

* **ThreatFox returns 403**: your abuse.ch auth key is missing or wrong. Check the `Threatfox Abuse.ch Header Credential` credential.
* **OTX returns 403 or 429**: API key issue or rate limit. OTX free tier has rate limits; a 6-hour cadence with a handful of calls per run is within the free tier.
* **Agent times out**: Scanner MCP unreachable, or a threat intel feed hanging. Check the AI Agent node execution log; the step immediately before the hang identifies the culprit.
* **Empty Slack message**: the agent returned non-text output. Check the Slack node's text expression; by default it extracts from `$json.output` with an indexOf preamble strip keyed to the 🔍 emoji.
