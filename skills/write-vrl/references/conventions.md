# Scanner VRL conventions

Read this when drafting or refining a VRL program for a Scanner transformation. The rules here are Scanner-specific and override generic VRL/Vector documentation.

## How Scanner runs your VRL

- Each log event arrives as the object `.`. The program mutates `.` in place. The return value of the last expression is **ignored** — only the final state of `.` matters.
- The final value of `.` must be either an **object** (one log event out) or an **array of objects** (zero or many log events out).
- A bare `return` exits the program early without changing `.`. To use this pattern intentionally, the previous statements must already have left `.` in the desired final state.
- A VRL **error** (an unhandled fallible call, an `assert!`, etc.) halts ingestion of the **entire file** the event was in and requires manual intervention. Never throw on a per-event problem — handle the case explicitly.

## The `@ecs` target

Scanner's normalized representation lives under `.@ecs` — a sub-tree on the event using [Elastic Common Schema](https://www.elastic.co/guide/en/ecs/current/index.html) field names. The original raw fields are preserved alongside it. This means downstream queries can pivot on `@ecs.user.name`, `@ecs.source.ip`, `@ecs.event.action`, etc. regardless of the upstream log source.

Scanner tracks **ECS version 9.5.0**. The full schema is checked in at `references/ecs_schema_9.5.0.csv` — see the next section for how to look fields up. The CSV has canonical bare paths like `source.ip`; in VRL you write `.@ecs.source.ip` (prepend `@ecs.` to whatever the CSV says).

Note that ECS 9 introduced two field-set additions that are relevant when extending the corpus: `cloud.entity.*` (for cloud resource hierarchy — supersedes ad-hoc `cloud.resource.*`) and `user.entity.{type,sub_type}` (for user categorization — supersedes ad-hoc `user.type`). Prefer these in new code.

Convention in the existing corpus:

```python
.@ecs.event.action = .eventName            # cloudtrail
.@ecs.user.id     = .userIdentity.arn      # cloudtrail
.@ecs.source.ip   = .client.ipAddress      # okta
.@ecs.cloud.provider = "aws"               # constant when the source implies it
```

Two equivalent path syntaxes appear in the wild:

- `.@ecs.event.action` — shorthand, used in every file under `corpus/`. Preferred.
- `."@ecs".event.action` — quoted form, used in some docs examples. Equivalent.

Pick one and stay consistent within a single program.

### Looking up canonical fields

`references/ecs_schema_9.5.0.csv` is the authoritative list of every ECS field at the version Scanner uses. Columns: `ECS_Version, Indexed, Field_Set, Field, Type, Level, Normalization, Example, Description`. **Don't read the whole file** (2116 fields, 261KB, some Description cells contain embedded newlines — use a real CSV parser if you need to walk every row) — grep it.

```bash
# Find a field by path fragment (matches the Field column only, not descriptions)
awk -F',' 'NR>1 && $4 ~ /process\./' references/ecs_schema_9.5.0.csv | cut -d',' -f4,5,9 | head

# All fields in a set (everything under user.*)
awk -F',' '$3 == "user"' references/ecs_schema_9.5.0.csv | cut -d',' -f4,5

# Get the type + description for one exact field
awk -F',' '$4 == "source.ip"' references/ecs_schema_9.5.0.csv
```

Two practical rules:

1. **Use canonical ECS paths.** When mapping a new field, grep the schema first. If ECS already has a home for what you're representing, use it — even if the corpus has a non-canonical variant (e.g. some corpus files write `.@ecs.user_agent` directly, but the canonical is `user_agent.original`). New code should prefer canonical.
2. **Custom fields are fine under `@ecs.*`.** If something doesn't fit ECS, you can still put it under `@ecs.<your_namespace>` — Scanner doesn't validate. But check the schema first; ECS covers more than you'd expect.

### Common ECS fields — quick cheat sheet

The fields that come up most often when mapping a new source. Grep the schema CSV for anything not on this list:

| ECS path | What goes there |
|---|---|
| `@ecs.event.action` | The action the event represents (eventName, eventType, action, etc.) |
| `@ecs.event.outcome` | `"success"` or `"failure"` |
| `@ecs.event.id` | A unique event id if the source provides one |
| `@ecs.user.id` | Stable user identifier (ARN, sub, UUID) |
| `@ecs.user.name` | Human-readable username |
| `@ecs.user.email` | If available |
| `@ecs.source.ip` | The client IP |
| `@ecs.source.geo.{country_iso_code,country_name,continent_code,continent_name}` | From an upstream source's own geo field (e.g. Okta's `client.geographicalContext`), or from an MMDB enrichment step against IPInfo Lite — see `corpus/ipinfo_geoip_enrichment.vrl`. |
| `@ecs.source.as.{number,organization.name}` | Autonomous system info — same MMDB enrichment step populates this alongside geo. |
| `@ecs.user_agent.original` | Raw user-agent string (canonical ECS — some older corpus files use `@ecs.user_agent` directly; prefer `.original` in new code) |
| `@ecs.http.request.{id,method,bytes,body.bytes}` / `@ecs.http.response.{status_code,bytes,body.bytes}` / `@ecs.http.version` | HTTP fields — canonical paths |
| `@ecs.url.{full,path,query,scheme,domain,port}` | URL components |
| `@ecs.cloud.{provider,region,account.id,service.name}` | Cloud context |
| `@ecs.host.{id,name,os.{type,name,version}}` | Endpoint / EDR data |
| `@ecs.process.{name,executable,user.name}` | Process info |
| `@ecs.file.{path,hash.{md5,sha1,sha256}}` | File info |
| `@ecs.organization.{id,name}` | Tenant / org / account on the upstream side |
| `@ecs.error.{code,message}` | When outcome is failure and the source has details |
| `@ecs.network.{zone,type,direction,transport,protocol}` | Network classification (zone is where `ip_classification_enrichment.vrl` writes `corporate`/`other`) |
| `@ecs.destination.{ip,port,domain,address}` | Mirror of `source.*` for the other end of a connection |

For anything not in this cheat sheet, `references/ecs_schema_9.5.0.csv` is authoritative. The corpus under `corpus/` shows the actual style used in deployed transforms — match its conventions when extending a mapping; reach for the schema CSV when adding a new field family.

## Idioms used throughout the corpus

### Guard every optional source field with `is_nullish`

```python
if !is_nullish(.userIdentity.userName) {
    .@ecs.user.name = .userIdentity.userName
}
```

`is_nullish` is true for `null`, the empty string, and missing fields. Use it instead of `!= null` so you don't write empty strings into `@ecs`. (Note: it doesn't catch empty objects/arrays — handle those separately when relevant.)

### Pick the first non-null value

The `??` operator falls back when the left side errors *or* is null:

```python
.@ecs.user.name = .userIdentity.userName ??
                  .userIdentity.sessionContext.sessionIssuer.userName ??
                  null
```

This produces shorter code than nested `if !is_nullish` when there are several candidate paths.

### End the program with `.`

Every file in `corpus/` ends with a bare `.` on its own line. It's idiomatic and harmless — the return value is ignored, but it makes intent obvious.

## Dropping events during ingestion

Set `.` to `[]` and exit early. Scanner treats an empty array as "produce zero log events", so the event never gets indexed.

```python
# Drop noisy health checks
if .url.path == "/health" || .url.path == "/ping" {
    . = []
    return 0   # early exit; the return value is ignored
}

# ... rest of the transform runs only for non-dropped events
```

Multiple conditions are easier to read with a flag:

```python
drop = false
if .url.path == "/health" { drop = true }
if .level == "DEBUG"      { drop = true }
if drop {
    . = []
    return 0
}
```

**Never** use `assert!` to reject an event — that halts ingestion of the whole file. The empty-array pattern is always the right answer for per-event filtering.

## Producing many events from one (fan-out)

Set `.` to an array of objects. Each element becomes its own log event.

```python
events_array = array(.events) ?? []
if length(events_array) > 0 {
    orig_ts = .timestamp
    output = []
    for_each(events_array) -> |index, event| {
        result = {}
        result.timestamp   = orig_ts
        result.event_index = index
        result.action      = event.action
        output = push(output, result)
    }
    . = output
}
```

When debugging this pattern with `vector vrl -o`, the CLI prints the array verbatim — Scanner is the thing that expands it into N events.

## Error handling

Every fallible function — `to_int`, `to_string`, `parse_json`, `parse_regex`, `ip_cidr_contains`, etc. — must either be paired with `??`, captured as `result, err = ...`, or invoked with `!` (which errors on failure). Avoid the `!` form unless an error genuinely means a misconfiguration that should halt the file.

Two patterns to keep in mind:

```python
# Fallback value
.status_code = to_int(.status) ?? 0

# Explicit error check
parsed, err = parse_json(.message)
if err == null {
    .message_parsed = parsed
} else {
    .parse_error = to_string(err)   # for visibility, not for halting
}
```

If a required field is missing and the rest of the program depends on it, **drop the event** (`. = []; return 0`) rather than letting later statements error.

## Enrichment tables

Scanner exposes two table types, and VRL has two functions for talking to them. Use the one that matches the table type and access pattern:

### CSV tables — `find_enrichment_table_records!()`

Multi-record, filter-based lookup. Returns a list of matching rows; you iterate to find what you need. Best for tables where the match is *predicate-based* (CIDR containment, prefix match, range), not exact-key.

```python
records = find_enrichment_table_records!("ip_classification", {})  # all rows
for_each(records) -> |_idx, record| {
    # ... ip_cidr_contains, first-match-wins, etc.
}
```

Worked example: `corpus/ip_classification_enrichment.vrl`.

### MMDB tables — `get_enrichment_table_record()`

Single-record, key-based lookup. Returns one record (or errors on miss). Best for tables that are *indexed* by a single value — IP-to-geo, hash-to-reputation, etc. MaxMind DB files (`.mmdb`) are the standard format.

```python
record, err = get_enrichment_table_record("ipinfo_lite", {"ip": ip_str})
if err != null {
    return .   # miss — leave the event untouched
}
# record fields are the table's columns: country_code, country, continent, asn, as_name, ...
```

Note: in user-uploadable Scanner VRL, the table-name argument to both `find_enrichment_table_records` and `get_enrichment_table_record` must be a **string literal** — hardcode it in the program. (Scanner's internal VRL exposes `%params.*` metadata for parameterization, but user-uploaded programs don't have that.)

Worked example: `corpus/ipinfo_geoip_enrichment.vrl`.

### Testing locally

The harness covers both table types:

```bash
# CSV table  -> find_enrichment_table_records!
test_vrl.sh --lookup-table ip_classification=path/to/cidrs.csv program.vrl in.json

# MMDB table -> get_enrichment_table_record
test_vrl.sh --mmdb-table ipinfo_lite=path/to/ipinfo_lite.mmdb program.vrl in.json

# Or both in one run
test_vrl.sh --lookup-table ip_classification=cidrs.csv \
            --mmdb-table   ipinfo_lite=lite.mmdb       \
            program.vrl in.json
```

Ready-to-use fixtures for all three patterns live in `examples/`:

- `corporate_cidrs.csv` — for testing `ip_classification_enrichment.vrl` or any CIDR-based filter
- `aws_accounts.csv` — for testing account-id → metadata enrichment (no corpus file yet — see `examples/README.md` for a template)
- `test_geoip.mmdb` — IPInfo-Lite-shaped, for testing `ipinfo_geoip_enrichment.vrl` unchanged (alias the flag as `--mmdb-table ipinfo_lite=examples/test_geoip.mmdb`)

## VRL's static-type linter

VRL is strict about dead error-handling. Two errors come up often when iterating on a draft:

### E651 — unnecessary error coalescing (`??`)

```
classification = to_string(record.classification) ?? "other"
                                                  ^^^^^^^^^^^
                                                  this expression never resolves
```

VRL has type-inferred that `record.classification` is a `String`, so `to_string(...)` is infallible and the `??` branch is dead. Drop the `??`:

```python
classification = to_string(record.classification)
```

This often bites when you swap a `find_enrichment_table_records!()` call (returns dynamically-typed `Value` objects, fallible coercions) for a hardcoded inline `records = [{...}]` for local testing (statically-typed `String` literals, infallible coercions). The two forms need slightly different code to satisfy the linter. The harness's `--lookup-table` mode lets you keep one production-shaped program and avoid the swap.

### E104 — unnecessary error assignment

```
class_str, _err = to_string(record.classification)
           ^^^^   ----------------------------------- because this expression can't fail
           this error assignment is unnecessary
```

Same cause: VRL has decided the call is infallible. Drop the error variable:

```python
class_str = to_string(record.classification)
```

### Patterns that work for both static and dynamic types

When `record.classification` could be statically `String` or dynamically `Value`:

```python
# Works in both modes — no error handling, just is_nullish guard
if !is_nullish(record.classification) {
    classification = string!(record.classification)
}
```

`string!(...)` is the bang form: errors on non-string, but after the `is_nullish` guard plus a known-string column in the lookup table, it's safe. (Use it sparingly — bang calls halt the file on failure.)

When you genuinely need a fallback for dynamic-typed Values:

```python
class_str, _conv_err = to_string(record.classification)
if !is_nullish(class_str) {
    classification = class_str
}
```

Lint only fires when VRL can statically prove infallibility. With `find_enrichment_table_records!()`, values are `Value`, so both forms compile.

## Things Scanner does *not* support

- Network calls, filesystem reads, `find_enrichment_table_records` is supported but **lookup tables are loaded out-of-band** in Scanner — you can't define a table inline.
- `assert!` / `assert_eq!` — treat these as halt-the-file footguns, not runtime checks. Never commit them to a production transform.
- The VRL Playground runs scripts in isolation and prints arrays as-is. Scanner expands arrays into multiple events and treats `[]` as a drop signal. When testing locally with `vector vrl`, you get Playground-style output — interpret an `[]` result as "this event would be dropped in Scanner".

The full list of supported functions lives in Scanner's docs at `using-scanner-complete-feature-reference/data-transformation-and-enrichment/custom-vrl.md` in the gitbook-docs repo. If a function isn't in that list, Scanner will reject the program at upload time.

## Testing locally

`scripts/test_vrl.sh <program.vrl> <input.json>` runs the program through `vector vrl` and prints the resulting object. Output of `[]` is annotated as `DROPPED`. Multiple input files run in sequence with a header per case so you can verify several scenarios in one run.

For programs that call `find_enrichment_table_records!(NAME, ...)` (CSV) or `get_enrichment_table_record(NAME, ...)` (MMDB), pass `--lookup-table NAME=PATH.csv` or `--mmdb-table NAME=PATH.mmdb` (both repeatable, can be mixed) to synthesize a full Vector pipeline with the table mounted:

```bash
scripts/test_vrl.sh \
  --lookup-table ip_classification=/tmp/ip_classification.csv \
  --mmdb-table   ipinfo_lite=$HOME/Downloads/ipinfo_lite.mmdb \
  program.vrl input1.json input2.json
```

The `NAME` must match the literal string passed to the VRL function. For CSV the column headers become object keys on each `record`; for MMDB the columns are whatever the database's data section provides (e.g. IPInfo Lite: `country_code`, `country`, `continent_code`, `continent`, `asn`, `as_name`).

The `vector` binary used by the script must match Scanner's VRL feature set reasonably closely. The corpus was written against Vector 0.41+; 0.47 is also fine. Install with `curl --proto '=https' --tlsv1.2 -sSf https://sh.vector.dev | bash`.

## When extending an existing corpus file

1. Read the existing file end-to-end. Match its style (spaces vs. tabs, comment density, `is_nullish` vs. `??`).
2. Add new mappings in the same field-group section where related fields already live (user, source, http, cloud, etc.).
3. Don't reorder existing lines — diffs against the deployed transform should be additive.
4. Re-run `test_vrl.sh` against the same input you ran before, plus a new sample that exercises your addition.
