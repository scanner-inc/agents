# write-vrl example lookup tables

Three ready-to-use fixtures for testing VRL enrichment programs against the harness in `../scripts/test_vrl.sh`. They are intentionally tiny so the harness round-trips fast and the contents are easy to eyeball when debugging.

## Files

| File | Type | Use with | What's in it |
|---|---|---|---|
| `corporate_cidrs.csv` | CSV | `--lookup-table NAME=...` | CIDR → classification (`corporate`, `corporate-vpn`, `datacenter`). 7 rows, includes one IPv6 range. |
| `aws_accounts.csv` | CSV | `--lookup-table NAME=...` | AWS account_id → `account_alias`, `environment`, `owner_team`. 6 rows, real-looking but fake account ids. |
| `test_geoip.mmdb` | MMDB | `--mmdb-table NAME=...` | IP → country / continent / ASN / AS org. 5 networks (Google DNS, Cloudflare, Quad9, OpenDNS, a Russian /16). Same column shape as IPInfo Lite, so `../corpus/ipinfo_geoip_enrichment.vrl` runs against it unchanged when aliased as `ipinfo_lite`. |
| `test_geoip.jsonl` | JSONL | source of truth | One network entry per line. Edit this and rerun the build to regenerate `test_geoip.mmdb`. |
| `build_test_mmdb.go` | Go | regen | Tiny Go program that reads `test_geoip.jsonl` and writes `test_geoip.mmdb`. |
| `go.mod`, `go.sum` | Go | regen | Module spec for `build_test_mmdb.go`. |

## Quick examples

### CIDR-based classification (CSV)

```bash
echo '{"@ecs":{"source":{"ip":"10.0.10.42"}}}' > /tmp/in.json

scripts/test_vrl.sh \
  --lookup-table ip_classification=examples/corporate_cidrs.csv \
  corpus/ip_classification_enrichment.vrl /tmp/in.json
# -> {"@ecs":{"network":{"zone":"corporate-vpn"},"source":{"ip":"10.0.10.42"}}}
```

### AWS account enrichment (CSV)

The corpus doesn't ship a generic account-enrichment program yet, but the pattern is one-shot — `find_enrichment_table_records!("aws_accounts", {"account_id": id})`. Drop this in a `.vrl` file:

```python
if !is_nullish(.@ecs.cloud.account.id) {
    acct_id = to_string(.@ecs.cloud.account.id) ?? ""
    if acct_id != "" {
        rows = find_enrichment_table_records!("aws_accounts", {"account_id": acct_id})
        if length(rows) > 0 {
            row = rows[0]
            .@ecs.cloud.account.name = row.account_alias
            .@ecs.cloud.account.environment = row.environment
            .@ecs.organization.name = row.owner_team
        }
    }
}
.
```

Then:

```bash
echo '{"@ecs":{"cloud":{"account":{"id":"111111111111"}}}}' > /tmp/in.json

scripts/test_vrl.sh \
  --lookup-table aws_accounts=examples/aws_accounts.csv \
  /tmp/aws_acct_enrich.vrl /tmp/in.json
# -> {"@ecs":{"cloud":{"account":{"environment":"production","id":"111111111111","name":"scnr-prod-usw2"}},"organization":{"name":"platform"}}}
```

### GeoIP enrichment (MMDB)

Aliased to `ipinfo_lite` so the corpus program runs unchanged:

```bash
echo '{"@ecs":{"source":{"ip":"8.8.8.8"}}}' > /tmp/in.json

scripts/test_vrl.sh \
  --mmdb-table ipinfo_lite=examples/test_geoip.mmdb \
  corpus/ipinfo_geoip_enrichment.vrl /tmp/in.json
# -> {"@ecs":{"source":{"as":{"number":15169,"organization":{"name":"Google LLC"}},
#             "geo":{"continent_code":"NA","continent_name":"North America",
#                    "country_iso_code":"US","country_name":"United States"},
#             "ip":"8.8.8.8"}}}
```

## Regenerating `test_geoip.mmdb`

The committed MMDB binary is built from `test_geoip.jsonl`. To add networks or modify columns, edit the JSONL and rerun the Go build:

```bash
cd examples/
# add or edit lines in test_geoip.jsonl ...
go run build_test_mmdb.go
# -> wrote test_geoip.mmdb (NNNN bytes, K networks)
```

Requires Go 1.24+ on PATH (older Go versions will auto-fetch a 1.24 toolchain via Go's built-in GOTOOLCHAIN mechanism). No other deps to install — `go.mod` pins `github.com/maxmind/mmdbwriter`.

## Picking realistic data

The example tables intentionally avoid real production IPs/accounts. For richer testing:

- **CSVs:** add your own rows. CSV column headers become the keys on each `record` in VRL, so renaming a column means updating the corresponding `record.<key>` reads in the program.
- **MMDB:** for real geo coverage download IPInfo Lite (free) and use that directly: `--mmdb-table ipinfo_lite=~/Downloads/ipinfo_lite.mmdb`. The corpus `ipinfo_geoip_enrichment.vrl` is written for that schema.
