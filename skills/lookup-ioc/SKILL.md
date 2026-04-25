---
name: lookup-ioc
description: Look up an external indicator of compromise (IP, domain, URL, file hash, or CVE) across abuse.ch ThreatFox, AlienVault OTX, and (for IPv4) Feodo Tracker, and return a single merged threat-intel report. Use when a SOC analyst types `/lookup-ioc [indicator]`, when another skill (triage-alert, threat-hunt, investigate) needs to enrich an indicator surfaced during investigation, or when the user asks any free-form variation of "is this IP/domain/hash bad?", "do we have threat intel on X?", or "check this IOC". Requires ABUSECH_AUTH_KEY and OTX_API_KEY in the environment; degrades gracefully if either is missing.
---

# lookup-ioc

## Workflow

1. Run `scripts/lookup_ioc.sh <indicator>`. The script auto-detects the IOC type (IPv4, IPv6, domain, URL, file hash, CVE) and fans out to the relevant sources in parallel.
2. Read the returned JSON object. The shape is:
   ```
   {
     "indicator": "...",
     "type": "IPv4|IPv6|domain|url|file|cve|unknown",
     "threatfox": {...} | {"skipped": "..."} | {"error": "..."},
     "otx":       {...} | {"skipped": "..."} | {"error": "..."},
     "feodo":     {...} | {"skipped": "..."} | {"error": "..."}
   }
   ```
3. Summarize the verdict for the analyst using the report template below.

## Calling the script

```
scripts/lookup_ioc.sh 8.8.8.8
scripts/lookup_ioc.sh evil.example.com
scripts/lookup_ioc.sh d41d8cd98f00b204e9800998ecf8427e
scripts/lookup_ioc.sh CVE-2024-3400
scripts/lookup_ioc.sh "https://malicious.test/path"
```

If `ABUSECH_AUTH_KEY` or `OTX_API_KEY` is missing, the corresponding source returns `{"skipped": "..."}` rather than failing the whole call. Relay missing-key skip messages verbatim — do not pretend a source returned a clean result when it was simply not consulted.

## Interpreting results

A hit on any feed is strong evidence. A miss is weak evidence — many real threats are not in public feeds, especially fresh campaigns and targeted malware. Be explicit about which sources were checked and which were skipped.

- **ThreatFox** (`scripts/threatfox.sh`): hit when `query_status == "ok"` and `data` is non-empty; reports malware family, confidence, first_seen.
- **OTX** (`scripts/otx.sh`): hit when `pulse_info.count > 0`; pulses include malware family, MITRE mappings, references.
- **Feodo Tracker** (`scripts/feodo.sh`): IPv4 only; hit when the IP is on the active botnet C2 blocklist.

## Report template

Reply in terminal markdown:

```
🔎 IOC lookup — `<indicator>` (`<type>`)

Verdict: <CLEAN | SUSPICIOUS | MALICIOUS> (sources checked: <list>; skipped: <list or none>)

- ThreatFox: <hit summary or "no result" or "skipped: ...">
- OTX: <pulse count, top malware families/MITRE, or "no pulses">
- Feodo: <hit details or "not on blocklist" or "skipped: IPv4-only">

Notes: <any analyst-relevant context — first_seen dates, related campaigns, false-positive risk>
```

Verdict rubric: `MALICIOUS` if any source has an active match with high confidence. `SUSPICIOUS` if a source has a weak/old/aged-out match or only context pulses without active C2 evidence. `CLEAN` only when every consulted source returned no result and at least two sources were actually consulted (skipped sources do not count).

## Direct sub-script usage

The fan-out script is the primary entrypoint, but the per-source scripts are usable on their own when only one source is needed:

- `scripts/threatfox.sh <ioc>` — POST to ThreatFox `search_ioc`.
- `scripts/otx.sh <type> <value>` — direct OTX indicator lookup (`<type>` is one of IPv4, IPv6, domain, hostname, url, file, cve — case-sensitive).
- `scripts/feodo.sh <ip>` — IPv4-only Feodo blocklist check.
