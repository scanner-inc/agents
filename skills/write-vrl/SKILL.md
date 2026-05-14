---
name: write-vrl
description: Author and test a VRL (Vector Remap Language) program for a Scanner transformation step. Takes sample raw logs (a file in JSON / JSONL / CSV / Parquet / plaintext, or an inline event) plus an objective — normalize to ECS, drop noisy events during ingestion, fan one event into many, parse an embedded string, enrich with derived fields — and produces a VRL program that the user can paste directly into the Scanner UI. Drafts the program, runs it against the sample with `vector vrl`, compares output to the objective, and iterates. Use when the user types `/write-vrl`, asks Claude to "write a VRL program", "make a Scanner transformation", "normalize this log to ECS", "drop these events during ingestion", or pastes/points to a raw log and says they want it transformed.
---

# write-vrl

## When to invoke

Trigger on any of:
- The user types `/write-vrl` (with or without context).
- The user pastes a raw log sample, or points at a sample file (JSON, JSONL, CSV, Parquet, plaintext), and asks for a transformation, ECS mapping, drop/filter rule, or fan-out.
- The user references an existing Scanner transformation step and wants to extend it.
- The user asks "how do I drop X during ingestion" or similar — the answer is a VRL program, and this skill writes and tests it.

## Inputs you need before drafting

Before writing any VRL, make sure you have:
1. **One or more sample raw log events.** These become the test inputs in Phase 4. Accepted forms, in rough order of preference:
   - **A file** (preferred) in any of:
     - JSON — a single object, a JSON array of events, or JSONL/NDJSON (one event per line).
     - CSV with a header row.
     - Parquet.
     - Plaintext logs (one event per line — syslog, k=v, common log format, free-form).
   - **An individual event pasted inline** (typically JSON, but a single plaintext line is fine too).

   More events is better, especially for ECS mapping — you want to see the full gamut of fields and event shapes the source produces, not just the first one. Survey what the user gave you (jq over the corpus, schema-summary one-liners, sampling across event types) before drafting, so you don't write VRL that handles the happy path and breaks on the tail. Then pick a handful of representative events to write to JSON files in a working directory under `/tmp` — those become the test fixtures the harness runs against. Conversion rules for getting events into one-object-per-file JSON:
   - **JSON array / JSONL** → split into one JSON object per file.
   - **CSV** → use the header row as keys; emit each row as a JSON object (`{"col1": "...", "col2": "..."}`). Quick one-liner: `python3 -c "import csv,json,sys;[print(json.dumps(r)) for r in csv.DictReader(sys.stdin)]" < file.csv`.
   - **Parquet** → use `duckdb -json -c "select * from 'file.parquet' limit 5"` or a `python3 -c "import pyarrow.parquet as pq, json; ..."` snippet. Verify the tool exists before you pick it.
   - **Plaintext** → wrap each line as `{"message": "<raw line>"}`. This matches what Scanner's pipeline does upstream of the transform, so VRL written against this shape will work in production. If the objective is to parse the line into structured fields, that parsing is part of the VRL (`parse_syslog`, `parse_regex`, `parse_key_value`, etc.).

   Fixture selection matters: pick events that exercise different shapes — the common case, plus anything that looks like an edge (missing fields, unusual types, the kind of event the user wants to drop or fan out). Without real samples you can't test, and untested VRL is the worst possible artifact for this skill — Scanner halts file ingestion on a VRL error.

2. **The objective.** Usually one of:
   - "Normalize to ECS" — see `references/corpus_index.md` for the source families already mapped.
   - "Filter out events where X" — the empty-array drop pattern; see `references/conventions.md#dropping-events-during-ingestion`.
   - "Parse an embedded JSON / regex / k=v string into structured fields."
   - "Fan one event with an array into many events" — see the flatten_array pattern in `references/conventions.md`.
   - "Add a derived field" — CIDR tag from a CSV lookup table, IPInfo geo from an MMDB lookup table, decoded base64/JSON, computed hash, etc. See `corpus/ip_classification_enrichment.vrl` (CSV / `find_enrichment_table_records`) and `corpus/ipinfo_geoip_enrichment.vrl` (MMDB / `get_enrichment_table_record`).
3. **Whether this extends an existing transform** in `corpus/`. If so, open that file first and match its style.

If samples or objective are missing, ask once before drafting. Don't draft from an imagined payload.

## Workflow

### Phase 1 — Read the references

For every invocation, load both:
- `references/conventions.md` — Scanner VRL rules (the `@ecs` target, the `. = []` drop pattern, error handling, enrichment-table functions, what Scanner does *not* support).
- `references/corpus_index.md` — the index over the existing transforms. If the user's source is in the list or structurally similar, open the matching file in `corpus/` and use it as the starting point.

These are short. Don't skip them — they're the difference between writing valid Scanner VRL and writing generic VRL that breaks at upload time.

Don't read `references/ecs_schema_9.5.0.csv` into context — it's 2116 fields. Grep it from Bash when you need to confirm a canonical field path or check what type a column should be:

```bash
# Field by path fragment (matches the Field column only, not descriptions)
awk -F',' 'NR>1 && $4 ~ /process\./' references/ecs_schema_9.5.0.csv | cut -d',' -f4,5,9 | head

# All fields in one set (e.g. user.*)
awk -F',' '$3 == "user"' references/ecs_schema_9.5.0.csv | cut -d',' -f4,5

# Exact field lookup
awk -F',' '$4 == "source.ip"' references/ecs_schema_9.5.0.csv
```

The CSV has bare ECS paths (`source.ip`); in VRL prepend `@ecs.` (`.@ecs.source.ip`).

### Phase 2 — Hypothesize

Before writing code, state in 2-4 short bullets:
- What the input looks like (which fields you'll read from).
- What the output should look like (which fields you'll write to, what gets dropped or fanned out).
- The handful of fallible operations the program will need (parse, type coercion, optional-field guards).

If the objective is ambiguous (e.g., "normalize this Slack event" with no indication of which fields matter), pick the high-confidence ECS mappings (`event.action`, `user.id`/`name`, `source.ip`, `user_agent`) and call out what you're *not* mapping so the user can extend.

### Phase 3 — Draft

Write the VRL program in one go, in a fenced ```python``` block (Scanner's UI uses Python-ish syntax highlighting; VRL has no dedicated lexer in most markdown renderers). Apply the conventions:
- Guard optional reads with `is_nullish`.
- Pair every fallible call with `??`, `result, err =`, or — only when failure means "halt the whole file is correct" — `!`.
- Group assignments by ECS section with one-line comments (`# User fields`, `# Source fields`, etc.) when mapping to ECS.
- End the program with a bare `.` on its own line.
- For drop rules: `. = []` then `return 0`, before any later transformation code runs.

Don't invent fields the sample doesn't show. If a desired ECS target has no clear source, omit it and note the gap to the user.

### Phase 4 — Test

Save the program and one or more input samples to disk, then run the harness:

```bash
scripts/test_vrl.sh path/to/program.vrl path/to/sample1.json path/to/sample2.json
```

If the program calls an enrichment-table function, mount the table(s):

- `find_enrichment_table_records!(NAME, ...)` (CSV) → `--lookup-table NAME=PATH.csv`
- `get_enrichment_table_record(NAME, ...)` (MMDB) → `--mmdb-table NAME=PATH.mmdb`

Both flags are repeatable and can be mixed. The harness spins up a full Vector pipeline with the table(s) mounted. Ready-to-use fixtures live in `examples/` — `corporate_cidrs.csv`, `aws_accounts.csv`, and `test_geoip.mmdb` (5 networks, IPInfo-Lite-shaped) — covering the common patterns without needing real data:

```bash
scripts/test_vrl.sh \
  --lookup-table ip_classification=examples/corporate_cidrs.csv \
  --mmdb-table   ipinfo_lite=examples/test_geoip.mmdb \
  path/to/program.vrl path/to/sample.json
```

The script uses a local `vector` binary (PATH first, then `~/.vector/bin/vector`). Output is one JSON value per input. A line of just `[]   # DROPPED -- ...` means the empty-array drop fired — that's how Scanner is told to skip the event.

Test at minimum:
- The **happy path** the user gave you.
- One **edge case** that exercises optional fields, fallbacks, or the drop branch (synthesize this from the happy-path sample if the user didn't supply one).
- If the program drops events, **both a sample that gets dropped and one that doesn't**.

If `vector vrl` errors, fix the program and re-run. Do not hand the user code that hasn't run cleanly against their sample.

### Phase 5 — Critique once

Before emitting the final answer, ask yourself:
- Are there fallible calls without `??` or `err` capture?
- Would a missing field anywhere in the read paths halt the file? (Inside `if !is_nullish(...)` guards is safe; bare `.a.b.c` is generally safe in VRL because it returns null for missing paths, but `to_int(.x)` without `??` is not.)
- Did I drop the event when the objective said "filter" or "skip"? Or did I just *not write* the ECS fields, which still indexes the raw event?
- For ECS work: are the chosen `@ecs.*` paths the same ones used in the corpus, or did I invent new ones?

Fix anything the critique surfaces, re-test, then emit.

### Phase 6 — Output

Respond to the user with:

1. **The VRL program** in a code block, ready to paste into the Scanner UI Transformations page.
2. **A short "what it does" summary** — one sentence per behavior (mapping, dropping, fanning out).
3. **The test results** — show the input → output for at least the happy path and one edge case. For drop tests, explicitly say "this event would be dropped" rather than just showing `[]`.
4. **Any gaps** — fields you couldn't map confidently, follow-ups the user might want, or assumptions worth confirming.

Keep the response tight. The code block is the deliverable; everything else is context the user needs to verify it.

## Required environment

- A `vector` binary on PATH or at `~/.vector/bin/vector`. Install with `curl --proto '=https' --tlsv1.2 -sSf https://sh.vector.dev | bash` or see <https://vector.dev/docs/setup/installation/>.
- No Scanner API access is required — this skill operates entirely on the user's sample data locally.

## Layout

```
write-vrl/
├── SKILL.md                  # this file
├── references/
│   ├── conventions.md            # Scanner VRL rules — @ecs target, drop pattern, error handling, enrichment functions
│   ├── corpus_index.md           # index over the transforms in corpus/
│   └── ecs_schema_9.5.0.csv     # full ECS 9.5.0 field list — grep, don't read whole
├── corpus/                   # production VRL programs Scanner uses for popular log sources
│   ├── aws_cloudtrail_to_ecs.vrl
│   ├── okta_to_ecs.vrl
│   └── ... (13 more)
├── scripts/
│   └── test_vrl.sh           # vector wrapper; --lookup-table NAME=PATH.csv / --mmdb-table NAME=PATH.mmdb
└── examples/                 # ready-to-use lookup-table fixtures for the harness
    ├── corporate_cidrs.csv   # CIDR -> classification (corporate / corporate-vpn / datacenter)
    ├── aws_accounts.csv      # account_id -> account_alias / environment / owner_team
    ├── test_geoip.jsonl      # source of truth for the MMDB
    ├── test_geoip.mmdb       # 5-network MMDB, IPInfo-Lite-shaped columns
    └── build_test_mmdb.go    # `go run` to regenerate test_geoip.mmdb from the JSONL
```
