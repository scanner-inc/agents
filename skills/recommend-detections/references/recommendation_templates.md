# Recommendation templates

This file documents the exact markdown shape each recommendation section produces. The model fills these in. Trim any section that has nothing to recommend.

## Document skeleton

````
🧭 Scanner Detection Recommendations — <YYYY-MM-DD>

> <One-line opinionated headline. Lead with the most important move. Examples:
>  "Your `aws-cloudtrail` coverage is solid; the next move is onboarding `okta` rules — you have the data and zero detections on it."
>  "3 rules are firing 50+/day at Medium severity; tune those before adding anything new."
>  "You've got 4 zombie rules and a co-firing pattern around `userIdentity.arn=*ci-deployer*` — both worth a look this week.">

## 🎯 Top 5 next moves
…

## 📈 Coverage matrix
…

## 🆕 New rule ideas (Track A)
…

## 🔧 Tuning opportunities (Track B)
…

## 🔗 Correlation opportunities (Track C)
…

## 📦 OOB packs to enable
…
````

## `🎯 Top 5 next moves` template

The opinionated short-list — items the user should act on this week. Pick across tracks; don't just take the first item from each.

```
1. **<Action verb + concrete target>** — <one-line rationale that doesn't repeat data from elsewhere in the report>
   → `/<skill-name> <args>`
2. **<…>** — <…>
   → `/<skill-name> <args>`
…up to 5.
```

Rules for picking the 5:
- Mix tracks (don't list 5 tunings).
- Skip items that depend on prerequisites unless the prerequisites are also in the list (e.g., don't recommend a correlation rule whose constituents the user hasn't tuned yet).
- Prefer items where the user has the data already (skip Track A items that need data they don't ingest).

## `📈 Coverage matrix` template

Compact. Use a code block so the columns align.

```
                       cloudtrail  okta  github  gsuite  azure-signin
initial_access              4        0      0       0          1
execution                   1        0      0       0          0
persistence                 3        0      1       0          0
privilege_escalation        5        0      0       0          0
defense_evasion             7        0      0       0          0
credential_access           4        2      0       0          1
discovery                   2        0      0       0          0
lateral_movement            0        0      0       0          0
collection                  0        0      0       0          0
exfiltration                1        0      0       0          0
command_and_control         0        0      0       0          0
impact                      2        0      0       0          0
reconnaissance              0        0      0       0          0
resource_development        0        0      0       0          0
```

(Show cells as integer counts. Rows: tactics ordered by the canonical Scanner list. Columns: ingested log sources, ordered by ingest volume desc. Width: keep under 80 cols if possible.)

Optionally append a one-line summary: *"22 user-controlled rules covering 9 of 14 tactics across 3 of 5 ingested sources. Holes concentrated in `okta`, `github`, `gsuite`."*

## `🆕 New rule ideas (Track A)` template

Up to 10 entries, ranked by priority. Each:

```
- **<Behaviour description>** · `source.<slug>` · `<technique tag>`
  Filter sketch: `<starting query fragment>` · Backtest regime: <needle-in-haystack | broad>
  Rationale: <one line — why this hole matters in this environment>
  → `/write-detection <one-line natural-language description for the skill to consume>`
```

Example:
```
- **Detect Okta admin role grants from non-corporate IPs** · `source.okta` · `techniques.t1098.account_manipulation`
  Filter sketch: `@scnr.source_type="okta" eventType="user.account.privilege.grant" source.classification="non_corporate"`
  Backtest regime: needle-in-haystack (admin grants are rare)
  Rationale: Okta is ingesting 8k events/day but has zero rules covering account manipulation; this would catch attacker pivots after credential theft.
  → `/write-detection write a rule for Okta admin role grants from non-corporate IPs`
```

If the user doesn't have a custom enrichment field available (e.g., `source.classification`, `principal.account.class`, or an `@ecs.*` equivalent), drop it from the sketch and mention the dependency in the rationale, with a hint to invoke `/write-vrl`.

## `🔧 Tuning opportunities (Track B)` template

Up to 5 entries. Each:

```
- **`<rule name>`** firing <N>/day at <Severity> — <one-line description of the suspected noise pattern>
  Loudest group: `<pivot>=<value>` (<X> fires) · Suggested first cut: <filter / threshold / dedup / severity downgrade>
  → `/tune-detection <rule name or rule_id>`
```

Plus zombie rules:

```
- **`<rule name>`** has not fired in 30d — possibly broken filter, wrong source-type, or stale rule
  → `/tune-detection <rule name or rule_id>`
```

Group these visually if there are many (one block for noise, one for zombies).

## `🔗 Correlation opportunities (Track C)` template

Up to 5 entries. Each:

```
- **<Entity-pivot description>** — <N> distinct rules firing on the same pivot in 30d
  Pivot: `results_table.rows[0].<col>` · Constituent rules: `<rule A>`, `<rule B>`, `<rule C>`
  Suggested correlation tag: `correlation.<scoped_label>` · Suggested severity: <one level above loudest constituent>
  → `/write-correlation <rule A>, <rule B>, <rule C>`
```

Prefer correlations where the constituent rules cover different tactics — those are higher-value alerts.

## `📦 OOB packs to enable` template

Up to 5. Each:

```
- **`detection-rules-<source>` pack** (~<N> rules)
  Covers: `source.<slug>`, MITRE: `<tactic tags>`
  GitHub: https://github.com/scanner-inc/detection-rules-<source>
  → In Scanner UI: Settings → Sync Sources → Add Sync Source → paste the GitHub URL.
  Set rules to `Staging` initially to monitor noise before promoting to `Active`.
```

Don't include packs where the user has already cloned individual rules into their local corpus (suggests intentional fork-and-disable).

## Closing line

End the report with the last bullet of the last non-empty section. No trailing summary, no "let me know if…" — terminal output, not chat.

## House style

- Verdict blockquote first, no preamble.
- Today's date in `YYYY-MM-DD` form.
- All MITRE tags as canonical IDs (`tactics.ta0005.defense_evasion`).
- Log sources as slugs (`aws-cloudtrail`, `okta`).
- Backtick rule names, field paths, tag IDs.
- Commands at the end of each entry — copy-paste ready, no placeholders to fill.
