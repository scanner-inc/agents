# Alert triage workflow (n8n)

Autonomous alert triage agent. Scanner detection fires → Scanner posts to this workflow's webhook → agent investigates using Scanner MCP → agent posts a structured finding to Slack.

## Architecture

```
┌─────────────┐       ┌───────────┐      ┌─────────────────┐      ┌───────┐
│  Scanner    │──POST─▶  Webhook  │─────▶│  Alert Triage   │─────▶│ Slack │
│  event sink │       │  (header  │      │     Agent       │      │ post  │
│             │       │   auth)   │      │                 │      │       │
└─────────────┘       └───────────┘      └────────┬────────┘      └───────┘
                                                  │
                                  ┌───────────────┼───────────────┐
                                  │                               │
                        ┌─────────▼────────┐             ┌────────▼────────┐
                        │   Anthropic      │             │   MCP Client    │
                        │   Chat Model     │             │   (Scanner MCP) │
                        │  (Opus 4.7)      │             │                 │
                        └──────────────────┘             └─────────────────┘
```

The AI Agent node runs an agent loop: it reasons, decides to call Scanner MCP tools (`get_scanner_context`, `execute_query`, `fetch_cached_results`), processes results, and produces a final Slack formatted finding. The downstream Slack node posts the finding to the configured channel.

## Why this shape

- **Webhook trigger, not SQS**: simplest integration with Scanner event sinks. Scanner's webhook event sink type (see `gitbook-docs/.../event-sinks.md`) POSTs JSON to a URL. n8n's webhook trigger node receives it directly.
- **AI Agent with Scanner MCP as a tool**: lets the agent decide which queries to run based on what it finds. This is the core "interactive investigation" loop, automated.
- **Slack node downstream, not Slack MCP tool inside the agent**: simpler. The agent always posts exactly one finding per alert, so there is no reason for the agent to "decide" when to post. Output of AI Agent → Slack node text.
- **No human in the loop approval**: this workflow is read only (no response actions). Safe to run fully autonomous. The daily reporting and threat hunting workflows use the same pattern. A future "autonomous response" workflow will add the approval pattern.

## Node by node walkthrough

1. **Webhook** (`n8n-nodes-base.webhook`): receives the Scanner alert JSON at `POST /webhook/scanner-alert`. Header Auth enabled: the `x-scanner-to-n8n-webhook-key` header must match the Scanner Webhook Secret credential. Invalid secrets get 401 automatically.
2. **Alert Triage Agent** (`@n8n/n8n-nodes-langchain.agent`): core agent. Prompt: "Triage this detection alert:\n\n{{ $json }}". System prompt lives in `prompts/triage-agent.md`. Retry On Fail enabled (3 tries, 5s wait) to survive transient Anthropic overload.
3. **Anthropic Chat Model** (`@n8n/n8n-nodes-langchain.lmChatAnthropic`): sub node, connected to the Agent via `ai_languageModel`. Model: `claude-opus-4-7` (swap to `claude-sonnet-4-7` if overload is frequent).
4. **Scanner MCP** (`@n8n/n8n-nodes-langchain.mcpClientTool`): sub node, connected to the Agent via `ai_tool`. Points at your Scanner MCP URL with bearer auth. Scanner MCP uses Streamable HTTP transport (not SSE).
5. **Send a message** (`n8n-nodes-base.slack`): posts the agent's final output to the configured channel.

## Setup

See `setup.md` for credentials, env vars, and test instructions.

## Sample payload

See `sample-payloads/example-alert.json` for a representative Scanner detection event. Use it to test the workflow by `curl`ing the webhook URL:

```bash
curl -X POST http://localhost:5678/webhook/scanner-alert \
  -H "Content-Type: application/json" \
  -d @sample-payloads/example-alert.json
```

## What you need to customize on import

The JSON in this directory has been validated against a live n8n instance with working node versions. On import, the only things to customize are environment specific values:

1. **Credentials**: create the four credentials listed in `setup.md` with the exact names the workflow references. n8n will link them by name on import.
2. **MCP endpoint URL**: replace `mcp.your-env.scanner.dev` in the MCP Client node with your tenant's Scanner MCP hostname.
3. **Slack channel ID**: replace `REPLACE_WITH_SLACK_CHANNEL_ID` in the Slack node with your target channel ID.
4. **Webhook secret**: generate a random string, store it in the Scanner Webhook Secret credential (header name `x-scanner-to-n8n-webhook-key`, value is the raw secret), and use the same header name and value when you create the Scanner event sink.

Node versions confirmed compatible (all current as of April 2026): Anthropic Chat Model 1.3, AI Agent 1.7, MCP Client Tool 1.2, Slack 2.4, Webhook 2.1.
