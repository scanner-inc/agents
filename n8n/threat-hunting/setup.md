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
   * **Send a message**: channel ID is your threat hunting Slack channel.

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
