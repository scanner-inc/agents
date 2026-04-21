# Threat Hunt Agent (Container)

A scheduled ECS Fargate task that proactively hunts for evidence of compromise across your historical logs. Every 6 hours, the agent pulls fresh threat intelligence from CISA KEV, ThreatFox, AlienVault OTX, and Feodo Tracker, hunts across 1+ years of [Scanner](https://scanner.dev) log data, and posts findings to Slack.

Built with the [Claude Agent SDK](https://github.com/anthropics/claude-agent-sdk).

## How It Works

The agent (`threat_hunt.ts`) executes a 6-phase hunt:

1. **Environment Discovery** - queries Scanner to understand what log sources exist
2. **Threat Intelligence** - fetches CISA KEV vulnerabilities, ThreatFox IOCs, OTX pulses, and Feodo C2 IPs. Filters for threats relevant to the discovered environment
3. **Announce** - posts to Slack: what's being hunted, which IOCs, what time range, and why
4. **Hunt** - sweeps logs for IOCs (IPs, domains, hashes) via Scanner MCP. Pivots to behavioral queries only when hits are found
5. **Correlate** - cross-references findings, builds timelines, maps to MITRE ATT&CK
6. **Report** - posts a structured findings report to Slack with evidence, confidence, visibility gaps, and recommended next questions

## Architecture

- **Runtime**: ECS Fargate on a private subnet (no public IP). Outbound traffic goes through a NAT gateway.
- **Schedule**: EventBridge triggers a Fargate task every 6 hours. The agent runs until done, then exits. No idle compute.
- **MCP Servers**: Three MCP connections:
  - **Scanner** (HTTP) - log queries
  - **Slack** (stdio, `@modelcontextprotocol/server-slack`) - posting findings
  - **Threat Intel** (stdio, `mcp-threatintel-server`) - ThreatFox, OTX, Feodo Tracker, MalwareBazaar, URLhaus
- **Networking**: Private VPC with no ingress rules. The container reaches out to APIs; nothing reaches in. NAT gateway costs ~$32/month.
- **Secrets**: Stored in AWS Secrets Manager, injected as environment variables by ECS task definition
- **Infrastructure**: Terraform manages ECS cluster, task definition, ECR, VPC/subnets/NAT, EventBridge schedule, IAM roles, Secrets Manager, and CloudWatch log group

## Setup

```bash
cp .env.template .env
# Fill in your credentials
```

Required environment variables:
- `ANTHROPIC_API_KEY` - Anthropic API key
- `SCANNER_MCP_URL` - Scanner MCP endpoint
- `SCANNER_MCP_API_KEY` - Scanner API key
- `SLACK_BOT_TOKEN` - Slack bot token (`xoxb-...`)
- `SLACK_TEAM_ID` - Slack workspace ID
- `SLACK_CHANNEL_ID` - Channel ID to post findings
- `SLACK_CHANNEL_NAME` - Channel name (used in the agent prompt)
- `OTX_API_KEY` - [AlienVault OTX](https://otx.alienvault.com/) API key (free)
- `ABUSECH_AUTH_KEY` - [abuse.ch](https://abuse.ch/) auth key (free)

## Deploy

```bash
./deploy.sh
```

This handles: ECR repo creation, TypeScript build, Docker build (`linux/amd64`), ECR push, and full Terraform apply (ECS, VPC, EventBridge, IAM).

After deploy, EventBridge runs the agent every 6 hours automatically.

## Manual Run

Trigger a hunt outside the schedule:

```bash
aws ecs run-task \
  --cluster soc-agents \
  --task-definition triage-agent \
  --launch-type FARGATE \
  --network-configuration 'awsvpcConfiguration={subnets=[SUBNET_ID],securityGroups=[SG_ID],assignPublicIp=DISABLED}' \
  --profile $AWS_PROFILE --region $AWS_REGION
```

Get the subnet and security group IDs from `terraform output`.

## Cost

The container itself is pay-per-run (Fargate billing). The NAT gateway is always-on at ~$32/month. Run `../scripts/teardown.sh` when you're done to avoid ongoing charges.

## Tests

```bash
npx jest
```
