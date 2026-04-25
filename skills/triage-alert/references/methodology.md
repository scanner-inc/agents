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

Emit the report in terminal markdown using the template below. Substitute bracketed placeholders with actual findings. Omit the `MITRE ATT&CK` line entirely unless the classification is MALICIOUS.

```
🚨 Security Alert Investigation

Alert ID: <id from the alert payload>
Alert: <name field> | Severity: <severity field>

TL;DR: <2-sentence summary. First sentence: what was detected and the classification. Second: key finding and recommended action.>

Classification: 🟢 BENIGN | 🟡 SUSPICIOUS | 🔴 MALICIOUS
Confidence: NN% (High | Medium | Low)

Timeline:
- `<timestamp>` <First relevant event in the investigation window>
- `<timestamp>` <Subsequent event>
- `<timestamp>` Alert triggered: <The detection event>
- `<timestamp>` <Any post-alert activity>

Hypothesis Testing:
- ✓ <Confirmed hypothesis with brief reasoning>
- ✗ <Ruled out alternative 1>
- ✗ <Ruled out alternative 2>

Key Evidence:
- <Finding 1 with `technical details` and timestamp>
- <Finding 2 with `code formatting` for IPs/users>
- <Finding 3>

> <Blockquote for the most critical evidence or context>

MITRE ATT&CK: <only if MALICIOUS — list canonical tags like techniques.t1078.valid_accounts>

Recommended Next Questions:
- <Follow-up to validate or deepen the investigation>
- <Question about gaps or unknowns>
- <Question about broader context>
```
