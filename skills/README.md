# Claude Code skills

Twelve SOC and detection-engineering slash commands packaged as a [Claude Code plugin marketplace](https://docs.claude.com/en/docs/claude-code/plugins). Drop into `claude`, type `/triage-alert <id>` (or one of the others), and the skill drives Scanner MCP for you.

## Skills

### SOC operations

| Slash command | What it does |
|---|---|
| **[`/triage-alert <id>`](./triage-alert)** | Look up a Scanner detection alert by id and run a full triage — hypothesis, evidence collection, BENIGN / SUSPICIOUS / MALICIOUS classification with confidence, self-critique, structured report. |
| **[`/threat-hunt [topic]`](./threat-hunt)** | Proactive hunt against historical logs. With no argument, picks the most environmentally relevant CVE from CISA KEV. With an argument (CVE / malware / actor / IOC), hunts that. |
| **[`/posture-report`](./posture-report)** | Daily Scanner posture report — environment, log volume, alert activity (actionable / correlation / uncategorized), coverage gaps, 2–5 recommended next moves. |
| **[`/investigate <question>`](./investigate)** | Free-form Scanner Q&A. Restates the question, drafts a 3–6 bullet plan grounded in your actual schema, then executes via Scanner MCP and returns a structured finding. |
| **[`/lookup-ioc <indicator>`](./lookup-ioc)** | One-shot IOC reputation across ThreatFox, OTX, and (for IPv4) Feodo Tracker. Returns a single merged threat-intel report. |

### Detection engineering

| Slash command | What it does |
|---|---|
| **[`/write-detection`](./write-detection)** | Author a new Scanner detection rule from a natural-language description. Discovers the source schema via MCP, sanity-checks the filter against real data, drafts the YAML, seeds inline tests from real events, validates with `scanner-cli`, and backtests against historical logs (needle-in-haystack regime can scan months of data). Always writes new rules in `Staging` state. |
| **[`/tune-detection <rule>`](./tune-detection)** | Investigate a noisy rule, classify recent firings as FP / TP / UNKNOWN, propose a targeted YAML diff (extra filter, threshold, dedup window, or severity downgrade), add regression tests seeded from FP events, validate, and backtest the new fire-rate. Handles the OOB fork-and-disable workflow for read-only rules. |
| **[`/migrate-detection <path>`](./migrate-detection)** | Translate a detection rule from Splunk / Sigma / Chronicle YARA-L / Panther / Azure Sentinel / Elastic into Scanner YAML. Auto-detects the source format, greps the migration corpus for the closest worked example, iteratively tests the translated query against real Scanner logs via MCP, and hands off VRL enrichment requirements to `/write-vrl` when the source rule needs lookup tables. |
| **[`/write-correlation`](./write-correlation)** | Author a correlation detection rule joining multiple existing rules via a custom `correlation.<label>` tag (which the skill writes onto each constituent's YAML). Pivots on an entity column from each rule's `results_table.rows[0].*`, uses `countdistinct(name)` — never the opaque `detection_rule_id`. Falls back to joining by rule `name` for OOB rules the user can't edit. |
| **[`/recommend-detections`](./recommend-detections)** | Orchestrator skill that produces a prioritised punch-list: new rules to write, existing rules to tune, correlations to add, foreign-SIEM rules to migrate, and Scanner OOB packs worth enabling. Consumes posture-report output and walks the user's local rules repo to build a coverage matrix. Every recommendation ends with a copy-paste-ready `/skill <args>` invocation. |

### Ingest engineering

| Slash command | What it does |
|---|---|
| **[`/write-vrl`](./write-vrl)** | Author and test a VRL transformation step for Scanner. Drafts a program from a sample log + objective (normalize to ECS, drop noisy events, fan out, parse, enrich), runs it through `vector vrl` against the sample, iterates until output matches, and hands back code ready to paste into the Scanner UI. Carries the canonical IOC-enrichment chain (`references/ioc_enrichment.md` + `corpus/alienvault_threat_intelligence_enrichment.vrl` + `scripts/list_lookup_tables.sh`) used by `/write-detection` and `/recommend-detections` whenever IOC matching is involved. |

### Reporting

| Slash command | What it does |
|---|---|
| **[`/report-as-html`](./report-as-html)** | Render a finished terminal report (from any other skill) as a polished light-mode HTML file in `/tmp/`. Cream / teal aesthetic, self-contained (inline CSS, no JS), print-friendly. Every report skill closes with "Want this as an HTML report?" → if yes, this skill renders it → then asks "Open in browser?" separately. Not a stand-alone analysis skill — purely a renderer. |

## Requirements

- **Claude Code** with plugin marketplaces enabled (`/plugin` should open a UI).
- **Scanner MCP** configured in Claude Code — every Scanner-backed skill calls `get_scanner_context` and `execute_query`. See [Scanner MCP docs](https://scanner.dev/docs). `/write-vrl` does not need Scanner MCP.
- **Environment variables** (set in your shell or `~/.claude/settings.json`):
  - `SCANNER_API_URL`, `SCANNER_API_KEY` — needed by `/posture-report`, `/recommend-detections`, `/write-detection`, `/tune-detection`, `/migrate-detection`, `/write-correlation`, and any `/investigate` question that hits the Detection Rules REST API. The detection-engineering skills use these for `scanner-cli validate` and `scanner-cli run-tests`.
  - `SCANNER_TENANT_ID` — needed by `/posture-report` and `/recommend-detections` for the rule-inventory REST API call.
  - `SCANNER_DETECTIONS_DIR` — comma-separated absolute paths to the user's detection-rule GitHub repos. Read by `/write-detection`, `/tune-detection`, `/migrate-detection`, `/write-correlation`, and `/recommend-detections`. If unset, each skill asks per-invocation.
  - `OTX_API_KEY`, `ABUSECH_AUTH_KEY` — optional, used by `/lookup-ioc`, `/threat-hunt`, and IOC enrichment inside `/triage-alert`. Each source degrades gracefully if its key is missing.
- **`scanner-cli`** on PATH for the detection-engineering skills — used for offline rule validation and unit-test execution. Install from `~/src/scanner-cli/` via Poetry (the Poetry entry point is `scanner-cli`).
- **`vector` binary** for `/write-vrl` only — used to run drafted VRL against sample input before handing the program back. Looks on PATH then at `~/.vector/bin/vector`. Install with `curl --proto '=https' --tlsv1.2 -sSf https://sh.vector.dev | bash` or see <https://vector.dev/docs/setup/installation/>.

### Sync flow (detection-engineering skills)

The detection-engineering skills (`/write-detection`, `/tune-detection`, `/migrate-detection`, `/write-correlation`) never push rules to Scanner directly. The hand-off is always: commit the YAML to your detection-rules GitHub repo, push to `main`, and the Scanner GitHub app validates server-side and syncs. `scanner-cli sync` is a legacy fallback — these skills never recommend it.

## Install

The marketplace lives in this `skills/` subfolder, not at the repo root, so the GitHub one-liner (`/plugin marketplace add owner/repo`) won't find it. Clone and use a local path:

```bash
git clone https://github.com/scanner-inc/agents.git
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
├── lookup-ioc/
│   └── scripts/            # bash helpers fanning out to ThreatFox / OTX / Feodo
├── write-vrl/
│   ├── references/         # Scanner VRL conventions, corpus index, ECS 9.5.0 schema CSV
│   ├── corpus/             # 15 production ECS transforms + 2 enrichment patterns
│   ├── examples/           # ready-to-use lookup-table fixtures (CSV + MMDB + Go regen)
│   └── scripts/            # `vector vrl` wrapper supporting CSV + MMDB enrichment tables
├── write-detection/
│   └── references/         # methodology, yaml_schema, query_language, severity_policy, backtesting, mitre_tags
├── tune-detection/
│   └── references/         # methodology (FP/TP rubric, tuning toolbox, OOB fork-and-disable)
├── migrate-detection/
│   ├── references/         # methodology, source_repos, translation_{splunk,sigma,chronicle,panther,sentinel,elastic}, mitre_tags
│   └── corpus/             # 6 worked side-by-side examples covering 1:1 / VRL-enriched / decomposed patterns
├── write-correlation/
│   └── references/         # methodology, correlation_patterns (tag-join, name-fallback, entity pivots), detections_index_schema
├── recommend-detections/
│   └── references/         # methodology, recommendation_templates, coverage_heuristics, mitre_tags
└── report-as-html/
    ├── templates/          # cream-light.html — canonical skeleton with inline CSS
    └── references/         # style-guide.md (CSS palette + when to use each color), components.md (md → HTML mapping)
```

Each skill folder is self-contained: `SKILL.md` is the entry point, `references/` holds longer methodology that the skill loads progressively, and `scripts/` holds bash helpers the skill shells out to.
