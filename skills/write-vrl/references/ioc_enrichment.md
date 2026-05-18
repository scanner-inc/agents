# IOC enrichment — the lookup-table → VRL → detection chain

This reference describes the canonical pattern for matching incoming logs against threat-intel IOCs (known-bad IPs, malicious domains, file hashes, URLs, CVE-tagged indicators) and surfacing matches to detection rules.

**The pattern is the default** for IOC-based detections — inline IOC matching in a rule body is brittle (IOC lists rotate; the rule has to be re-deployed on every refresh) and doesn't compose with reporting/visualization. The chain enriches at ingest time, keeps detection rules small, and uses the ECS-standard `@ecs.threat.enrichments` field path.

## The three stages

### Stage 1 — Lookup table of IOCs

Three ways to populate a Scanner lookup table with IOCs:

- **Sync from a threat-intel feed in the Scanner UI.** Library → Lookup Tables → + → "Add Sync Source". Pick a provider (currently AlienVault OTX, with more on the way). Scanner re-pulls on a schedule and writes one table per indicator type (`ipv4-addr`, `domain-name`, `url`, `file-hash-md5`, `file-hash-sha1`, `file-hash-sha256`). Each synced table has a non-null `sync_source` field — see the schema below.
- **CSV upload in the UI.** Library → Lookup Tables → + → upload a CSV directly. Good for static internal lists, or for IOC feeds that Scanner doesn't have a built-in sync source for. `sync_source` is null for these.
- **Unstable API.** `POST /v1/unstable/lookup_table_file/tenant/<tenant-id>` with multipart `file=@table.csv` and `name=<table-name>`. See `https://docs.scanner.dev/scanner/using-scanner-complete-feature-reference/unstable/lookup-tables`. Same UI URL is shown in the API response: `https://app.scanner.dev/teams/<tenant-id>/library/lookup-tables#id=<id>`.

### Identifying IOC tables — the `sync_source` field

For tables synced from a built-in threat-intel feed, the API returns:

```jsonc
"sync_source": {
  "ThreatIntel": {
    "source":         "AlienVault",         // feed name; future: "ThreatFox", "Feodo", "CISA-KEV", …
    "indicator_type": "ipv4-addr"           // STIX value: ipv4-addr | ipv6-addr | domain-name | url | email-addr | file-hash-md5 | file-hash-sha1 | file-hash-sha256
  },
  "is_connected": true                       // whether the sync is healthy
}
```

This is a tagged enum (Rust serde-style); `ThreatIntel` is one variant. Tables with `sync_source: null` are either uploaded CSVs or non-threat-intel syncs.

**For IOC discovery — definitive vs. heuristic:**

- **Definitive:** `sync_source.ThreatIntel` is populated. These tables are guaranteed to be IOC indicators; the `indicator_type` matches the AlienVault VRL's `%params.indicator_type`.
- **Heuristic fallback:** for tables with `sync_source: null`, check whether `name` or `description` matches `ioc|threat|alienvault|otx|abuse|threatfox|feodo|cisa|malware|c2|blocklist|reputation|indicator`. Captures manually-uploaded IOC CSVs.

`scripts/list_lookup_tables.sh --ioc` returns both categories with the source/indicator_type labelled, e.g.:

```
alienvault_scanner_internal_ipv4         [AlienVault · ipv4-addr · connected]    9745 rows
alienvault_scanner_internal_domain       [AlienVault · domain-name · connected]  88102 rows
internal_blocklist                       [uploaded · heuristic match]            1234 rows
```

When recommending a chain to the user, prefer **synced** tables — they refresh automatically and the `indicator_type` is canonical (saves you guessing what column to join on).

The recommended schema for an IOC lookup table (synced tables produced by Scanner's built-in threat-intel sync sources already follow this schema):

| Column         | Type   | Notes                                                    |
|----------------|--------|----------------------------------------------------------|
| `indicator`    | string | The atomic value (IP, domain, hash, URL, email). Index column the VRL joins on. |
| `type`         | string | STIX-style: `ipv4-addr`, `ipv6-addr`, `domain-name`, `url`, `email-addr`, `file-hash-md5`, `file-hash-sha1`, `file-hash-sha256`. Matches `sync_source.ThreatIntel.indicator_type`. |
| `first_seen`   | ISO timestamp | When the feed first observed this IOC                       |
| `last_seen`    | ISO timestamp | Most recent observation                                     |
| `description`  | string | Free-form context — malware family, campaign name, etc.    |
| `provider`     | string | Source feed (`alienvault-otx`, `threatfox-abusech`, `feodo`, `cisa-kev`, `internal-blocklist`). |
| `reference`    | string | URL back to the source (pulse / report)                    |

### Stage 2 — VRL enrichment

The canonical reference is `corpus/alienvault_threat_intelligence_enrichment.vrl`. It parameterizes:

- `%params.lookup_table_name` (string, required) — the Scanner lookup table to join against. Must be specified inline in the call to `get_enrichment_table_record()` (the function only accepts string literals or metadata).
- `%params.indicator_type` (string, default `"ipv4-addr"`) — controls which typed slot under `indicator.*` gets populated (e.g. `indicator.ip`, `indicator.file.hash.sha256`, `indicator.url.original`).
- `%params.match_path` (array, default `["@ecs", "source", "ip"]`) — the field in the log to read as the candidate IOC value.
- `%params.result_array_path` (array, default `["@ecs", "threat", "enrichments"]`) — where to write matches. Use the ECS default unless you have a reason not to.

The program:

1. Reads `match_path` from the event; if missing or null, returns the event unchanged (no enrichment).
2. Calls `get_enrichment_table_record(lookup_table_name, { "indicator": match_value })`.
3. On a hit, builds a `threat_obj` with `indicator.{name,type,first_seen,last_seen,description,provider,reference}` and a typed `indicator.{ip|url|email|file.hash.…}` slot, plus `matched.{atomic,field}` describing what matched.
4. Pushes onto the existing `@ecs.threat.enrichments` array (preserves prior enrichments).
5. Returns the modified event.

### Stage 3 — Detection rule on `@ecs.threat.enrichments`

The detection rule queries the enrichment array, not the raw IOC list. Examples:

```scanner
# Any CloudTrail event with an enriched threat indicator
%ingest.source_type:aws:cloudtrail
@ecs.threat.enrichments[*].indicator.type:"ipv4-addr"
```

```scanner
# Filter to a specific provider feed (the user only trusts OTX, say)
@ecs.threat.enrichments[*].indicator.provider:"alienvault-otx"
```

```scanner
# VPC flow records hitting a known-bad destination IP
%ingest.source_type:aws:vpc_flow
@ecs.threat.enrichments[*].indicator.type:"ipv4-addr"
@ecs.threat.enrichments[*].matched.field:"@ecs.destination.ip"
```

Use `[*]` for the array wildcard (single bracket-level), **not** `[**]` (deep-path).

## `@ecs.threat.enrichments` schema (what to populate)

```jsonc
"@ecs.threat.enrichments": [
  {
    "indicator": {
      "name":        "<matched atomic value, e.g. '192.0.2.1' or 'evil.example.com'>",
      "type":        ["ipv4-addr"],          // or "ipv6-addr", "domain-name", "url", "email-addr", "file" (collapsed from hash variants)
      "first_seen":  "<ISO timestamp from the lookup table>",
      "last_seen":   "<ISO timestamp from the lookup table>",
      "description": "<context from the lookup table>",
      "provider":    "<feed source>",
      "reference":   "<URL to the source>",

      // Typed slot — pick one based on the simplified type:
      "ip":    "<value>",                    // for ipv4-addr / ipv6-addr
      "url":   { "original": "<value>",      // for url
                 "domain":   "<value>" },    // for domain-name (only .domain populated)
      "email": { "address": "<value>" },     // for email-addr
      "file":  { "hash": { "sha256": "<value>",
                           "sha1":   "<value>",
                           "md5":    "<value>" } }  // for file-hash-*
    },
    "matched": {
      "atomic": "<the value that matched, same as indicator.name>",
      "field":  "<dotted field path that produced the match, e.g. '@ecs.source.ip'>"
    }
  }
]
```

Multiple enrichments are allowed (an event might match multiple feeds, or you might call the VRL multiple times with different `match_path` values). Always push, never overwrite.

## Why this pattern, not inline IOC matching

| Concern               | Inline IOC matching in rule body                         | Lookup table + VRL chain                              |
|-----------------------|----------------------------------------------------------|-------------------------------------------------------|
| Refreshing IOC list   | Every rotation requires a rule re-deploy                 | Refresh the lookup table; no rule change              |
| Shared across rules   | Each rule has its own copy                               | One table, N rules consume                            |
| Reporting/dashboards  | No standard field path — every rule reports differently  | `@ecs.threat.enrichments` standard ECS shape          |
| Rule size             | Large filter bodies (thousands of values) → slow         | Small rule body, fast match                           |
| Multi-source enrichment | Hard to do — each rule re-implements                   | One VRL per feed; events accumulate enrichments       |
| Composability with `/triage-alert`, `/lookup-ioc` | None                            | Enrichment data already on the event during triage    |

The trade-off is the chain has 3 moving pieces instead of 1. Worth it for IOC matching; not worth it for one-off behavioural rules.
