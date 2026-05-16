# Coverage heuristics

This file documents the judgments the skill uses to rank holes, prioritise rules, and decide what's worth recommending. The point isn't to enumerate every possible rule — it's to surface a small, high-confidence punch-list.

## Hole-ranking weight

```
score(tactic, source) = tactic_priority(tactic) × log_volume(source) × novelty_bonus
```

### Tactic priority (1.0 baseline)

| Tactic | Priority | Why |
|---|---|---|
| `initial_access` | 1.0 | First step of any successful attack; high-leverage to detect |
| `credential_access` | 1.0 | If you catch this, you cut off downstream attacks |
| `privilege_escalation` | 1.0 | Late-stage, high-impact |
| `defense_evasion` | 1.0 | Often the only signal during an active intrusion |
| `exfiltration` | 0.9 | High-impact but often too late |
| `impact` | 0.9 | Catastrophic; alerts must reach humans fast |
| `execution` | 0.7 | Lots of FP potential in endpoint environments |
| `persistence` | 0.7 | Important but slower-moving |
| `command_and_control` | 0.7 | Network rules often noisier than cloud rules |
| `discovery` | 0.5 | Often-noisy; lower priority unless paired with another tactic |
| `lateral_movement` | 0.5 | Highly source-specific (need internal logs) |
| `collection` | 0.4 | Late-stage; usually caught downstream of exfiltration |
| `reconnaissance` | 0.3 | High-volume baseline noise on most internet-facing tenants |
| `resource_development` | 0.3 | Pre-attack; rarely catchable from victim's logs |

### Log-source volume (log scale)

Compute the source's 24h event volume. Score:

```
log_volume_score = log10(events_per_day / 100)   # capped at 5.0
```

A source with 1k events/day scores ~1.0; with 1M events/day scores ~4.0; with 100M+ scores 5.0. The intent is that volume matters but doesn't dominate.

### Novelty bonus

`novelty_bonus = 1.5` if the tactic × source cell has **zero** user-controlled rules, `1.0` otherwise. Strong preference for filling empty cells over deepening already-covered ones.

## What makes a Track B (tuning) candidate

A rule belongs in Track B if any of:

1. **High-volume Medium+ rule.** Fire-count ≥ 10/day at severity ≥ Medium over 30 days. Medium+ rules that fire 10+ times daily are almost certainly mis-classified or mis-tuned.
2. **Low/Information rule with absurd volume.** Fire-count ≥ 500/day at any severity. Even signals shouldn't be that noisy if they're meant to feed correlations.
3. **Zombie.** Never fired in 30 days, or last-fired > 90 days ago. Either the rule is broken (wrong field path, source no longer ingested) or it's a rare-event rule that should be checked.

Cap Track B at 5 to keep the report scannable. If there are more candidates, pick the highest-impact (count × severity).

## What makes a Track C (correlation) candidate

A co-firing pattern qualifies if all of:

1. **≥ 2 distinct rule names** fired on the same `results_table.rows[0].<entity>` in the last 30 days.
2. **The rules cover different MITRE tactics.** Two rules with the same tactic firing together is less surprising than rules from different tactics — the latter is more likely a real attack chain.
3. **The entity is not a trivial outlier** — a service account that legitimately appears in every alert isn't a correlation signal, it's a known-noisy entity. Heuristic: exclude entities that appear in >50% of all detection events.
4. **None of the candidate constituents are already participating in another correlation** — re-correlating is usually wrong.

Suggested correlation tag label: derive from the dominant tactic combination, e.g., `correlation.credential_theft_to_persistence`, `correlation.cloud_lateral_movement`.


## What makes an OOB pack worth recommending

A pack from the canonical list in `references/oob_packs.md` (the `scanner-inc/detection-rules-*` repos) is worth surfacing if:

1. **The log source is ingested.** (Pack for `azure` is useless if Azure isn't onboarded.)
2. **The user has no rules covering that source.** (Pack for `cloudtrail` is redundant if the user already has 20+ CloudTrail rules.)
3. **The user has not cloned individual rules from this pack into their local corpus.** (Suggests they intentionally don't use the OOB version.)

For ingest-source matching, compare the pack name's source-slug against the user's `@scnr.source_type` distribution. Examples:
- `detection-rules-aws-cloudtrail` ↔ `aws:cloudtrail`
- `detection-rules-okta` ↔ `okta`
- `detection-rules-github` ↔ `github:audit`
- `detection-rules-gsuite` ↔ `gsuite`
- `detection-rules-1password` ↔ `1password:audit`
- `detection-rules-azure` ↔ `azure:*` (any Azure source)

Each OOB pack recommendation includes the GitHub URL (`https://github.com/scanner-inc/detection-rules-<source>`) and the UI-enable step.

## Top-5 picking heuristic

The Top 5 is the most important section — it's what the user reads if they read nothing else. Pick across tracks:

1. **At least one Track B** if there's a screamingly noisy rule (>50/day Medium+). Tuning that should come before adding more rules.
2. **At least one Track A or migration suggestion** that targets a high-priority hole (initial_access / credential_access / defense_evasion on a high-volume source).
3. **A correlation candidate** if there's a strong co-firing pattern (3+ rules, mixed tactics, on a small set of entities).
4. **An OOB pack** if there's a clear no-rules-for-this-source gap.
5. **Whatever else stands out** as concretely impactful.

If the user has fewer than ~10 rules total, skip Track B and lean toward Track A and OOB packs — they need *more* rules before they need *better* rules.

## Things to avoid

- **Generic advice.** "Improve coverage" doesn't help. Always name a specific rule, source, or tag.
- **Repeating posture-report.** Posture-report already says "0 actionable alerts in 24h." Don't repeat that — say what to *do* about it.
- **Over-recommending.** A report with 30 items is a report nobody acts on. Cap each section, hard.
- **Recommending against the data.** If the user has no GitHub data, don't propose GitHub rules. If they have no Azure ingest, don't propose Sentinel migrations.
