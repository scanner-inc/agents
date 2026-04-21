# SOC Triage Agent (Lambda)

A webhook-driven Lambda function that investigates security alerts autonomously. Scanner (or any other source) POSTs alerts to an API Gateway endpoint with API key auth; the gateway enqueues them to SQS, which triggers the Lambda. The agent queries your logs through [Scanner](https://scanner.dev) MCP, generates and tests hypotheses, runs two self-critique passes, and returns a structured classification (BENIGN / SUSPICIOUS / MALICIOUS) with evidence, timeline, and next questions for the analyst.

Built with the [Claude Agent SDK](https://github.com/anthropics/claude-agent-sdk).

## How It Works

1. Your detection system (e.g., a Scanner webhook event sink) POSTs alerts to `POST /v1/alerts` on the API Gateway endpoint, with an `x-api-key` header
2. API Gateway validates the API key, enforces the rate limit, and enqueues the request body into SQS
3. SQS triggers the Lambda (one alert per invocation)
4. The agent queries logs via Scanner MCP, investigating a 4-6 hour window around the alert
5. The agent posts a structured finding (classification, evidence, timeline, recommended next questions) to Slack via the Slack MCP server
6. Every MCP tool call is logged as structured JSON to CloudWatch for audit
7. The final classification is returned in the Lambda response and logged
8. Failed invocations retry once, then land in a dead letter queue

The handler (`handler.ts`) accepts both direct invocation and SQS-wrapped events, so you can test with `aws lambda invoke` and run in production via the webhook without changes. The Slack post step is optional: if `SLACK_BOT_TOKEN` and `SLACK_TEAM_ID` are not set, the agent still runs and returns the classification, but does not post anywhere.

## Architecture

- **Runtime**: Container-image Lambda (Node.js 22). The Agent SDK spawns `cli.js` as a child process, which requires a container image; zip-packaged Lambdas hang for ~31 seconds and return nothing.
- **Ingress**: API Gateway REST API with API key auth on `POST /v1/alerts`. Rate limited (5 req/s burst 10, 10k/day). Direct AWS service integration forwards the request body to SQS as the message body.
- **Trigger**: SQS queue with `batch_size = 1` and `visibility_timeout = 960s` (slightly longer than Lambda's 900s timeout to prevent duplicate invocations).
- **Concurrency**: `reserved_concurrent_executions = 5`. Excess messages wait in SQS. Increase if messages age in the queue, but watch API rate limits first.
- **Secrets**: Stored in AWS Secrets Manager, injected as environment variables by Lambda.
- **Infrastructure**: Terraform manages API Gateway, Lambda, SQS, DLQ, ECR, IAM roles, Secrets Manager, and CloudWatch log group (`terraform/main.tf` plus `terraform/webhook.tf`).

## Setup

```bash
cp .env.template .env
# Fill in your credentials
```

Required environment variables:
- `ANTHROPIC_API_KEY` - Anthropic API key
- `SCANNER_MCP_URL` - Scanner MCP endpoint (e.g. `https://mcp.scanner.dev/sse`)
- `SCANNER_MCP_API_KEY` - Scanner API key

## Deploy

```bash
./deploy.sh
```

This handles the full pipeline: ECR repo creation, TypeScript build, Docker build (`linux/amd64`), ECR push, Terraform apply, and Lambda code update.

## Invoke

```bash
aws lambda invoke --function-name soc-triage-agent \
  --payload '{"alert_id":"test-001","alert_summary":"Unusual API call from new IP"}' \
  --profile $AWS_PROFILE --region $AWS_REGION \
  --cli-binary-format raw-in-base64-out \
  --cli-read-timeout 900 \
  /tmp/output.json && cat /tmp/output.json | jq .body -r | jq .
```

`--cli-read-timeout 900` is required. Investigations take 2-5 minutes; the default 60s CLI timeout will cut the connection while the agent is still running.

## Output

The agent returns structured JSON:

```json
{
  "classification": "BENIGN",
  "confidence": "high",
  "confidence_pct": 92,
  "summary": "Routine SSO federation from known corporate IP...",
  "timeline": [{"timestamp": "...", "event": "..."}],
  "hypothesis_testing": {
    "confirmed": "Benign SSO activity from authorized user...",
    "ruled_out": ["Attack scenario: no indicators of compromise..."]
  },
  "key_evidence": ["Source IP matches known corporate range..."],
  "mitre_attack": [],
  "next_questions": ["Is this user authorized for cross-account access?"]
}
```

## Tests

```bash
npx jest
```
