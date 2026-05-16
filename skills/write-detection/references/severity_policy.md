# Severity policy — alerts vs signals

Scanner detections fall into two operational roles depending on severity:

- **Alerts** — *page* a human (or AI triage agent). Routed to event sinks.
- **Signals** — do **not** page anyone on their own. Land in the `_detections` index, where correlation rules can pick them up later.

## The line

| Severity | Role | `event_sink_keys` | Examples |
|---|---|---|---|
| `Fatal` | Alert | `fatal_severity_alerts` | Catastrophic events. Use sparingly. |
| `Critical` | Alert | `critical_severity_alerts` | Active compromise; ransomware staging; root credential misuse. |
| `High` | Alert | `high_severity_alerts` | Privilege escalation, IAM tampering, S3 bucket made public, MFA disabled. |
| `Medium` | Alert | `medium_severity_alerts` | Suspicious-but-not-confirmed behaviour. The lowest severity that should ever page. |
| `Low` | **Signal** | (none) | Anomalous-but-common behaviour. Useful when correlated. |
| `Informational` | **Signal** | (none) | Visibility-only; baseline reconnaissance noise; per-row diagnostics. |
| `Other`, `Unknown` | Avoid | (none) | Don't introduce new rules at these. |

## Why the split

- A SOC analyst can review ~100 alerts/day without burnout. The **alert** bucket has to stay in that budget.
- A correlation engine can chew through 100,000 signals/day. The **signal** bucket has no realistic upper bound.
- A rule that fires more than ~10 times/day at Medium+ is misclassified — either it should be a signal, or it needs a threshold (`| where @q.count > N`) or a `dedup_window_s`.

## How to pick

1. Start by asking: **if this rule fires once, should a human stop what they're doing to look?** If yes → Medium+. If no → Low/Informational.
2. If your draft puts the rule at Medium+ but the backtest fires more than ~10/day, you have three choices in order of preference:
   a. **Tighten the filter** (add a predicate that excludes the loud cases).
   b. **Add a threshold** (`| stats count() as eventCount by … | where eventCount > N`).
   c. **Downgrade to Low/Informational** and let a correlation rule promote it when paired with another signal.
3. Default for a brand-new rule with no firing history: **Medium** if the behaviour is genuinely suspicious; **Low** if it's "interesting but not actionable alone".

## `event_sink_keys` convention

When a rule has Medium+ severity, set `event_sink_keys` to the matching key:

```yaml
severity: High
event_sink_keys:
  - high_severity_alerts
```

Customers configure which actual destinations (Slack channel, PagerDuty service, email, SOAR webhook) those keys map to in the Scanner UI under Settings → Event Sinks. The skill never edits sink mappings — only the keys.

A rule can ship to multiple sinks:

```yaml
event_sink_keys:
  - high_severity_alerts
  - soar_response_flow
```

For Low / Informational rules, **omit `event_sink_keys` entirely**. Setting it to an empty array (`event_sink_keys: []`) is permitted but confusing — just leave the field out.

## Staging vs Active

This is separate from severity, controlled by `enabled:`:

| `enabled` value | Behaviour |
|---|---|
| `Active` | Runs. Sends detection events to `event_sink_keys`. |
| `Staging` | Runs. Writes to `_detections` index. **Does NOT send to event sinks.** |
| `Paused` | Doesn't run at all. |

**New rules are always written in `Staging`** so the user can watch a few days of `_detections` activity (use `/posture-report` or query `_detections` directly) before promoting to `Active`. To promote, the user edits the YAML, changes `enabled: Staging` → `enabled: Active`, and pushes — the Scanner GitHub app re-syncs.
