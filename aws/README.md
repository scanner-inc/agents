# AWS agents

Two autonomous SOC agents deployed on AWS, built with the [Claude Agent SDK](https://github.com/anthropics/claude-agent-sdk):

1. **Alert Triage Agent** (`alert-triage/`): receives detection alerts via a webhook (API Gateway with API key auth) that enqueues to SQS, which triggers a Lambda. The Lambda queries logs through Scanner MCP, classifies severity, posts a structured finding to Slack, and logs every tool call as structured JSON to CloudWatch for audit.

2. **Threat Hunt Agent** (`threat-hunting/`): scheduled ECS Fargate task that combines CISA KEV data with threat intel feeds (ThreatFox, OTX, Feodo Tracker), hunts across historical logs, and posts findings to Slack.

## Prerequisites

- Node.js 22+
- Docker
- Terraform
- AWS CLI (configured with appropriate permissions)
- An [Anthropic API key](https://console.anthropic.com/)
- A [Scanner](https://scanner.dev) account with MCP access
- An [AlienVault OTX](https://otx.alienvault.com/) API key (free)
- An [abuse.ch](https://abuse.ch/) auth key (free)

## Quick Start

```bash
# Install dependencies
./scripts/setup.sh

# Copy and fill in environment variables
cp .env.template .env
# Edit .env with your API keys
```

### Alert Triage Agent (Lambda)

```bash
cd alert-triage
cp .env.template .env
# Fill in ANTHROPIC_API_KEY and Scanner MCP credentials
./deploy.sh
```

### Threat Hunt Agent (Container)

```bash
cd threat-hunting
cp .env.template .env
# Fill in all credentials (Anthropic, Scanner, Slack, threat intel APIs)
./deploy.sh
```

## Repo Structure

```
aws/
├── alert-triage/        # Alert triage agent (container-image Lambda)
│   ├── handler.ts       # Lambda function
│   ├── Dockerfile
│   ├── deploy.sh        # Build and deploy pipeline
│   └── terraform/       # Lambda, SQS, IAM, Secrets Manager
├── threat-hunting/      # Threat hunt agent (ECS Fargate)
│   ├── threat_hunt.ts   # Agent entrypoint
│   ├── Dockerfile
│   ├── deploy.sh        # Build and deploy pipeline
│   └── terraform/       # ECS, VPC, EventBridge, IAM
├── scripts/
│   ├── setup.sh         # Install deps and verify AWS auth
│   └── teardown.sh      # Destroy all infrastructure
└── .env.template        # Root env template (used by scripts/)
```

## Teardown

The threat-hunting agent provisions a NAT gateway (~$32/month). When you're done:

```bash
./scripts/teardown.sh
```

## License

MIT (see `LICENSE` at the repo root).
