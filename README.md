# Scanner agents

Autonomous SOC agents for [Scanner](https://scanner.dev), ready to deploy. Each folder is a working implementation: import it, configure credentials for your environment, and it runs.

## What's here

Each top-level folder is a different deployment approach. The workflows inside each folder are the same recurring set of SOC agent use cases: alert triage, threat hunting, detection engineering, and reporting.

- **[`n8n/`](./n8n)**: n8n workflows (visual workflow automation). Importable `workflow.json` files plus READMEs. Good for teams that already use n8n or want non-developers to read and modify agents.
- **[`aws/`](./aws)**: Claude Agent SDK agents deployed on AWS (Lambda + ECS Fargate) with Terraform. Good for teams that want the agent runtime inside their own VPC, with full control and standard engineering tooling.

## Picking an approach

| Situation | Start with |
|---|---|
| You already run n8n, or you want a visual/graph representation of the agent | `n8n/` |
| You have a platform team and want code + Terraform as the source of truth | `aws/` |
| You want the fastest path from Claude Code interactive use to autonomous | `n8n/` (n8n Cloud trial) |
| Compliance or networking requires the agent to run inside your VPC | `aws/` |

The three approaches are not mutually exclusive. A mature SOC often runs a mix: interactive Claude Code + Scanner MCP for detection engineering, an n8n workflow for alert triage, and an AWS-hosted agent for in-VPC response actions.

## Related

- **[Scanner MCP docs](https://scanner.dev/docs)**: documentation for using Claude with Scanner via MCP (interactive investigations, detection engineering, autonomous workflows).

## License

MIT. See [`LICENSE`](./LICENSE).
