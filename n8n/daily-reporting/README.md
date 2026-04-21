# Daily reporting workflow (n8n)

Scheduled agent that produces a daily digest of your Scanner environment: log source volume, detection rule coverage, MITRE ATT&CK coverage, and alert activity, with recommendations for expanding coverage. Runs every morning, posts to Slack.

## Architecture

```
┌───────────┐      ┌─────────────────┐      ┌───────┐
│ Schedule  │─────▶│  Daily Report   │─────▶│ Slack │
│ (daily)   │      │      Agent      │      │ post  │
└───────────┘      └────────┬────────┘      └───────┘
                            │
          ┌─────────────────┼─────────────────┐
          │                 │                 │
┌─────────▼────────┐  ┌─────▼───────┐  ┌──────▼──────────┐
│   Anthropic      │  │  Scanner    │  │  Detection      │
│   Chat Model     │  │     MCP     │  │  Rules API      │
│  (Opus 4.7)      │  │             │  │  (HTTP tool)    │
└──────────────────┘  └─────────────┘  └─────────────────┘
```

The agent pulls two kinds of data:

1. **Scanner MCP** (log queries): log volume per source over the last 24h, alert counts and categorization over the last 24h, environment context (`get_scanner_context` returns the tenant id and available indices).
2. **Scanner Detection Rules REST API** (HTTP tool): paginated list of detection rules with tags (MITRE tactics/techniques), severity, query text, and last fired timestamp.

Cross referencing these gives: which log sources have coverage, which MITRE tactics are covered, which rules are actually firing, and where the gaps are.

## Why this shape

- **Schedule trigger** instead of webhook: this is a cron-style report, not event driven.
- **AI Agent with two tools** instead of a graph of HTTP nodes: the report is mostly reasoning work (identifying gaps, writing recommendations). Deterministic pagination + LLM reasoning is possible but costs more n8n nodes for little gain at daily cadence.
- **Opus 4.7**: gap analysis and recommendation generation benefit from stronger reasoning. Bounded tool budget keeps the runtime predictable.
- **Slack node downstream, not a Slack tool**: the agent posts exactly one report per run, no reason to let it decide.

## Node by node walkthrough

1. **Schedule Trigger** (`n8n-nodes-base.scheduleTrigger`): cron expression `0 8 * * *` (08:00 UTC daily). Adjust to your timezone.
2. **Daily Report Agent** (`@n8n/n8n-nodes-langchain.agent`): core agent. System prompt in `prompts/reporting-agent.md`. Retry On Fail enabled.
3. **Anthropic Chat Model** (`@n8n/n8n-nodes-langchain.lmChatAnthropic`): sub node via `ai_languageModel`. Model: `claude-opus-4-7`.
4. **Scanner MCP** (`@n8n/n8n-nodes-langchain.mcpClientTool`): sub node via `ai_tool`. Bearer auth.
5. **Detection Rules API** (`@n8n/n8n-nodes-langchain.toolHttpRequest`): sub node via `ai_tool`. Configured with a parameterized URL template so the agent can pass `tenant_id` and pagination cursors.
6. **Send a message** (`n8n-nodes-base.slack`): posts the agent's final digest to the reporting channel.

## What to customize on import

1. **Credentials**: Anthropic, Scanner MCP Bearer, Scanner REST Bearer (same API key as MCP is fine), Slack.
2. **MCP and API base URLs**: replace `your-env.scanner.dev` with your tenant hostname in two places (MCP Client and Detection Rules HTTP Request Tool).
3. **Schedule**: adjust the cron expression for your team's timezone.
4. **Slack channel**: set the reporting channel ID.
5. **Pagination cap**: the prompt caps the agent at 5 pages (5,000 rules at page size 1000); tune if you have more than ~5,000 rules.

See `setup.md` for step by step.
