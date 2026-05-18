# Backtest regime — needle-in-haystack vs broad

Scanner's read path is fast on rare-event queries even over petabytes — that's a key differentiator. Lean into it. A 90-day backtest of a needle-in-haystack filter is fast and cheap; a 90-day backtest of a "give me all CloudTrail events" filter is slow and expensive.

This file tells you how to pick the window so the backtest is informative without burning a lot of time/money.

## The two regimes

### Needle-in-haystack

The first filter clause targets a **rare** event. Heuristics:
- `eventName` is a specific, low-volume API call (`PutUserPolicy`, `ModifySnapshotAttribute`, `CreateAccessKey`).
- `userAgent` contains a specific token (`S3 Browser`, `aws-sdk-go.<version>`).
- `errorMessage` matches a specific string (`access denied`).
- Filter combines 2+ token predicates that AND-narrow aggressively.

For these:
- **Window: 30–90 days minimum.** Often 180 days or more is fine — Scanner can do it.
- **Cost:** small (rare-event queries hit the index, not the data).
- **Why long:** to see the realistic firing rate. A 7-day window for a once-per-month behaviour will report zero, and the user will incorrectly conclude the rule is broken.

### Broad

The first filter clause hits a **high-volume** event class. Heuristics:
- `%ingest.source_type="aws:cloudtrail"` alone — that's millions of events per day in a typical tenant.
- `eventSource="iam.amazonaws.com"` alone.
- No `eventName` predicate.
- A wildcard like `**:value` (those are slow regardless).

For these:
- **Window: 1–7 days.** Cap at 7 days.
- **Cost:** larger (data scan).
- **Warn the user.** Phrase: *"This filter hits a high-volume event class, so I'm capping the backtest at 7 days to keep it cheap. We can go longer if you really need to."*

## How to tell which regime you're in

1. **Filter-clause sanity check (Phase 3).** Before going deep, run just the filter for 1 day. If it returns more than ~10,000 hits/day, you're in the broad regime. If under ~1,000/day, you're in needle-in-haystack. In between is fine either way.
2. **Bias toward needle.** If unsure, start with 30 days. If the count comes back >1M, drop to 7 days and tighten the filter before the full backtest.

## Backtest output format

After running the full query (filter + aggregations + threshold), report to the user in one line:

```
Backtest: needle-in-haystack, 90 days, 4 matches, ~0.04 fires/day in production
```
```
Backtest: broad, 7 days, 312 matches, ~45 fires/day in production
```

If the rule aggregates `by` an entity, also surface the top 5 grouping-key values by count — these are the candidates for tuning or exclusion.

## Special cases

- **`n_bytes_scanned == 0`** — distinct from "filter matched zero events". When the MCP query response's `metadata.n_bytes_scanned` is exactly **0**, the target index has zero data over the backtest window — either the index is empty entirely, or the time range predates / postdates all ingested data. **This is different from "we scanned data and the filter matched nothing"** (which has non-zero bytes scanned). Stop and tell the user: *"`@index=<alias>` returned `n_bytes_scanned: 0` over <window> — the index appears empty for that time range. Verify the index name and the data's actual ingestion window before proceeding."* Verified empirically 2026-05: empty index + wide range = 0; populated index + filter-misses = 5.5 GB scanned; populated index + pre-data range = 0.
- **Zero fires over the full window** (but `n_bytes_scanned > 0`). State it explicitly: *"The rule wouldn't have fired in the last 90 days. It's a future trip-wire, which is sometimes the right call — but if you expected hits and got zero, the filter is probably wrong."* Don't silently accept zero.
- **Too many fires for Medium+ severity.** Surface the loud groups from the top-5 list and propose specific tuning: extra filter, threshold, dedup window, or severity downgrade. See `severity_policy.md`.
- **Filter clause that uses leading wildcards** (`*value`) — flag as a perf risk. Suggest tightening to a token match: `roleArn:"integration-access"` (fast) instead of `roleArn:"*integration-access*"` (slow).

## Why no fixed window

The reason we don't default to "always 30 days" is that broad-filter rules can scan terabytes per day, and a blind 30-day window can be expensive. The user is here for *iterative* tuning — fast feedback matters more than perfectly long backtests.
