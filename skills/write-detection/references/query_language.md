# Scanner query syntax — detection-rule cheat-sheet

The full reference lives in Scanner's `get_docs("syntax")` MCP call. This file collects the patterns most useful for writing detection rules.

## Core rules

- **Source filtering**: prefer `@scnr.source_type="<value>"` (built-in) or `%ingest.source_type="<value>"` (user-added) over `@index=`. Detection rules query all readable indexes by default — source-type filtering is usually the right scope. See `yaml_schema.md` for when `@index=` is actually warranted.
- `@index=<exact_name>` is for narrowing searches when source-type filtering isn't enough. **In detection rules**, if you use `@index=` you must use the full `@index={UUID|"alias"}` form — aliases alone parse-error at sync time. (Ad-hoc MCP queries can use the alias form.) Resolve UUIDs via `@index=<alias> | head 1 | table(@index, @index_id)`.
- `field:value` — partial / token match. Examples: `email:'mydomain'` matches `user@mydomain.com` because `@` and `.` are token boundaries.
- `field=value` — exact match.
- `field>N`, `field<N`, `field>=N`, `field<=N` — numeric only.
- Group OR'd values in parentheses: `eventName: ("CreateAccount" "DeleteAccount")`. **Never** bare `OR` between `field:value` pairs.
- Boolean operators: `and` (default), `or`, `not`. Case-insensitive. Use parentheses to control order: `(error or warning) and not test`.

## Token boundaries

Everything except `[a-zA-Z0-9_]` is a token boundary. This means `:` (partial match) handles structured values naturally:

- `email:'mydomain'` matches `user@mydomain.com` (because `@` and `.` are boundaries).
- `roleArn:'myrole'` matches `arn:aws:iam::123456789012:role/myrole`.
- No wildcards needed for these — use `:` with quotes.

## Wildcards

- **Trailing** `value*` — fast. `userArn:'role/prod-*'`.
- **Leading** `*value` — SLOW (full column scan). Avoid except for genuinely-needed substring matches.
- **Both** `*value*` — slow. Use only when you must.
- **All-fields wildcard** `**:value` — searches every field at every depth. Slow, but right for IOC sweeps.

## Array / nested wildcards (important for `_detections` queries)

- `field[*]` — wildcard within array brackets, single depth. **Use this for `tags[*]:`** since Scanner stores tags as positional fields (`tags[0]`, `tags[1]`, ...).
- `field[**]` — crosses multi-level depth, including arrays and nested objects. Overkill for tag matching; use for nested objects like `pet_kinds[**]:fish`.
- `*name` — single-asterisk in column name; matches one depth (`fname` and `lname`, not `name.first`).
- `**` in column name — crosses depth. Useful for "give me any field containing this IP anywhere": `**:'192.168.1.1'`.

## Aggregations (pipe operators)

| Pipe | Result column | Notes |
|---|---|---|
| `\| count` | `@q.count` | Total event count. |
| `\| groupbycount(col, …)` | `@q.count` | Group by column(s), count per group. Auto-sorted by count desc. |
| `\| countdistinct(col)` | `@q.uniq` | Count distinct values. |
| `\| stats fn() [as alias] by col, …` | named aliases | Available fns: `avg`, `min`, `max`, `sum`, `count`, `countdistinct`, `var`, `percentile(n, col)`. |
| `\| eval(col = expr)` | `col` | Computed column. Scalars: `if`/`coalesce`/`math.abs`/`math.round`/`+ - * /`. |
| `\| where <filter>` | (filter) | Post-aggregation filter. Use `\| where @q.count > N` to threshold. |
| `\| rename(col as alias)` | renamed col | |
| `\| table(col, …)` | projection | Limit output columns. |
| `\| head N` | first N rows | Cheap. |

## Time math

- `@scnr.time_ns` — integer nanoseconds. Use this for math: `@scnr.time_ns / 1000000000` gives seconds.
- `@scnr.datetime` — string ISO timestamp. Useful for `stats min(...) / max(...)` aggregations to emit `firstTime` / `lastTime`.

## Patterns that show up in nearly every detection rule

**Event-counting with group-by entity:**
```scanner
%ingest.source_type="aws:cloudtrail"
eventSource="iam.amazonaws.com"
eventName=PutUserPolicy
| stats
    min(@scnr.datetime) as firstTime,
    max(@scnr.datetime) as lastTime,
    count() as eventCount
    by userIdentity.arn, awsRegion, eventSource, eventName
```
This is the safest default: groups by entity (one event per arn), emits first/last/count.

**Threshold-based detection** (rule fires only when N events from the same entity in the window):
```scanner
… filter …
| stats count() as eventCount by userIdentity.arn
| where eventCount > 5
```

**Distinct-value detection** (fire when too many distinct things happen for one entity):
```scanner
… filter …
| stats countdistinct(awsRegion) as regionCount by userIdentity.arn
| where regionCount >= 3
```

**Correlation across `_detections`** (used in `write-correlation` skill):
```scanner
@index={UUID|"_detections"}
tags[*]:correlation.<custom_label>
| stats countdistinct(name) as rule_count by results_table.rows[0].userIdentity.arn
| where rule_count >= 2
```

## Reserved columns

| Column | Meaning |
|---|---|
| `@q.count` | Count from `| count` or `| groupbycount`. |
| `@q.uniq` | Distinct count from `| countdistinct`. |
| `@q.value` | Value column in aggregation output. |
| `@scnr.datetime` | ISO string timestamp of the log event. |
| `@scnr.time_ns` | Integer nanoseconds timestamp. |
| `@index` | Index the event came from. |

## Things that do NOT work

- ❌ `| sort` — there's no sort operator. `groupbycount` auto-sorts by count desc.
- ❌ `if()` inside `sum()` / `count()` — `if` only works inside `eval`. Pattern: `eval x = if(...) | stats sum(x)`.
- ❌ `OR` between `field:value` pairs without parens — use `field: ("a" "b")` instead.
- ❌ Numeric `>` / `<` against strings — comparison operators are numeric-only.
- ❌ Time math against `@scnr.datetime` — it's a string; use `@scnr.time_ns`.
- ❌ Detection-rule `@index=alias` — if you use `@index=` at all, must be `@index={UUID|"alias"}`. (Better still: drop `@index=` and rely on source-type filtering.)
