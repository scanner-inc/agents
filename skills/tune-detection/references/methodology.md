# tune-detection — methodology

Read this when the user invokes `/tune-detection`. The skill's job is to turn "this rule is noisy" into a concrete YAML diff backed by a real classification of recent firings.

## Phase 1: Locate the rule YAML

The user names a rule (by `name` or `detection_rule_id`). Search, in order:

1. **Local user repos** — every path in `SCANNER_DETECTIONS_DIR` (comma-split). Match on `name:` field. If found, use this YAML in-place.
2. **Scanner OOB packs** — Scanner-inc publishes pre-built rule packs at `scanner-inc/detection-rules-<source>` (each pack is its own GitHub repo — see the canonical list in `recommend-detections/references/oob_packs.md`). Two ways to locate a rule:
   - **Default** — use the rule's tags to identify the matching pack's `source.<slug>`, then list rule files in that pack via the GitHub API:
     ```bash
     curl -sSL "https://api.github.com/repos/scanner-inc/detection-rules-<source>/contents/rules" | jq -r '.[].name'
     ```
     …then fetch the candidate file raw:
     ```bash
     curl -sSL "https://raw.githubusercontent.com/scanner-inc/detection-rules-<source>/main/rules/<file>.yml"
     ```
     and confirm the `name:` matches. If matched, **switch to fork-and-disable** (see SKILL.md). Copy the fetched YAML to a user-controlled path before any edits; tell the user about the UI disable step.
   - **If the user has cloned the pack locally** (some users group these under a convenience parent like `~/src/scanner-out-of-the-box-detections/<pack>/`) and gives you a path, grep that path for the rule's `name:` instead. Same downstream workflow.
3. **Scanner Detection Rule API** — for rules that exist in the tenant but not in any local repo and aren't OOB (UI-created rules). Use `scripts/fetch_detection_rule.sh`:
   ```bash
   scripts/fetch_detection_rule.sh --name "<rule name>"
   # or
   scripts/fetch_detection_rule.sh --id <uuid>
   ```
   The script returns the full rule JSON via the `GET /v1/detection_rule/{id}` endpoint. Inspect `detection_rule_sync_id`:
   - **`detection_rule_sync_id: null`** → UI-created, no git source. **Switch to UI-tune workflow** (see below).
   - **`detection_rule_sync_id: "<uuid>"`** → git-synced from a repo the skill couldn't find on the local filesystem. Tell the user to clone / locate that repo and re-invoke `/tune-detection` with the YAML path. Don't fork via API because the user's git repo is the source of truth.
4. If `detection_rule_id` was given and step 1/2 didn't match by `name`, you can also resolve via `_detections`:
   ```scanner
   @index=_detections detection_rule_id="<id>" | head 1
   ```
   …read the `name` field, then go back to step 1.

### UI-tune workflow (for `detection_rule_sync_id: null`)

The rule exists only in the tenant — it was created in the Scanner web UI, not synced from a git repo. **It is still fully editable in the UI**: the user can change the query, severity, tags, alert template, event-sink mapping, etc. directly. Present **three** options to the user and let them pick:

**A. Edit in the Scanner web UI** (quickest, no commit/push round-trip):
- Settings → Detection Rules → search for the rule by name → Edit.
- Tweak the query (apply the FP/TP-informed tuning patch from Phase 5 — extra filter, threshold, dedup window, severity downgrade).
- Save. Change takes effect immediately.
- This is the right call for small ad-hoc tweaks where the user doesn't need a change-management trail.

**B. Disable / delete in the Scanner web UI** (right if the rule shouldn't run at all):
- Settings → Detection Rules → search by name → Disable or Delete.
- Use this when the FP/TP classification was 100% FP and the rule has no salvageable signal (e.g., a debug/test rule that got promoted).

**C. Convert to a git-tracked YAML** (for production-quality rules where change management matters):
- Write a YAML version (the skill converts the API JSON → YAML) into a path in `SCANNER_DETECTIONS_DIR`. Carry over name / severity / event_sink_keys / tags from the API record; apply the tuning patch in the new YAML.
- ⚠️ **Duplication risk**: Scanner's GitHub-app sync matches by `sync_key` or `detection_rule_sync_id`, not by `name`. Committing a YAML with the same `name` as a UI-created rule will create a SECOND rule, not override the first. **The user must disable / delete the UI-created original FIRST**, then commit the YAML. Be explicit about this in the hand-off.
- Why prefer this over (A) for important rules: change management, source control history, peer review via PR, audit trail, repeatability across tenants. Worth the friction for any rule a team actually depends on.

In all three branches, surface the original `detection_rule_id` in the hand-off message so the user can find the rule in the UI.

## Phase 2: Pull recent firings

Run:

```scanner
@index=_detections name="<exact rule name>"
| groupbycount results_table.rows[0].<pivot1>, results_table.rows[0].<pivot2>
```

Pivots are the columns in the rule's `query_text` `stats … by …` clause. If the rule doesn't aggregate (rare), pivot on `results_table.rows[0].userIdentity.arn` (or whatever the dominant entity is for that source) plus an event-distinguishing field.

Window: start with 14 days. If you see fewer than 20 firings, extend to 30 days for better classification signal.

Sort by count descending. The top 10 groups are the noise. The long tail might be TPs.

## Phase 3: Sample underlying events

For the top 3–5 noisy groups, re-run the rule's *filter clause* (no aggregations) scoped to:
- The pivot values from that group (`userIdentity.arn=<value>`, etc.)
- The window where `_detections` showed the firings.

Pull 3–5 representative raw events per group. Look at fields the original rule didn't filter on:
- `userAgent` — common FP source (legitimate automation tools).
- `requestParameters.*` — sometimes a benign parameter value distinguishes the FP from the TP.
- `userIdentity.sessionContext.attributes.mfaAuthenticated` — MFA-protected actions are often TP-suspicious.
- `eventTime` patterns — pure 9-to-5 might be human use; 24/7 even cadence is automation.

## Phase 4: Classify FP / TP / UNKNOWN

Render a compact table:

```
| Group (entity / pivot)                           | Verdict | Reason                                                    |
|---------------------------------------------------|---------|-----------------------------------------------------------|
| arn:aws:iam::123…:user/ci-deployer                | FP      | CI service account; every fire matches deploy schedule    |
| arn:aws:iam::123…:user/alice                      | TP      | Sustained activity at 3 AM from a residential IP          |
| arn:aws:iam::123…:role/eks-node                   | FP      | Kubernetes service role; reads cluster config 24/7        |
| 198.51.100.42                                      | UNKNOWN | Tor exit node, but only one event; not enough signal     |
```

Rules:
- **FP** = the rule fires but the activity is benign. Concrete reason required.
- **TP** = the rule fires and the activity is genuinely suspicious or worth a human look. The tuning **must not** remove these.
- **UNKNOWN** = needs more data. Don't tune around unknowns; flag them for the user.

If everything is FP → tune aggressively.
If everything is TP → don't tune the filter; consider `dedup_window_s` or `alert_per_row` to reduce alert noise without losing coverage.
Mixed → tune the FPs surgically.

## Phase 5: Propose targeted tuning

Pick the smallest change that eliminates FPs and preserves TPs. In order of preference:

### A. Extra filter clause

Best when the FPs share a distinguishing field:

```diff
   eventName=ConsoleLogin
   errorMessage="Failed authentication"
+  and not userAgent: "AWSConsole-HealthCheck"
+  and not userIdentity.arn: "/role/eks-node-"
```

Use **token-match (`:`)** when matching part of a structured value (ARN substring, user-agent token). Use **exact-match (`=`)** when the FP signature is a fixed string.

### B. Post-aggregation threshold

Best when individual events look fine but the *rate* is the signal:

```diff
   | stats count() as eventCount by userIdentity.arn
+  | where eventCount > 5
```

### C. Dedup window

Best when the SAME group keeps re-firing for legitimate reasons but you want to know about it once per hour:

```diff
   ...
   query_text: |-
     ...
+  dedup_window_s: 3600
+  alert_template:
+    info:
+      - label: User
+        value: "{{results_table.rows[0].userIdentity.arn}}"
+        use_for_dedup: true
```

### D. Severity downgrade

Last resort. Use when the rule is producing valid hits but they're not page-worthy:

```diff
- severity: Medium
- event_sink_keys:
-   - medium_severity_alerts
+ severity: Low
```

A Low/Informational rule writes to `_detections` and is consumed by correlation rules — no event-sink alerts. See `/write-correlation` for promoting it.

### What to avoid

- **Blanket exclude-lists** of ARNs / IPs / usernames — they decay quickly as the customer's environment changes. Prefer field-based filters.
- **Wholesale rewrite** of `query_text` — it's a rule, not a refactor. Smallest diff that solves the problem.

## Phase 6: Add regression tests

The rule has a `tests:` array. Append at least one new negative test seeded from an FP event:

```yaml
  - name: Regression — does not fire on CloudShell user-agent (FP from 2026-05-12)
    now_timestamp: "2026-05-15T00:03:00.000Z"
    dataset_inline: |
      {"timestamp":"2026-05-15T00:02:30.000Z","%ingest.source_type":"aws:cloudtrail","eventName":"ConsoleLogin","errorMessage":"Failed authentication","userAgent":"AWSConsole-HealthCheck","userIdentity":{"arn":"arn:aws:iam::123456789012:user/ci-deployer"}}
    expected_detection_result: false
```

Sanitise account IDs / ARNs / IPs to canonical examples. Keep field shapes faithful to what the source produces.

If existing positive tests still pass with the tuned filter, leave them. If the tuning broke one, fix it (or the user broke a TP — re-classify).

## Phase 7: Validate

```bash
scanner-cli validate -f <path>
scanner-cli run-tests -f <path>
```

If validate fails: read the error, fix, re-run.
If a test fails: the diff between expected vs actual is usually obvious. Inspect, adjust the filter, re-run.

## Phase 8: Backtest the tuned query

Re-run the *exact* tuned `query_text` (filter + aggregations + threshold) via Scanner MCP over the same window as Phase 2.

Report:
- Before fire-rate (`<N>/day` from the classification window).
- After fire-rate (`<M>/day` from the tuned query).
- Reduction percentage.
- **TP coverage check** — confirm explicitly that each TP group from Phase 4 still appears in the tuned-query output. If any disappear, the tuning is too aggressive; back off and re-iterate.

Example:
```
Backtest: 14 days, was 312/day → now 18/day (-94%). All 3 TP groups still fire.
```

## Phase 9: Hand off

Don't auto-flip `enabled:` state during tuning. If the rule was `Active`, it stays `Active` (a tuning patch shouldn't silently demote). If it was `Staging`, stays `Staging`.

Hand-off format:

1. The FP/TP table.
2. The YAML diff — show only changed lines.
3. The validate + test results.
4. The backtest (before/after).
5. The TP-coverage confirmation.
6. The GitHub-app sync flow (4 numbered steps from SKILL.md).
7. For OOB-cloned rules: the explicit UI disable step.

Never recommend `scanner-cli sync`.

## Self-critique before emitting

- Is the YAML diff truly minimal, or did I refactor more than necessary?
- Did I check that **each TP group from the classification table still fires** under the tuned query?
- Is the new negative regression test actually using an FP event from the classification, not a synthetic one?
- For OOB rules: did I include the disable-in-UI instruction in the hand-off?
- Are FPs classified with **concrete** reasons, or generic ones?
- If I downgraded severity, did I explain *why* the rule's hits aren't page-worthy in `description`?

Fix anything the critique surfaces, re-validate, re-emit.
