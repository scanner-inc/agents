# Sentinel KQL → Scanner (decomposed + correlated): credential stuffing followed by anomalous-location success

**Source:** [`source.yaml`](./source.yaml) — synthetic Sentinel analytic rule using KQL `join`s across sub-queries.

**Targets:**
- [`scanner_rule_part_a_failed_burst.yml`](./scanner_rule_part_a_failed_burst.yml) — first decomposed rule (Low signal): failed sign-in burst.
- [`scanner_rule_part_b_anomalous_location.yml`](./scanner_rule_part_b_anomalous_location.yml) — second decomposed rule (Low signal): successful sign-in from anomalous country (requires VRL enrichment).
- [`scanner_correlation.yml`](./scanner_correlation.yml) — High-severity correlation rule joining both signals via `tags[*]:correlation.azure_credential_stuffing` on `UserPrincipalName`.

## The migration challenge

The Sentinel original is a single rule that uses KQL `join`s:

1. Compute `recentFailures` — users with 10+ failed sign-ins in the last hour.
2. Compute `userHistoricalCountries` — set of countries each user signed in from in the last 30 days, ignoring the last hour.
3. Take successful sign-ins in the last hour, `join` with `recentFailures` (require failure burst), `join` with `userHistoricalCountries`, and filter to where the current country isn't in the historical set.

Scanner can't express this in one rule — it doesn't have cross-table or cross-time-window joins inside a single `query_text`. This is Pattern C from `corpus_index.md` — decomposed + correlated migration.

## How the decomposition works

| Sentinel KQL component | Scanner rule |
|---|---|
| `recentFailures` sub-query | `scanner_rule_part_a_failed_burst.yml` (Low signal, tagged `correlation.azure_credential_stuffing`) |
| `userHistoricalCountries` + `!in` check | A VRL transformation `azure_signin_anomalous_country` that maintains a per-user 30-day country set in a Scanner lookup table, plus `scanner_rule_part_b_anomalous_location.yml` which filters on the resulting `user.country_is_anomalous="true"` (also Low signal, tagged `correlation.azure_credential_stuffing`) |
| The `join` itself + the final detection | `scanner_correlation.yml` (High) joining the two signals via `tags[*]:correlation.azure_credential_stuffing` on the shared `UserPrincipalName` entity |

## Trade-offs vs the original

- **Temporal ordering is loosened.** Sentinel's `join` lets the rule express "the successful sign-in is AFTER the failure burst." Scanner's correlation matches "both fired in the window" without strict ordering. In practice this is rarely a problem: the failure rule needs 10+ failures over an hour to fire, so by the time it does, any preceding success would have already been visible.
- **The window slips slightly.** Sentinel's `lookback = 30d` for historical countries vs `queryFrequency = 1h` for the failures — Scanner's two rules each get their own `time_range_s`, and the correlation joins them in a 1h window. The historical-country logic moves out of the rule and into ingest-time VRL state, which is a more durable place for it.
- **Three artifacts to maintain** instead of one. The user has to keep the two signal rules and the correlation rule in sync. The corpus README's "Hand-off sequence" below makes this explicit.
- **Severity step.** The constituent rules are Low (don't page) — only the correlation pages, at High. This is a deliberate "signal then alert" promotion pattern.

## Hand-off sequence

1. **Install the VRL** (`azure_signin_anomalous_country`) and its `user_country_history` enrichment table. Use `/write-vrl` to author and test it.
2. **Commit and push all four artifacts** (the two signal rules and the correlation rule).
3. Wait one ingestion cycle so the VRL's enriched field is populated.
4. Scanner GitHub app validates and syncs.
5. All three rules start in `Staging`. Watch `_detections` for a few days. When you promote:
   - Promote the **constituents first** (Low) so the correlation has data to chew on.
   - Then promote the **correlation rule** (High).

## When to use this pattern

Any vendor rule that:
- Uses `join`, `transaction`, `streamstats`, `subsearch`, EQL `sequence`, or YARA-L multi-event `condition` blocks.
- Combines events across very different time windows (recent + historical).
- Combines events from different log sources.

If the source rule fits any of those, decomposition + correlation is usually the right shape.

## When NOT to use this pattern

- If the source rule's logic fits in one Scanner `query_text` — keep it as one rule. Decomposition adds maintenance overhead.
- If the source rule's temporal ordering is **load-bearing** (e.g., "fire only if A happens *before* B and *not after C*"), the correlation pattern may not preserve enough precision. In that case consider whether the rule is genuinely catchable in Scanner, or whether the user's threat-modelling needs to be adjusted to what the platform supports.
