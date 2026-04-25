# triage-alert — methodology

Read this file when the user invokes `/triage-alert <id>` or asks Claude to investigate a specific Scanner alert. SKILL.md handles the alert lookup; this file is the post-lookup investigation procedure and the output template.

## Phase 1: Initial assessment and hypothesis generation

1. Review the alert document fetched in Phase 0 (the lookup step in SKILL.md). Understand what the detection rule is looking for — read `name`, `description`, `query_text`, and `tags` (MITRE tactics/techniques).
2. Generate 2-4 hypotheses ranked by probability:
   - Benign (legitimate user activity, known process)
   - Misconfiguration (incorrect rule, system issue)
   - Actual attack (malicious activity, compromise)
   - Insider threat (authorized user acting maliciously)
3. For each hypothesis, identify what evidence would confirm or refute it.

## Phase 2: Evidence collection

Use Scanner MCP `execute_query` to collect targeted evidence around the alert's `detected_in_time_range`:

- Query a 4-6 hour window centered on the detection time. Run separate queries for BEFORE, DURING, and AFTER if the detection is a point-in-time event.
- Pivot on the alert's identifying fields — same source IP, user, account, role, instance, etc.
- Think adversarially: if this were an attack, what would the attacker do next? Check for expansion indicators:
  - Privilege escalation or role changes
  - Lateral movement / unusual network connections
  - Data access anomalies or exfiltration patterns
  - Persistence mechanisms (new users, scheduled tasks, backdoors)
  - Multiple failed attempts followed by success

### Threat-intel enrichment

For any external IOCs (IPs, domains, URLs, file hashes) that surface in the evidence, invoke the `lookup-ioc` skill or call `../lookup-ioc/scripts/lookup_ioc.sh <indicator>` directly. A hit on ThreatFox/OTX/Feodo is strong evidence of compromise. Absence of a hit is weak evidence — many real threats are not in public feeds.

## Phase 3: Classification

Classify the alert:

- **BENIGN** — Weight of evidence points to legitimate activity. Includes cases where the activity pattern is well-established (recurring user, known IP, business hours, expected role chains) even if some fields are redacted. Redacted parameters are a *visibility gap*, not evidence of malice. If you can explain WHO did it, WHY it is expected, and there are ZERO indicators of compromise, classify as BENIGN.
- **SUSPICIOUS** — Concrete anomalies that don't fit legitimate patterns: new IP, unusual time, unexpected role, first-time access, failed attempts before success. Visibility gaps alone do not make something suspicious.
- **MALICIOUS** — High-confidence evidence of attack with corroborating indicators (known-bad IOCs, persistence mechanisms, data exfiltration, multiple ATT&CK techniques chained together).

Confidence:
- **High (80-100%)** — multiple independent evidence sources support the conclusion.
- **Medium (60-79%)** — moderate support with some gaps or contradictions.
- **Low (0-59%)** — insufficient evidence to confidently support any hypothesis.

## Phase 4: Self-critique (run twice)

After your initial classification, critique your own analysis:

- What evidence might you have missed?
- Are there alternative explanations you didn't consider?
- Is your confidence level justified by the evidence?
- What would change your classification?

Revise if the critique reveals weaknesses. Run the critique loop twice — once on the first draft, once on the revised draft.

## Phase 5: Final output

Emit the report in terminal markdown using the template below. Substitute bracketed placeholders with actual findings.

```
🚨 Security Alert Investigation

> <One-line headline verdict in plain English. Lead with the classification and the most consequential nuance — this is the one sentence a reader who reads nothing else would walk away with. e.g. "🟡 SUSPICIOUS — textbook T1098 priv-esc pattern, but the source IP is RFC 5737 reserved space suggesting demo data; verify out-of-band before acting.">

Alert: <name field>
ID: `<id field>` · Severity: <severity field> · Classification: 🟢 BENIGN | 🟡 SUSPICIOUS | 🔴 MALICIOUS · Confidence: NN% (High | Medium | Low)

TL;DR: <2 sentences. First: what was detected and the classification. Second: the key finding and the recommended next action.>

Timeline:
- `<timestamp>` <First relevant event in the investigation window>
- `<timestamp>` <Subsequent event>
- `<timestamp>` Alert triggered: <The detection event>
- `<timestamp>` <Any post-alert activity>

Hypothesis Testing:
- ✓ <Confirmed hypothesis — one-sentence reasoning>
- ✗ <Ruled out alternative 1 — why>
- ✗ <Ruled out alternative 2 — why>

Key Evidence (interpretations the reader can't infer from Timeline alone — not restated facts):
- <Finding 1 — the *meaning* of the evidence, not a re-quote of what's already in Timeline. Each bullet adds something Timeline didn't.>
- <Finding 2>
- <Finding 3>

MITRE ATT&CK: <Cite tactics and techniques by canonical tag (e.g., `techniques.t1098.account_manipulation`, `techniques.t1098.003.additional_cloud_roles`). Include this line whenever any techniques apply, regardless of classification — a SUSPICIOUS or BENIGN alert can still map to a technique. Omit the line only when no techniques are relevant.>

Next questions (cap at 2; only include if they would actually unblock further work):
- <Follow-up that would close a gap or deepen the investigation>
- <Follow-up about broader context>
```

Output rules:
- The verdict blockquote leads. There is no other blockquote in the report — don't scatter `>` lines across sections.
- Key Evidence carries *interpretations*, not restated facts. If a bullet only re-quotes a Timeline event, drop it.
- MITRE ATT&CK is included whenever techniques apply, regardless of classification. Only omit if no techniques are relevant.
- Cap *Next questions* at 2 — and skip the section entirely if the only follow-ups would be filler.
