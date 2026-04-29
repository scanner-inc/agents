# Claude Code skills

Five SOC slash commands packaged as a [Claude Code plugin marketplace](https://docs.claude.com/en/docs/claude-code/plugins). Drop into `claude`, type `/triage-alert <id>` (or one of the others), and the skill drives Scanner MCP for you.

## Skills

| Slash command | What it does |
|---|---|
| **[`/triage-alert <id>`](./triage-alert)** | Look up a Scanner detection alert by id and run a full triage — hypothesis, evidence collection, BENIGN / SUSPICIOUS / MALICIOUS classification with confidence, self-critique, structured report. |
| **[`/threat-hunt [topic]`](./threat-hunt)** | Proactive hunt against historical logs. With no argument, picks the most environmentally relevant CVE from CISA KEV. With an argument (CVE / malware / actor / IOC), hunts that. |
| **[`/posture-report`](./posture-report)** | Daily Scanner posture report — environment, log volume, alert activity (actionable / correlation / uncategorized), coverage gaps, 2–5 recommended next moves. |
| **[`/investigate <question>`](./investigate)** | Free-form Scanner Q&A. Restates the question, drafts a 3–6 bullet plan grounded in your actual schema, then executes via Scanner MCP and returns a structured finding. |
| **[`/lookup-ioc <indicator>`](./lookup-ioc)** | One-shot IOC reputation across ThreatFox, OTX, and (for IPv4) Feodo Tracker. Returns a single merged threat-intel report. |

## Requirements

- **Claude Code** with plugin marketplaces enabled (`/plugin` should open a UI).
- **Scanner MCP** configured in Claude Code — every skill calls `get_scanner_context` and `execute_query`. See [Scanner MCP docs](https://scanner.dev/docs).
- **Environment variables** (set in your shell or `~/.claude/settings.json`):
  - `SCANNER_API_URL`, `SCANNER_API_KEY`, `SCANNER_TENANT_ID` — needed by `/posture-report` and any `/investigate` question that hits the Detection Rules REST API. Skip if you only run `/triage-alert`, `/threat-hunt`, and `/lookup-ioc`.
  - `OTX_API_KEY`, `ABUSECH_AUTH_KEY` — optional, used by `/lookup-ioc`, `/threat-hunt`, and IOC enrichment inside `/triage-alert`. Each source degrades gracefully if its key is missing.

## Install

The marketplace lives in this `skills/` subfolder, not at the repo root, so the GitHub one-liner (`/plugin marketplace add owner/repo`) won't find it. Clone and use a local path:

```bash
git clone https://github.com/scanner-dev/agents.git
cd agents
```

Then in Claude Code:

```
/plugin marketplace add ./skills
/plugin install scanner-soc-skills@scanner-soc-skills
```

That's it — skills auto-load. Run `/reload-plugins` if Claude Code doesn't pick them up immediately, then `/triage-alert <some-alert-id>` to smoke test.

To browse, enable / disable, or uninstall later:

```
/plugin                                                  # tabbed UI: Discover, Installed, Marketplaces, Errors
/plugin disable scanner-soc-skills@scanner-soc-skills
/plugin enable  scanner-soc-skills@scanner-soc-skills
/plugin uninstall scanner-soc-skills@scanner-soc-skills
```

## Updating

Pull the repo and reload:

```bash
git -C path/to/agents pull
```

```
/plugin marketplace update scanner-soc-skills
/reload-plugins
```

## Troubleshooting

- **`/plugin` doesn't exist.** Update Claude Code — plugin marketplaces are a recent feature.
- **Skill doesn't appear after install.** Run `/reload-plugins`. If still missing, check `/plugin` → Errors tab for marketplace parse errors.
- **Skill runs but Scanner queries fail.** Confirm Scanner MCP is configured and reachable (`get_scanner_context` should return a context token). The skills assume MCP is already set up — they don't bootstrap it.
- **`/posture-report` complains about missing env vars.** Set `SCANNER_API_URL` / `SCANNER_API_KEY` / `SCANNER_TENANT_ID` and restart Claude Code so the new env is inherited.

## Layout

```
skills/
├── .claude-plugin/
│   └── marketplace.json    # plugin marketplace manifest (one plugin: scanner-soc-skills)
├── triage-alert/
│   ├── SKILL.md            # frontmatter + workflow
│   └── references/         # methodology loaded on demand
├── threat-hunt/
├── posture-report/
├── investigate/
└── lookup-ioc/
    └── scripts/            # bash helpers fanning out to ThreatFox / OTX / Feodo
```

Each skill folder is self-contained: `SKILL.md` is the entry point, `references/` holds longer methodology that the skill loads progressively, and `scripts/` holds bash helpers the skill shells out to.
