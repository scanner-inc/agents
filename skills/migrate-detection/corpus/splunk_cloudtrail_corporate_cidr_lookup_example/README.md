# Splunk → Scanner with VRL enrichment: privileged IAM from non-corporate network

**Source:** [`source.yml`](./source.yml) — synthetic Splunk security_content rule demonstrating the lookup-table pattern.

**Targets:**
- [`enrich.vrl`](./enrich.vrl) — Scanner VRL transformation that adds the `source.classification` field at ingest time.
- [`lookup_corporate_cidrs.csv`](./lookup_corporate_cidrs.csv) — example lookup CSV (the user replaces with their real corporate CIDR list).
- [`scanner_rule.yml`](./scanner_rule.yml) — Scanner detection rule that consumes the enriched field.

## The migration challenge

Splunk supports lookup tables at search time:

```spl
... | lookup corporate_cidrs cidr OUTPUT classification | where isnull(classification) | ...
```

Scanner **does not** have query-time lookups. The same logical capability requires moving the table lookup **upstream** to ingest time, where a VRL transformation adds enriched fields to every event.

This is Pattern B from `corpus_index.md` — VRL-enriched migration. The user must install the VRL plus the lookup table in Scanner UI **before** the migrated rule can fire correctly.

## What the migration produces (in order)

1. **The lookup CSV** (`lookup_corporate_cidrs.csv`). The user uploads this to Scanner UI under Library → Lookup Tables.
2. **The VRL transformation** (`enrich.vrl`). The user creates this as a custom transformation in the Scanner UI under Library → Transformations, then references it in Collect → Index Rules for the `aws:cloudtrail` source as one of the Transform & Enrich steps. It reads `.sourceIPAddress`, looks up the CIDR in the table via `find_enrichment_table_records!(...)`, and writes `.source.classification` (one of `corporate`, `corporate-vpn`, `non_corporate`, or `unknown`). See `methodology.md` "Field namespace for enrichment output" for how to choose the field path — prefer ECS when there's a real mapping, else the customer's own schema, else a plain custom field like this one.
3. **The detection rule** (`scanner_rule.yml`). Now filters on `source.classification="non_corporate"`. The rule is otherwise a 1:1 translation of the Splunk filter clause.

## Hand-off sequence

The user has to perform these steps in order:

1. Install the lookup table (Library → Lookup Tables, upload CSV). The Lookup Tables API is also available (beta, unstable; see https://docs.scanner.dev/scanner/using-scanner-complete-feature-reference/unstable/lookup-tables).
2. Install the VRL as a custom transformation (Library → Transformations, paste `enrich.vrl`). Then in Collect → Index Rules for the `aws:cloudtrail` source, add the transformation under the Transform & Enrich steps.
3. Wait one ingestion cycle so existing data gets the new field (or accept that only future events will have it).
4. Push the detection rule to `main`. The Scanner GitHub app syncs.
5. Watch `_detections` for a few days, then promote to `Active`.

Skipping any of these will result in the rule never firing or firing on every event (depending on how the missing-field case is handled).

## Why this matters in the corpus

This pattern shows up in many migrations:

| Source feature | Same pattern |
|---|---|
| Splunk `\| lookup` | Same — VRL enrichment |
| Splunk KV Store lookup | Same |
| Sentinel watchlist | Same |
| Chronicle reference list | Same |
| Elastic enrich processor | Same |
| Panther rules that call `aws_helpers.is_corporate_ip(ip)` | Same — model into VRL |

If you're migrating any of these and see a vendor-side lookup, you'll need a parallel VRL hand-off. This corpus entry is the template.

## Sister skill: `/write-vrl`

The `enrich.vrl` here is short, but real-world enrichments often need more sophistication (multiple lookup tables, MMDB GeoIP, error handling, derived fields). The `/write-vrl` skill is purpose-built for authoring and testing VRL transformations against sample logs. Recommend invoking it for non-trivial enrichments rather than writing VRL by hand from this template.

## Limitations

- **Existing data isn't enriched.** Only events ingested after the transformation is installed will have the field. For retroactive coverage, the user can re-ingest historical CloudTrail (if they have the source files) or accept that the rule starts catching only forward-going events.
- **Lookup updates are not instant.** When the user updates `corporate_cidrs.csv`, Scanner picks up the new version on a periodic schedule (check Scanner docs for current cadence). Events ingested before the update won't see the new entries.
