---
name: triage-alert
description: Look up a Scanner detection alert by id and run a full triage investigation — hypothesis generation, evidence collection from surrounding logs, classification (BENIGN / SUSPICIOUS / MALICIOUS) with confidence, self-critique, and a structured report. Use when the user types `/triage-alert [id]`, pastes a Scanner alert id, or asks Claude to "triage", "investigate", or "look at" a specific alert by id. Requires Scanner MCP configured in Claude Code.
---

# triage-alert

## Workflow

### Phase 0 — Look up the alert by id

The user gives an alert id. The alert may be days, weeks, or months old, so search a wide time range.

1. Call Scanner MCP `get_scanner_context` if you have not already in this session — you need the context token plus the canonical name of the detections index (commonly `_detections`, but confirm from the context response).
2. Call Scanner MCP `execute_query` with this query template:
   ```
   @index=<detections index from get_scanner_context> id: "<alert_id>"
   ```
   Set the time range to the last **180 days** (`from = now - 180d`, `to = now`). If the query returns zero rows, widen to 365 days and retry once. If still zero, stop and tell the user the alert id was not found in the last year — do not fabricate.
3. The returned document is a Scanner alert with these key fields (see `n8n/alert-triage/sample-payloads/example-alert.json` in the parent repo for the exact shape):
   - `id`, `detection_rule_id`, `tenant_id`
   - `severity`, `severity_id`, `name`, `description`, `query_text`, `tags`
   - `detected_in_time_range` — `{start, end}` ISO timestamps (use this to anchor the investigation window in Phase 2)
   - `results_table` — the rows that triggered the rule
   - `View in Scanner` — a UI deep link

Now load `references/methodology.md` and proceed through phases 1-5.

### Phases 1-5 — Investigation

`references/methodology.md` carries the full procedure (hypothesis generation, evidence collection, classification rubric, self-critique, output template). Read it, follow it, emit the report exactly as templated.

## Threat-intel enrichment

When the methodology calls for IOC enrichment in Phase 2, prefer invoking the `lookup-ioc` skill (or call its script directly with `../lookup-ioc/scripts/lookup_ioc.sh <indicator>`). The script fans out across ThreatFox, OTX, and Feodo Tracker in parallel and returns a single JSON object — much cheaper than three sequential MCP/HTTP calls.

## Required environment

- Scanner MCP configured in Claude Code (used for both the alert lookup and the evidence-collection queries).
- For IOC enrichment via `lookup-ioc`: optionally `OTX_API_KEY` and `ABUSECH_AUTH_KEY`. The lookup degrades gracefully if missing.

## Output

Terminal markdown only — see the template at the bottom of `references/methodology.md`. Begin the response with the 🚨 line; end with the final *Next questions* bullet (or with the *MITRE ATT&CK* line if no follow-ups are worth listing). No preamble, no trailing commentary.
