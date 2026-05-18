# write-detection — methodology

Read this file when the user invokes `/write-detection`. It carries the full 8-phase procedure. The schema mechanics live in `yaml_schema.md`; the severity policy in `severity_policy.md`; the backtest regime guidance in `backtesting.md`.

## Phase 1: Restate the hypothesis

In one paragraph, name:
- The **behaviour** being detected (one sentence — the attacker action, the misconfiguration, the policy violation).
- The **log source** that records it (CloudTrail, Okta, GitHub, etc.).
- The **fields** that distinguish it from benign activity.

If you can't fill in any of those from the user's prompt, ask **one** clarifying question and stop. Don't draft from imagined data — the rule will be wrong and the user will lose trust.

If the user is describing an existing rule with FPs, route to `/tune-detection`. If they're translating from another SIEM, route to `/migrate-detection`. If they want a cross-rule correlation, route to `/write-correlation`.

## Phase 2: Discover schema and the source-type identifier

1. Call Scanner MCP `get_scanner_context()` first — returns the context token, available indexes, and the `source_types` block listing which `@scnr.source_type` / `%ingest.source_type` values are populated and at what volume.
2. **Pick the source filter** — this is what goes at the top of the rule's query. Decide in this order:
   - **Natively-supported source** — `get_scanner_context.source_types` shows the source-type for this log family (e.g., `aws:cloudtrail`, `okta`, `auth0:audit`). Use `@scnr.source_type="<value>"`. The rule will work across every index that carries this source-type.
   - **User-added source via custom transformation** — the source shows up under `%ingest.source_type` instead. Use `%ingest.source_type="<value>"`.
   - **`custom:generic` source-type** (Scanner doesn't natively support this log family). Source-type filtering is useless — `get_scanner_context` will show `custom:generic` for several different sources at once. Instead, **sample real events** (`@index=<candidate-index> | head 3` via MCP) and find the field that uniquely identifies *this* source within the index. Common candidates: `vendor`, `provider`, `product`, `log_type`, `_source`, or whatever bespoke field the customer added. Use that as the rule's first filter.
3. `get_top_columns(indices=["<index>"])` to discover the **real** field names used in this tenant for the rest of the rule's predicates. Different sources nest fields differently (`userIdentity.arn` vs `principal.user.email` vs `actor.id`).
4. Sample 2–3 actual events to confirm field shapes. Read the schema, not the docs — schema drift is real.

**Index scoping (optional).** By default, a detection rule queries every index the user has read permission for. You typically don't need an `@index=` clause — source-type filtering takes care of it. Add `@index={UUID|"alias"}` (full form required) only when:
- The customer has separate `prod-*` and `staging-*` indexes of the same source and the rule should fire only on prod.
- The customer uses the one-source-per-index layout and `@index=` is clearer than `@scnr.source_type=` to their reviewers.

To resolve an alias to its UUID for the full form: `@index=<alias> | head 1 | table(@index, @index_id)`.

Never invent field paths. If you're unsure whether the field is `eventName` or `event.name` or `@ecs.event.action`, sample and look.

## Phase 3: Filter-clause sanity check

Write the **first filter clause** of the rule (the part before any `| stats` or `| where`). Run it via Scanner MCP `execute_query` and count.

Pick the backtest window using the regime in `backtesting.md`:
- **Needle-in-haystack** — the filter targets a rare event (specific `eventName`, specific user agent token, specific role-name token). Go long: 30–90 days. Scanner is fast on rare-event queries even at petabyte scale; long backtests are a feature.
- **Broad** — the filter still hits hundreds of events per day (e.g., "all PutObject in CloudTrail"). Cap at 7 days. Warn the user that going further is expensive.

Read the count **and** `n_bytes_scanned` from the MCP response metadata:
- **`n_bytes_scanned == 0`** → the target index has no data over the backtest window. Different from "filter matched zero events on data that was there." Stop and tell the user the index appears empty for that range — verify the index name and the data ingestion window. (Verified empirically: empty index = 0, populated index with filter-misses = non-zero, populated index pre-data = 0.)
- **Zero hits, `n_bytes_scanned > 0`** → stop. Either the filter is wrong or the behaviour doesn't occur in this tenant. Show the user the count and ask before proceeding.
- **Reasonable hits** → continue.
- **Floods** (millions over the window) → the filter is far too broad. Tighten it before drafting the rest of the rule.

Pull a handful of representative events (`| head 5`) — these become the seeds for inline tests in Phase 5.

## Phase 4: Draft the YAML

Apply `yaml_schema.md` mechanically:

- First line: `# schema: https://scanner.dev/schema/scanner-detection-rule.v1.json`
- `name:` — short, action-oriented, human-readable.
- `description:` — what it detects, references (CVE / blog / report), known false-positive scenarios.
- `enabled: Staging` — always Staging on first write.
- `severity:` — per `severity_policy.md`.
- `query_text:` — multi-line `|-` block. Use a source-type filter (`@scnr.source_type=...`, `%ingest.source_type=...`, or the bespoke identifier you discovered in Phase 2). Include `@index={UUID|"alias"}` only if Phase 2 identified a scoping reason — aliases alone parse-error in detection rules; resolve UUIDs via `@index=<alias> | head 1 | table(@index, @index_id)`.
- `time_range_s:` — lookback. Multiple of 60. Default 300.
- `run_frequency_s:` — how often the engine evaluates. Multiple of 60, `<= time_range_s`. Default 60.
- `event_sink_keys:` — per `severity_policy.md` (Medium+ → set this; Low/Info → omit).
- `tags:` — at least one MITRE tactic (`tactics.taXXXX.*`) and one technique (`techniques.tXXXX.*`) where applicable, plus `source.<slug>`. Use only canonical tags from `mitre_tags.md`.

Aggregation patterns that work well:

```scanner
%ingest.source_type="aws:cloudtrail"
eventSource="iam.amazonaws.com"
eventName=PutUserPolicy
userAgent: "S3 Browser"
| stats
  min(@scnr.datetime) as firstTime,
  max(@scnr.datetime) as lastTime,
  count() as eventCount
  by userIdentity.arn, eventSource, eventName, awsRegion
```

The `stats … by …` form is the safest default: it groups by entity (so the rule fires once per arn/IP/host, not per raw event) and emits a result row the rule consumer can pivot on. For a noisy filter, add `| where @q.count > N` after the stats to threshold.

## Phase 5: Inline tests

Add a `tests:` array with **2–4 tests**. Required: at least one positive (the rule fires) and at least one negative (it doesn't).

```yaml
tests:
  - name: Test the rule fires when <behaviour>
    now_timestamp: "2026-05-15T00:03:00.000Z"
    dataset_inline: |
      {"timestamp":"2026-05-15T00:02:30.000Z","%ingest.source_type":"aws:cloudtrail",...}
      {"timestamp":"2026-05-15T00:02:15.000Z","%ingest.source_type":"aws:cloudtrail",...}
    expected_detection_result: true
  - name: Test no fire when <similar benign behaviour>
    now_timestamp: "2026-05-15T00:03:00.000Z"
    dataset_inline: |
      {"timestamp":"2026-05-15T00:02:30.000Z","%ingest.source_type":"aws:cloudtrail",...}
    expected_detection_result: false
```

Seed `dataset_inline` from the **real events** you sampled in Phase 3. Sanitise: scrub real account IDs, ARNs, IPs to canonical example values (`123456789012`, `arn:aws:iam::123456789012:user/JohnDoe`, `203.0.113.5`). Keep the field shapes faithful — that's the point of testing against real data.

Each row must include an RFC-3339 `timestamp`. The `now_timestamp` should be slightly after the latest event timestamp (test windows are inclusive-exclusive on the upper bound).

## Phase 6: Validate offline

Write the YAML into one of the paths in `SCANNER_DETECTIONS_DIR` (or the path the user gave). Suggest a sub-path that matches the source: `rules/aws/<rule_name>.yml`, `rules/okta/<rule_name>.yml`, etc.

Run:

```bash
scanner-cli validate -f <path>
scanner-cli run-tests -f <path>
```

If validate fails: read the error, fix the YAML, re-run. Common failures:
- Missing schema header.
- Bare `@index=alias` instead of `@index={UUID|"alias"}`.
- Invalid severity value (must be one of the eight OCSF strings).
- `enabled: true` accepted, but prefer the explicit `Staging` / `Active` / `Paused` strings.

If run-tests fails: read the diff between expected and actual. Often the negative test fires because the filter is broader than intended — tighten the filter and rerun.

## Phase 7: Historical backtest

Run the **full query** (filter + aggregations + threshold) via Scanner MCP over the regime-appropriate window from Phase 3.

Report:
- Total matches in the window.
- Expected daily firing rate (matches ÷ days).
- For aggregated rules: list the top 5 grouping-key values by count.

Tuning decisions:
- **Medium / High / Critical / Fatal**, expected fire rate > ~10/day → propose extra filters or a threshold (`| where @q.count > N`). Show the user the loud values from the top-5 list so they can decide what to exclude.
- **Low / Information** — looser tolerance. These are signals, not alerts; high volume is fine if downstream correlation rules handle it.
- **Zero fires over the full window** → tell the user. The rule will quietly never fire. Suggest either a different filter or accepting that this is a "future trip-wire" rule (which is sometimes the right call).

## Phase 8: Hand off

Show:

1. The file path (absolute).
2. The validate + run-tests result.
3. The backtest summary (1 line).
4. The exact `scanner-cli` commands the user can re-run.
5. The GitHub-app sync flow (4 numbered steps from SKILL.md).
6. Any tuning suggestions surfaced by Phase 7.

Never recommend `scanner-cli sync`.

## Self-critique before emitting

Before finalising the response, check:

- Does every fallible aggregation field actually exist in the source schema (re-grep `get_top_columns` output if unsure)?
- Are MITRE tags strings from `mitre_tags.md`, not hallucinated?
- Did the rule pick the right severity vs signal? (Medium+ should be something a human or AI agent would want to look at; Low/Info is for correlation-only.)
- Is `enabled: Staging`? (Always Staging on first write.)
- If the YAML uses `@index=`, is it the full `{UUID|"alias"}` form and was the scoping reason actually warranted (per Phase 2)? Or could it just be `@scnr.source_type=` instead?
- Is there a positive AND negative test? Do they actually exercise different paths?

Fix anything the critique surfaces, re-validate, re-emit.
