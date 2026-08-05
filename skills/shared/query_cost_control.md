# Query cost control: measure before you scan

Shared reference for every skill that runs Scanner MCP queries. Read this before choosing any
time window wider than a few hours.

## Scope: ad-hoc MCP queries ONLY, never deployed rules

Everything in this file is about ad-hoc queries run through Scanner MCP: exploration, sampling,
backtests. **None of it applies to a deployed detection rule.** The detection engine is a
streaming engine: it evaluates rules incrementally as data ingests and caches partial results, so
a rule's production evaluation cost is negligible and does not scale like an ad-hoc scan.
Backtesting a rule via MCP pays ad-hoc rates; running the same rule in production effectively
does not.

Concretely: never choose `time_range_s` or `run_frequency_s` to "save scan cost". Reasoning like
"hourly evaluation scans 600 GB/day but 5-minute evaluation would scan 7 TB/day" is a wrong model
of the engine, and acting on it trades away alert latency for a saving that does not exist. Pick
those fields for detection semantics and latency only.

## The two budgets

**Target: every MCP query returns in a few seconds.** At observed scan rates that is roughly
**500 GB scanned**. This is THE budget; every other file that mentions a scan budget means this
number. Recalibrate it here, not in the satellites.

**Hard ceiling: 60 seconds**, roughly **6 TB scanned** at a conservative rate. Never go here
routinely. If a query needs this much, the filter is wrong, not the window.

The MCP query path also has a hard **300-second** limit: the blocking wrapper the MCP server uses
polls for completion, gives up at 300s, cancels the query, and returns a gateway timeout (the web
UI's non-blocking path has no such limit). Do not plan against it: at observed rates you would
have to scan tens of TB to hit it, far past both budgets above.

Scan-rate numbers behind these conversions, measured 2026-08 on one production tenant (other
clusters may differ; the byte budgets are the portable part): ~190 GB/s p50 and ~100 GB/s slow
decile on large queries; largest observed *completed* query 44 TB in 54s; the only observed
timeouts were 184+ TB scans.

Scan volume is billable infrastructure work, and it draws down the tenant's **monthly query
capacity**: tenants have a GB-per-month limit, and exceeding it can get further queries throttled
for the whole team. Treat every TB as something you spent, and prefer the query that answers the
question for the fewest bytes.

## The failure this prevents

Skills used to pick windows in **days** ("needle: 30-90d, broad: cap at 7d"). Days is not a unit of
cost. In a tenant ingesting 8 TB/day, a "safe" 7-day broad aggregation scans ~56 TB: about 100x
over the target budget, ~9x over the hard ceiling, and into the range where real timeouts have been
observed. In a tenant ingesting 20 GB/day the same 7 days is 140 GB and finishes instantly.

The fix: **budget in bytes and seconds, then derive the window.** Never the other way around.

## Three measured facts

Verified 2026-08 against a tenant whose largest index ingests ~599 GB/day:

1. **Scan cost is linear in window.** Same broad aggregation: 582 MB over 1 minute, 6.13 GB over
   10 minutes. So a short probe predicts a long window reliably.
2. **Selectivity dominates window by orders of magnitude.** A *needle* filter plus aggregation over
   a **full day** of that index scanned 274 MB. The *broad* version of the same aggregation over
   **one minute** scanned 582 MB. The needle covered 1440x more time for half the bytes.
3. **Therefore the aggregation is almost never the problem.** `| stats` and `| groupbycount` are
   cheap. What costs money is how many events survive the filter. "Don't aggregate over 7 days" is
   the wrong lesson; "don't aggregate over 7 days *of an unselective filter*" is the right one.

Corollary worth internalising: **needles are effectively free, so do not throttle them.** At 274 MB
per day of a 599 GB/day index, a 90-day needle backtest scans ~25 GB, well inside the few-seconds
target. Long backtests on selective filters are a Scanner differentiator. Use them.

## Step 0: probe ingest volume (once per session)

Run this before the first wide query. It tells you which cost regime the tenant is in.

```scanner
@index=_usage record_type=indexing_record
| stats sum(num_bytes_indexed) as bytes_indexed, sum(num_log_events_indexed) as events_indexed
  by destination_index.name
```

Window: the last 24h (use 7d divided by 7 if yesterday looks atypical).

Field names above are verified against `_usage`. Notes:

- `record_type` is one of `indexing_record` (what you want), `collect_record`, `query_record`.
- `_usage` accounts per **destination index**, not per source type. If one index carries several
  sources, add `index_rule.name` to the `by` clause to split it further.
- The probe is cheap: ~656 MB scanned for 24h of `_usage` in a 40-index tenant.
- Cache the result for the session. Do not re-run it per query.

Read the row for the index your query will actually touch, and classify:

| `bytes_indexed` per day | Tier | Broad-query headroom at the 500 GB target |
| --- | --- | --- |
| < 100 GB | **small** | 5+ days. Day-based windows are fine. |
| 100 GB to 1 TB | **large** | 12h to 5 days. Measure before going longer. |
| > 1 TB | **extreme** | Under 12h. Tighten the filter instead of shortening further. |

Needles are unconstrained in every tier.

## Step 0.5: always scope the query with `@index=`

**Every MCP query you run for exploration, sampling, or backtesting should carry an `@index=<name>`
clause.**

`@index=` is different in kind from a filter predicate. It is a **real partition of the search
space**: it decides which indexes get opened at all. `@scnr.source_type` is a predicate evaluated
*within* whatever indexes are already open, so it narrows which events match but not how much data
is searched. Adding a source-type filter is not a substitute for scoping.

**How much it saves is data-dependent, not a fixed multiplier.** It is driven by how much of the
tenant's data lives outside your target index:

- **Upper bound** on the saving is roughly `total readable bytes / target index bytes`.
- **The realized saving is well below that bound**, because the filter's own selectivity already
  prunes inside every index it opens.
- **When your target index is the tenant's dominant index, scoping saves almost nothing.**

Measured 2026-08, same filter, same 7-day window, same aggregation, in a 40-index tenant ingesting
~1.5 TB/day total:

| Target index | Its share of tenant | Naive bound | Actual saving |
| --- | --- | --- | --- |
| `github`, ~0.9 MB/day | 0.00006% | ~1,600,000x | **~15,000x** (37.5 GB → 2.5 MB) |
| the 599 GB/day index | ~40% | ~2.5x | ~2.5x at best |

So: scope a small index out of a big tenant and the win is enormous; scope the biggest index and it
is marginal. Do it either way, because it costs nothing, never hurts, and you usually do not know
the ratio before you look.

Consequences:

- When no `@index=` is present, the volume number that matters is the **sum** of all rows from the
  Step 0 probe, not the biggest one.
- If you do not know which index holds the source, find out (`get_scanner_context`, or a single
  scoped `| head 3` probe per candidate) rather than running an unscoped wide query.
- **A detection rule's shipped `query_text` is a separate question.** Rules usually should *not* pin
  an index, so they keep working as data moves. That portability argument applies to the YAML, never
  to the ad-hoc MCP queries you run while authoring it. Scope your queries; leave the rule portable.

## Step 1: derive the window from the budget

```
max_days = budget_bytes / (bytes_per_day * selectivity)
```

What that yields at the 500 GB target:

| Tenant volume (target index) | Selectivity ~0.05% (needle) | Selectivity ~100% (full scan) |
| --- | --- | --- |
| 20 GB/day | years | ~25 days |
| 600 GB/day | years | ~20 hours |
| 8 TB/day | ~4 months | **~1.5 hours** |

This is the whole point. At 8 TB/day an unselective aggregation exhausts the budget before it
reaches a single day, while a needle runs for months. A fixed "7 days" rule is wrong in both
directions.

When the derived window is uselessly short, that is a signal to fix the *filter*, not to spend more
bytes.

## Step 2: measure selectivity instead of guessing it

Do not classify the filter as needle or broad by eyeballing it. Measure it.

**The ladder.** Run the real query (filter *and* aggregation, exactly as it will ship) over a
1-hour probe window. Read `n_bytes_scanned` from the response metadata.

```
selectivity = probe_scanned_bytes / (bytes_per_day * probe_hours / 24)
projected   = probe_scanned_bytes * (target_window / probe_window)
```

- **selectivity < ~1%** the filter is index-served. Go long: 30-90 days, often more. This is cheap;
  do not talk yourself out of it.
- **selectivity ~1% to 50%** partial scan. Compute `max_days` from the budget and use it.
- **selectivity > ~50%** treat as a full scan. Cost tracks the window linearly with no relief.
  Derive the window from the budget and do not exceed it. (Scan accounting can exceed
  `bytes_indexed`, so a full scan often measures slightly above 100%. That is expected.)

If `projected > budget`, do not run the target window. Either shrink it to what the budget allows
or apply a remedy from Step 3.

Escalate 1h to 24h to target rather than jumping straight to the target window. Each rung costs
about what it scans, so the ladder itself is nearly free, and it fails cheap.

**Skip the ladder when the probe is unnecessary.** On a **small**-tier index, or when the filter is
obviously a needle and the window is under 90 days, just run it. The ladder is a guard for expensive
queries, not a ritual. Two extra probe queries on a 5 GB/day index is pure overhead.

**`n_bytes_scanned == 0`** is a separate signal, not a cheap query: the index has no data in that
range. Stop and tell the user to check the index name and the data's ingestion window.

## Step 3: when the budget will not stretch

Ranked best to worst. Prefer the top of the list.

1. **Tighten the filter.** Add a selective token predicate (a specific `eventName`, a specific user
   agent token, a specific error string). This buys orders of magnitude, unlike everything below it,
   which only trades away coverage. A leading wildcard (`field:*value`) is slow and buys no
   selectivity; a trailing one (`field:value*`) is fine.
2. **Scope the index.** Add `@index=<name>` if you somehow have not already (see Step 0.5). Check
   this before anything below: on a small index in a large tenant it can dominate every other lever.
3. **Chunk the window.** Run N sequential single-day queries and sum the results. Note this costs
   the *same total bytes*, so it buys latency per query, not savings. Use it only when the user
   genuinely needs the full range.
4. **Sample a sub-window.** Query a contiguous representative slice, then extrapolate the rate.
   Only with an explicit label: "measured over 12h, extrapolated to 30d". This is the cheap option.
5. **Drop the aggregation and count first.** `| count()` on the filter alone tells you the match
   volume, which is usually the number you needed before writing the `stats` clause.

**Never silently shorten a window and report the result as if it covered the range you named.** If
you capped, say what you ran and why, with the numbers.

## Keep the whole invocation cheap, not just each query

A skill run makes many queries, and the 500 GB budget is per query. Watch the running total too:
plan an invocation so that **at most one query approaches the per-query budget** (usually the
backtest) and everything else stays in the probe/sample regime of a few GB. An invocation whose
every query burns hundreds of GB is misdesigned even though each query individually passes.

Practical habits, including two facts verified in the MCP server source:

- **`get_scanner_context` is itself an expensive call**: it runs an unscoped 1-hour
  `* | groupbycount` across every readable index to build its `source_types` block, roughly the
  tenant's hourly ingest in scan cost (~120 GB measured on a 1.5 TB/day tenant). Call it once per
  session and never re-call it to "refresh". Its `source_types` block is a 1-hour volume signal
  you already paid for; reuse it before running any volume query of your own.
- **`get_top_columns` is metadata-backed and does not scan log data.** Use it freely to discover
  fields; prefer it over sampling events when the question is "what fields exist".
- Reuse the Step 0 probe rather than re-running it.
- Reuse sampled events across phases instead of re-querying for them.
- **Never scan the same window twice with the same filter.** A filter-alone check followed by the
  full query over the same range pays double for one answer; combine them into one query, or reuse
  the first result via `fetch_query_results`.
- Prefer `| head 5` over an unbounded sample; it terminates early. On a broad filter also shrink
  the sample window to minutes (measured: unfiltered `| head 3` over 1h of a 600 GB/day index
  still touched 40 GB).
- Prefer the builtin small indexes (`_detections`, `_usage`, `_audit`) over raw log scans whenever
  they can answer the question. They are orders of magnitude cheaper.
- Do not re-run a query just to reformat its output. Use `fetch_query_results` on the existing
  result handle.

## Group-by cardinality: the other way queries die

Distinct from scan volume. A `stats ... by <field>` over a high-cardinality field (request ID,
event ID, session token, an ARN with a random suffix) builds group state that hits the memory cap
and silently drops groups.

- Check `results_caveat` and `table_metadata` in every aggregation response. A `MemoryLimit` entry
  means groups were dropped: results are incomplete and must not be presented as exact. Surface it.
- **First remedy is lower cardinality**, not a bigger cap: group by the entity you actually want to
  pivot on (user, IP, host, role), not by a per-request identifier.
- Only then consider raising `max_bytes` (default 64 MiB, max 128 MiB) to recover dropped groups.
- `max_rows` (default 1000, max 100000) caps returned rows. A result with exactly `max_rows` rows
  may be truncated.
- Other `table_metadata` entries are informational; `MemoryLimit` is the one that invalidates
  results.

## Reporting to the user

Whenever a window was chosen or capped by cost, put the reasoning in the output as one line with
real numbers:

```
Volume: global-cloudtrail = 411 GB/day (large tier). Filter selectivity 0.05% (index-served).
Backtest: 90 days, 22 GB scanned, 4 matches, ~0.04 fires/day.
```

And when capped:

```
Volume: prod-use1 = 8.2 TB/day (extreme tier). Filter selectivity ~100% (full scan).
Capped the backtest at 90 minutes instead of 7 days to keep the query fast. Adding a specific
eventName predicate would make a 90-day backtest cheaper than this capped run.
```

The second form matters most: it turns a shrug into an actionable recommendation.

## Pre-flight

When a skill's pre-flight briefing mentions a window, and the target index is in the **large** or
**extreme** tier, state the tier and the intended window in the briefing so the user can redirect
before anything expensive runs.
