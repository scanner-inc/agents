# Alert triage workflow: setup

## Prerequisites

* n8n instance (local via Docker or hosted). For local, see the primer in `2026_04_April/claude_demos_and_autonomous_agents/n8n_primer.md`.
* Anthropic API key.
* Scanner account with MCP access. Scanner MCP URL in the form `https://mcp.<your-env>.scanner.dev/v1/mcp` and a Scanner MCP API key.
* An [AlienVault OTX](https://otx.alienvault.com/) API key (free).
* An [abuse.ch](https://auth.abuse.ch/) auth key (free). Used for the ThreatFox API.
* Slack workspace connected to n8n.

## Credentials to create in n8n

Before importing `workflow.json`, create these credentials in n8n's **Credentials** UI. Names must match exactly so the workflow references resolve on import.

1. **Anthropic account** (type: Anthropic API)
   * API Key: your Anthropic key.

2. **Scanner API/MCP Bearer Auth account** (type: HTTP Bearer Auth)
   * Bearer Token: your Scanner MCP API key. Paste just the token; n8n adds the `Bearer ` prefix.

3. **Slack account** (type: Slack API or Slack OAuth2)
   * Follow n8n's prompts to connect your workspace.

4. **Header Auth account** (type: HTTP Header Auth, n8n's default name for this credential type)
   * Name: `x-scanner-to-n8n-webhook-key`
   * Value: a random secret string you generate (no prefix, just the raw secret). Save it; you will paste the same value into the Scanner event sink below.

5. **OTX Header Auth** (type: HTTP Header Auth)
   * Name: `X-OTX-API-KEY`
   * Value: your AlienVault OTX API key.

6. **Threatfox Abuse.ch Header Credential** (type: HTTP Header Auth)
   * Name: `Auth-Key`
   * Value: your abuse.ch auth key. Used for the ThreatFox endpoint.

## Import the workflow

1. In n8n, go to **Workflows** → **Import from File**.
2. Select `workflow.json`.
3. Open each node and verify or fix:
   * **Webhook**: path is `scanner-alert`. Authentication shows "Header Auth" and references the "Header Auth account" credential. Copy the Production URL for the Scanner event sink config.
   * **Alert Triage Agent**: Retry On Fail enabled (3 tries, 5s wait).
   * **Anthropic Chat Model**: credential set to "Anthropic account". Model is `claude-opus-4-7` (swap to `claude-sonnet-4-7` if you hit overload errors).
   * **Scanner MCP**: endpoint URL is your tenant's MCP URL (replace `mcp.your-env.scanner.dev` with the real hostname). Credential is "Scanner API/MCP Bearer Auth account".
   * **ThreatFox IOC Lookup**: credential is "Threatfox Abuse.ch Header Credential".
   * **OTX IOC Lookup**: credential is "OTX Header Auth".
   * **Alert Triage Agent**: system message field contains the full body of `prompts/triage-agent.md`. Import copies it, but verify it is not truncated.
   * **Split Output**: Code node that parses the agent's final response into a Slack portion and an optional Jira block. Leave the JavaScript as-is.
   * **Send a message**: channel ID is set to your target Slack channel (replace the placeholder).
   * **Create Jira?** and **Create Jira Issue**: leave alone unless you want Jira ticket creation — see the next section.

## Optional: enable Jira ticket creation

Slack delivery is the default. The **Create Jira Issue** node ships disabled, so out of the box the workflow only posts to Slack. Skip this section if you do not use Jira.

When enabled, the agent will request a Jira ticket only when **classification is SUSPICIOUS or MALICIOUS** AND **alert severity is Medium, High, or Critical**. BENIGN alerts, and Low/Info severity alerts of any classification, stay Slack-only.

To enable:

1. Create a **Jira SW Cloud account** credential (type: Jira Software Cloud API) in the n8n Credentials UI. Domain, email, API token. n8n's Jira docs walk through generating the token: <https://docs.n8n.io/integrations/builtin/credentials/jira/>.
2. Open the **Create Jira Issue** node → right-click → **Activate** (or untick "Disable").
3. In the same node:
   * Set **Project** to your Jira project key (replace `REPLACE_WITH_JIRA_PROJECT_KEY`).
   * Confirm **Issue Type** (default `Task`; change to `Bug`, `Incident`, etc. if your project requires).
   * Confirm the **Additional Fields** mappings — Description binds to `{{ $json.jira_description_wiki }}`, Labels to `{{ $json.jira_labels }}`. Priority is **not mapped by default** because many Jira projects (especially team-managed ones) disable the priority field entirely, and sending a value to such a project returns 400 "invalid priority". To check whether yours supports it, open any existing issue in your Jira project — if the Details panel has a Priority row, your project has priority enabled. If so and you want the agent's severity-driven mapping (`Critical → Highest, High → High, Medium → Medium`), add a Priority entry under Additional Fields bound to `{{ $json.jira_priority }}`.
4. Activate the workflow. The next SUSPICIOUS-or-MALICIOUS alert at Medium+ severity will produce both a Slack post and a Jira ticket.

If your Jira instance is self-hosted (Server / Data Center) rather than Cloud, swap the credential to "Jira Server API" and adjust the node accordingly.

## Test locally

1. Start n8n with the tunnel option so Scanner can reach it:
   ```bash
   docker run -it --rm \
     -p 5678:5678 \
     -v ~/.n8n:/home/node/.n8n \
     -e N8N_SECURE_COOKIE=false \
     n8nio/n8n start --tunnel
   ```
2. Activate the workflow.
3. Smoke test with the pinned sample payload (included in `workflow.json`) by clicking **Execute workflow** in the n8n UI, or via `curl`:
   ```bash
   curl -X POST http://localhost:5678/webhook/scanner-alert \
     -H "x-scanner-to-n8n-webhook-key: <your webhook secret>" \
     -H "Content-Type: application/json" \
     -d @sample-payloads/example-alert-iam-admin-attach.json
   ```
4. Watch the execution in the n8n UI. Expected: the agent calls Scanner MCP tools (`get_scanner_context`, `execute_query`, `fetch_query_results`) over multiple turns, enriches any external IOCs it sees via ThreatFox / OTX, then emits the Slack formatted finding. The Slack node posts it.

## Wire up a real Scanner event sink

1. In Scanner UI, go to **Settings** → **Event Sinks** → **Create New Sink** → **Webhook**.
2. **URL**: the Production URL from the n8n Webhook node (the tunnel URL while developing locally, or your stable hosted n8n URL in production).
3. **Headers**: add a custom header matching the n8n "Header Auth account" credential:
   * Name: `x-scanner-to-n8n-webhook-key`
   * Value: `<same secret you stored in n8n>` (no prefix)
4. Save the event sink, then click **Send Test Event** to confirm the round trip works.
5. Attach the event sink to one or more detection rules.

## Security considerations

* The webhook URL plus the shared secret is the security boundary. The Webhook node's Header Auth validates the `Authorization` header before the workflow runs, returning 401 on mismatch. Rotate the secret periodically and any time it might have been exposed.
* The AI Agent has MCP read access to Scanner and Slack write. It takes no response actions. If you extend this workflow to call write APIs (disable user, isolate host), add a **Wait** node with a Slack button approval before the write step.
* Scanner MCP API keys should be scoped to read only permissions. Do not use an admin key here.

## Troubleshooting

* **Webhook 401**: `x-scanner-to-n8n-webhook-key` header is missing or does not match the credential value. Check the Scanner event sink header config, verify the credential value in n8n.
* **Webhook 404**: workflow not activated, or path does not match. Check the n8n UI.
* **Anthropic "Overloaded" (429 / 529)**: Anthropic API under load. Retry On Fail on the AI Agent node covers most cases. If persistent, switch model to `claude-sonnet-4-7`.
* **MCP Client authentication failed**: credential value wrong, or Scanner MCP endpoint unreachable. Test the MCP URL with `curl` using a bearer token outside of n8n first.
* **Empty Slack message**: AI Agent returned non text output. Check the execution log for the AI Agent node; the output should be a single string. If wrapped, adjust the Slack node's text field expression.
