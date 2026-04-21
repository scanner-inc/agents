# n8n workflows

n8n workflow examples that pair Claude with [Scanner](https://scanner.dev) MCP to automate common SOC tasks. Each subfolder is a self-contained workflow you can import directly into your n8n instance.

## Workflows

| Workflow | Trigger | What it does |
|---|---|---|
| **[`alert-triage/`](./alert-triage)** | Webhook (Scanner event sink) | Investigates a detection alert via Scanner MCP, classifies as BENIGN / SUSPICIOUS / MALICIOUS with evidence, and posts a structured finding to Slack. |
| `daily-reporting/` (planned) | Schedule (daily) | Reports on log source volume, detection rule coverage, MITRE coverage, and alert counts. Recommends next log sources and detections to close gaps. |
| `threat-hunting/` (planned) | Schedule (hourly) | Pulls fresh IOCs from CISA KEV, ThreatFox, OTX, and Feodo Tracker; hunts across historical logs via Scanner MCP; posts findings to Slack. |

## Structure of each workflow folder

```
<workflow>/
├── workflow.json          # Importable n8n workflow
├── README.md              # Architecture + node-by-node walkthrough
├── setup.md               # Credentials, import steps, test instructions
├── prompts/               # System prompt(s) as markdown (versioned separately from JSON)
├── sample-payloads/       # Example inputs for local testing
└── screenshots/           # Canvas screenshots referenced from the README
```

## Getting started

1. Pick a workflow folder. Start with `alert-triage/` if you want the simplest end-to-end example.
2. Follow its `setup.md`: create credentials in n8n, import `workflow.json`, adjust the MCP URL and Slack channel, test with the pinned sample payload.
3. Once the workflow runs end-to-end against the sample, wire up the real trigger (Scanner event sink for webhooks, or activate the Schedule trigger).

## Shared patterns

All workflows follow the same shape:

```
Trigger (Webhook or Schedule)
  → [optional preprocessing]
  → AI Agent node
       ├── Claude chat model (sub node)
       ├── Scanner MCP client tool (sub node)
       └── [additional MCP tools: threat intel, etc.]
  → Slack or other output
```

The AI Agent node runs the reasoning loop; Scanner MCP is exposed to it as a tool. Prompts live in `prompts/` so they can be reviewed and diffed without wading through JSON.

## Compatibility

Tested against n8n with these minimum node versions: Anthropic Chat Model 1.3, AI Agent 1.7, MCP Client Tool 1.2, Slack 2.4, Webhook 2.1. Older n8n versions may not list Claude 4.x models or speak Streamable HTTP MCP transport; update the image if needed.

## Contributing a new workflow

1. Copy an existing folder as a starting template.
2. Edit `README.md`, `setup.md`, `workflow.json`, and the prompt.
3. Validate end-to-end in a live n8n instance before committing.
4. Re-export the workflow from n8n to capture the canonical JSON, then sanitize: blank credential IDs, placeholder Slack channel IDs, generic MCP URL.
