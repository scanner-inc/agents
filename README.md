# Scanner agents

SOC agents built against [Scanner](https://scanner.dev)'s MCP and detection rules API. Three runtimes: n8n workflows (import into any n8n instance), Claude Agent SDK programs (deploy to AWS with the included Terraform), and Claude Code skills (slash commands a SOC analyst runs from their laptop).

## What's here

Each top-level folder is a different kind of artifact.

- **[`n8n/`](./n8n)**: n8n workflows (visual workflow automation). Importable `workflow.json` files plus READMEs. Good for teams that already use n8n or want non-developers to read and modify agents.
- **[`aws/`](./aws)**: Claude Agent SDK agents deployed on AWS (Lambda + ECS Fargate) with Terraform. Good for teams that want the agent runtime inside their own VPC, with full control and standard engineering tooling.
- **[`skills/`](./skills)**: Claude Code skills packaged as a plugin marketplace. Five slash commands — `/triage-alert`, `/threat-hunt`, `/generate-health-report`, `/investigate`, `/lookup-ioc` — that an analyst can invoke directly from `claude` in their terminal. Good for interactive SOC work and ad-hoc investigations without standing up infrastructure.

## Picking an approach

| Situation | Start with |
|---|---|
| You already run n8n, or you want a visual/graph representation of the agent | `n8n/` |
| You have a platform team and want code + Terraform as the source of truth | `aws/` |
| You want a SOC analyst to drive the agent interactively from their terminal | `skills/` |
| You want the fastest path from Claude Code interactive use to autonomous | `n8n/` (n8n Cloud trial) |
| Compliance or networking requires the agent to run inside your VPC | `aws/` |

These approaches are not mutually exclusive. A mature SOC often runs a mix: the `skills/` plugin for interactive triage and detection engineering, an n8n workflow for autonomous alert triage on incoming webhooks, and an AWS-hosted agent for in-VPC response actions.

## Related

- **[Scanner MCP docs](https://scanner.dev/docs)**: documentation for using Claude with Scanner via MCP (interactive investigations, detection engineering, autonomous workflows).

## License

MIT. See [`LICENSE`](./LICENSE).
