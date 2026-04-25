---
name: investigate
description: Answer a free-form security or detection-engineering question against the user's Scanner tenant using a summarize → plan → execute workflow — restate the question, draft a 3-6 bullet investigation plan grounded in the actual environment schema, then run that plan with Scanner MCP and return a structured finding. Use when the user types `/investigate [question]`, asks an open-ended security question that needs Scanner data ("did anyone exec from a public S3 bucket today?", "are there any failed Okta logins from new countries?", "which rules cover MITRE T1078?"), or asks Claude to "investigate", "look into", or "check on" something in the logs. Requires Scanner MCP configured.
---

# investigate

This skill mirrors the slack-bot's three-step pattern (summarize -> plan -> execute) for terminal use. The structure exists to keep the work disciplined — a one-line restatement forces clarity, a written plan keeps Scanner queries focused, and the execute step does only what the plan called for.

## Step 1 — Restate the question (one line, silent)

Before doing anything else, write a one-line internal restatement of what the user is actually asking. This is for your own use; do not print it. If the user's question is ambiguous (e.g. "check on that incident"), ask one short clarifying question instead of guessing.

## Step 2 — Plan (read-only Scanner MCP)

Draft a 3-6 bullet investigation plan. Use the **read-only** Scanner MCP tools to ground the plan in the actual environment — these return metadata only, they do not search log events:

- `get_scanner_context` — list the available indices and get the context token. Call this first if you have not already in this session.
- `get_top_columns` — most common fields in a given index. Use when the plan depends on field names you are not sure exist.
- `get_docs` — Scanner query syntax reference, when needed.

Do **not** run `execute_query` yet. Keep schema exploration to 1-3 tool calls. If you find yourself wanting to search for a specific user or IP, that's a hint the item belongs in a plan bullet, not a tool call at this step.

Write the plan as concrete bullets. Each bullet is one short sentence — a verb plus a target. Name the index, source, threat-intel call, or rule inventory you intend to consult. **Do not** paste Scanner pipe syntax (`| stats ...`, `| groupbycount ...`, `| where ...`) — that belongs in Execute. The Plan exists so the user can spot a wrong direction in 5 seconds. Avoid vague bullets like "investigate the activity" or "check for anomalies".

Good — each bullet is skimmable:

```
Plan:
- Query @index=global-cloudtrail for all lambda:* events in the past 6h, grouped by eventName
- Filter for operations against function `system-maintenance-handler` specifically
- Check EventBridge PutRule and PutTargets calls in the same window to see how the Lambda was wired to a schedule
- Cross-reference source IP `31.41.59.26` against threat intel
- Look for CreateFunction / UpdateFunctionConfiguration loops that suggest redeployment persistence
```

Bad — full query syntax in the plan, unreadable at a glance:

```
- Query `@index=global-cloudtrail | stats count() as events by eventName, userIdentity.arn | where events > 5` over the last 6 hours to find anomalous Lambda calls
```

Print the plan to the user (a short `Plan:` header followed by bullets) before executing. Lets them spot a wrong direction before the queries run.

## Step 3 — Execute

Run the plan. Tools available at this step:

- **Scanner MCP** (full set): `execute_query`, `fetch_query_results`, `get_scanner_context`, `get_top_columns`, `get_docs`.
  - Use `@index=<name>` to narrow searches.
  - Group OR'd values in parentheses: `field: ("a" "b")`. **Never** bare `OR`.
  - All-fields wildcard search: `**: "<value>"`.
  - Run independent queries in parallel.
  - Stop running queries when the evidence is conclusive. Don't speculate.
- **Detection Rules REST API** (`${SCANNER_API_URL}/v1/detection_rule`, `Authorization: Bearer ${SCANNER_API_KEY}`) — for inventory questions like "what rules do we have for X" or "is there a rule covering MITRE technique Y". For "which rules fired recently", use a Scanner MCP query against `@index=_detections` instead — the REST API is inventory-only.
- **lookup-ioc** skill (or `../lookup-ioc/scripts/lookup_ioc.sh <indicator>`) — for any external IOC that surfaces during the investigation.

## Output

Read `references/output_template.md` and emit the report exactly as templated. The report begins with `✅ Finding` and ends with the last *Next questions* bullet. Aim for under 30 lines.

If the question is small ("did this user log in today?"), the answer should be small too — TL;DR and a single evidence bullet may be enough. Don't pad to fit the template.

## Required environment

- Scanner MCP configured in Claude Code.
- For Detection Rules REST API questions: `SCANNER_API_URL`, `SCANNER_API_KEY`. (Not needed for log-only questions.)
- For IOC enrichment: `OTX_API_KEY`, `ABUSECH_AUTH_KEY` — degrades gracefully if absent.
