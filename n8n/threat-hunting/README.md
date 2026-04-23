# Threat hunting workflow (n8n)

Scheduled agent that proactively hunts for evidence of compromise across historical Scanner logs. Every 6 hours, it pulls fresh CISA KEV entries and queries threat intel feeds (ThreatFox, OTX, Feodo Tracker) for IOCs relevant to the customer's environment, sweeps historical Scanner logs for matches, and posts a findings report to Slack.

Adapted from [`aws/threat-hunting/`](../../aws/threat-hunting), which deploys the same agent as an ECS Fargate task via the Claude Agent SDK.

## Architecture

```
┌───────────┐    ┌────────────┐    ┌────────────┐    ┌─────────────────┐    ┌───────┐
│ Schedule  │───▶│  CISA KEV  │───▶│  Extract   │───▶│  Threat Hunt    │───▶│ Slack │
│ (6h cron) │    │  (HTTP)    │    │  top 5     │    │     Agent       │    │ post  │
└───────────┘    └────────────┘    │  (Code)    │    └────────┬────────┘    └───────┘
                                   └────────────┘             │
                           ┌───────────────────┬──────────────┼──────────────┬──────────────┐
                           │                   │              │              │              │
                  ┌────────▼────────┐  ┌───────▼──────┐  ┌────▼─────┐  ┌─────▼──────┐  ┌────▼─────┐
                  │   Anthropic     │  │   Scanner    │  │ ThreatFox│  │    OTX     │  │  Feodo   │
                  │   Chat Model    │  │     MCP      │  │  Search  │  │  Pulse     │  │  Tracker │
                  │  (Opus 4.7)     │  │              │  │  (HTTP)  │  │  Search    │  │  (HTTP)  │
                  └─────────────────┘  └──────────────┘  └──────────┘  │  (HTTP)    │  └──────────┘
                                                                       └────────────┘
```

## What the agent does

A 5-phase hunt:

1. **Environment discovery**: `get_scanner_context` to understand what indices, source types, and platforms exist in the tenant.
2. **Threat intel gathering**: review pre-fetched CISA KEV entries (top 5 most recently added); filter for relevance to the environment. Use ThreatFox, OTX, and Feodo Tracker HTTP Request Tools to pull actionable IOCs (IPs, domains, hashes) tied to matching CVEs or malware families. Determine a historical search window based on when the threat first emerged.
3. **Hunt**: broad IOC sweeps against Scanner logs using wildcard field search (`**: "IOC"`). Only if hits are found, pivot to targeted behavioral queries on the relevant index to build context.
4. **Correlation and assessment**: cross-reference findings across log sources, build a timeline, map to MITRE ATT&CK, identify visibility gaps.
5. **Report**: post a structured finding to Slack with hunt target, IOCs searched, results (evidence found / inconclusive / no evidence), timeline, MITRE tags, visibility gaps, and recommended next questions for the analyst.

## Why run it

Known-bad IOCs land in public feeds daily. A SOC without a threat hunting program typically has no systematic way to check for them across its log history. This agent runs while the team sleeps, checks every IOC in a fresh batch against Scanner's full log history, and only posts when it finds something worth investigating (or when a clean run is notable — e.g., every run was clean for a month, or a specific high-priority CVE came out and the sweep was clean).

## Known differences from the AWS version

- **Single Slack post**, not two. The AWS version posts a Phase 3 announcement ("hunt starting") and a Phase 6 findings report. The n8n version posts only the final findings report. Adding mid-hunt Slack posts in n8n requires running a Slack MCP server somewhere reachable over HTTP, which is out of scope for v1.
- **Threat intel via HTTP Request Tools**, not `mcp-threatintel-server`. The custom threat intel MCP server that the AWS version uses is stdio-only and can't be reached from n8n. The n8n version exposes three of its tools directly via HTTP Request Tool nodes: ThreatFox search, OTX pulse search, Feodo Tracker IP blocklist. URLhaus and MalwareBazaar are not wired in; add them as additional HTTP Request Tools if you need them.
- **No Bash/jq fallback for large responses**. The AWS version's system prompt mentions Bash + `jq` as a way to parse large tool responses; n8n's AI Agent node doesn't have filesystem or shell access. Threat intel responses are small enough (10s of IOCs per call) that this hasn't been an issue in practice.

## What to customize on import

1. **Credentials**: Anthropic, Scanner MCP, Slack, and the two threat intel API keys (OTX, abuse.ch).
2. **MCP endpoint URL**: replace `mcp.your-env.scanner.dev` in the Scanner MCP node.
3. **Slack channel**: set the target channel ID.
4. **Schedule**: default cron is `0 */6 * * *` (every 6 hours). Adjust to suit your team.

See `setup.md` for details.
