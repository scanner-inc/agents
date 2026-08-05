# Backtest window: budget bytes, then derive days

Scanner's read path is fast on rare-event queries even over petabytes. That is a key
differentiator, so lean into it: a 90-day backtest of a selective filter is fast and cheap. A
7-day backtest of "all CloudTrail events" is neither: in a multi-TB/day tenant it scans tens of TB,
which is far over budget and slow enough to risk the server timeout.

**Read `../../shared/query_cost_control.md` first.** It carries the volume probe, the byte budget
formula, the selectivity ladder, and the remedies. This file covers only what is specific to
backtesting a detection rule.

## The short version

0. Scope the query with `@index=<name>`, independent of everything below. The rule's YAML stays
   unscoped; your MCP queries do not. Biggest win when the target index is a small slice of the
   tenant; see `../../shared/query_cost_control.md` Step 0.5.
1. Probe ingest volume once per session (`_usage`, `record_type=indexing_record`). Note the
   bytes/day for the index this rule will query, and its tier.
2. Run the rule's filter over a **1-hour** window. Read `n_bytes_scanned`.
3. Compute selectivity and project the cost of the window you want.
4. Pick the largest window that fits the shared scan budget (the few-seconds target; the number
   lives in `query_cost_control.md`). Report the
   window *and* why.

Do not skip to step 4 with a number you guessed. In a tenant at 8 TB/day, guessing costs the user a
slow, expensive query; measuring costs one cheap one. Always prefer the cheapest query that answers
the question.

## Regimes, restated as measurements

The old needle-vs-broad split is still the right mental model, but classify by the measured
selectivity from the ladder, not by reading the filter.

### Needle-in-haystack (measured selectivity < ~1%)

Typical shapes:
- `eventName` is a specific, low-volume API call (`PutUserPolicy`, `ModifySnapshotAttribute`,
  `CreateAccessKey`).
- `userAgent` contains a specific token (`S3 Browser`, `aws-sdk-go.<version>`).
- `errorMessage` matches a specific string (`access denied`).
- Two or more token predicates that AND-narrow aggressively.

Window: **30 to 90 days minimum**, often 180+. Verified: a needle filter plus aggregation over a
full day of a 599 GB/day index scanned 274 MB, so 90 days of it is roughly 25 GB. Well inside
budget at any tenant size. (Selectivity varies: a needle on a busy CloudTrail index measured
~0.5%, 173 GB over 90d. Still affordable, but not free, which is why the next rule matters.)

**One long scan per invocation.** Do not run the filter alone over the full window and then the
full query over the same window: the two scans cost the same, so the invocation pays double
(observed: 173 GB + 173 GB for one rule). Instead:

1. Pull sample events for unit tests with `filter | head 5`. `head` terminates early, so this is
   usually far cheaper than an unbounded filter scan.
2. Run the **full query** (filter + aggregation + threshold) once over the long window. That single
   scan is both the sanity check and the backtest; read the match count and the grouping keys from
   it.

Go long deliberately. A 7-day window on a once-per-month behaviour reports zero, and the user
concludes the rule is broken when it is fine.

### Broad (measured selectivity > ~50%)

Typical shapes:
- `@scnr.source_type="aws:cloudtrail"` alone.
- `eventSource="iam.amazonaws.com"` alone.
- No `eventName` predicate.
- A leading wildcard (`**:value`, `field:*value`), which is slow regardless of window.

Window: **derive it from the byte budget.** Do not use a fixed 7 days. At 20 GB/day that budget is
weeks; at 8 TB/day it is under two hours.

For a broad filter the right move is usually not a shorter window, it is a better filter. Tell the
user that, with the numbers:

> This filter scans essentially all of `<index>`, which ingests `<N>`/day, so 7 days would be
> `<N*7>`. I capped the backtest at `<window>`. Adding a specific `eventName` predicate would make
> a 90-day backtest cheaper than the capped run.

## Backtest output format

One line, including the cost basis so the user can judge the result:

```
Backtest: needle (selectivity 0.05%), 90 days, 22 GB scanned, 4 matches, ~0.04 fires/day
```
```
Backtest: broad (selectivity ~100%), capped at 20 hours by budget, 490 GB scanned, 312 matches, ~1250 fires/day (extrapolated)
```

Mark any rate derived from a capped window as **extrapolated**. If the rule aggregates `by` an
entity, also surface the top 5 grouping-key values by count: those are the candidates for tuning
or exclusion.

## Special cases

- **`n_bytes_scanned == 0`** is distinct from "the filter matched zero events". Exactly **0** means
  the target index has no data over the window: either it is empty, or the range predates or
  postdates all ingested data. A real scan that matched nothing has non-zero bytes. Stop and tell
  the user: *"`@index=<alias>` returned `n_bytes_scanned: 0` over `<window>`. The index appears
  empty for that time range. Verify the index name and the data's actual ingestion window before
  proceeding."* (Verified empirically 2026-05: empty index plus wide range = 0; populated index
  with filter-misses = 5.5 GB scanned; populated index with pre-data range = 0.)
- **Zero fires over the full window** with `n_bytes_scanned > 0`. State it explicitly: *"The rule
  wouldn't have fired in the last 90 days. It's a future trip-wire, which is sometimes the right
  call, but if you expected hits and got zero the filter is probably wrong."* Never silently
  accept zero.
- **Zero fires over a window that was capped for cost.** Weaker evidence than the above, and you
  must say so: a 6-hour capped backtest returning zero says almost nothing about a monthly
  behaviour. Recommend tightening the filter so a long window becomes affordable, then re-running.
- **Too many fires for Medium+ severity.** Surface the loud groups from the top-5 list and propose
  specific tuning: extra filter, threshold, dedup window, or severity downgrade. See
  `severity_policy.md`.
- **Group-by dropped groups.** If the aggregation response carries a `MemoryLimit` entry or a
  non-null `results_caveat`, the top-5 list is incomplete. Say so, and reduce the group-by
  cardinality before raising `max_bytes`.
- **Leading wildcards** (`*value`) are a perf risk at any window. Suggest a token match instead:
  `roleArn:"integration-access"` (fast) rather than `roleArn:"*integration-access*"` (slow).

## Why no fixed window

Because "7 days" describes time, and the thing that fails is bytes. The same 7 days is 140 GB in
one tenant and 50 TB in another. The user is here for *iterative* tuning, so fast feedback beats a
perfectly long backtest, and a measured window beats both.
