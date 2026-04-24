# Slack bot workflow (n8n)

Interactive Scanner SOC assistant you can `@` mention in Slack. The bot reads thread or channel context, summarizes what you asked, posts a plan, then executes the plan against Scanner MCP and posts a finding, all in the same thread.

## Architecture

```
┌──────────┐     ┌─────────────┐
│  Slack   │─@──▶│Slack Trigger│
│ (mention)│     │ (app_mention)│
└──────────┘     └──────┬──────┘
                        │
                        ▼
                 ┌──────────────┐
                 │ Parse Event  │  extract question, channel, ts, thread_ts
                 └──────┬───────┘
                        │
          ┌─────────────┴────────────┐
          ▼ (parallel)               ▼
   ┌──────────────┐          ┌──────────────┐
   │ Add 👀        │         │  In Thread?  │
   │  Reaction    │          └──┬────────┬──┘
   │ (fire &      │       true  │        │  false
   │  forget)     │             ▼        ▼
   └──────────────┘      ┌───────────┐ ┌────────────┐
                         │Get Thread │ │Get Channel │
                         │ Replies   │ │  History   │
                         └─────┬─────┘ └─────┬──────┘
                               └──────┬──────┘
                                      ▼
                              ┌──────────────┐
                              │Build Context │  merge + sort by ts
                              └──────┬───────┘
                          ▼
                  ┌────────────────┐
                  │ 1. Summarize   │◀── Anthropic Opus 4.7
                  │    Request     │
                  └───────┬────────┘
                          ▼
                  ┌────────────────┐
                  │ Post Summary   │    💭 _one-line restatement_
                  └───────┬────────┘
                          ▼
                  ┌────────────────┐
                  │ 2. Plan        │◀── Anthropic Opus 4.7
                  │   Investigation│◀── Scanner MCP (schema tools only)
                  └───────┬────────┘
                          ▼
                  ┌────────────────┐
                  │   Post Plan    │    📋 *Plan*: ...
                  └───────┬────────┘
                          ▼
                  ┌────────────────┐
                  │ 3. Execute     │◀── Anthropic Opus 4.7 + Scanner MCP
                  │    Plan        │
                  └───────┬────────┘
                          ▼
                  ┌────────────────┐
                  │  Post Result   │    ✅ *Finding* ...
                  └────────────────┘
```

All three posts land in the same thread (using `thread_ts`, or the mention's own `ts` when the mention wasn't already in a thread).

## Why this shape

* **Three chained AI Agent nodes, not one**: n8n's AI Agent node is a black box, it runs the full reasoning loop internally and only emits one output. There's no way to interleave Slack posts mid-execution. To show progress ("here's what I heard", "here's the plan", "here's the answer"), we split the work across three separate agents with Slack posts between them. All three share a single Opus 4.7 sub-node; if you want to save cost on the summary/plan steps you can split it into per-agent models (Haiku 4.5 for Summarize, Sonnet 4.6 for Plan, Opus 4.7 for Execute).
* **Scanner MCP split across two nodes**: Plan gets a filtered MCP node that exposes only the three read-only schema/docs tools (`get_scanner_context`, `get_top_columns`, `get_docs`). Execute gets the unfiltered MCP node with the full tool set. This lets Plan ground its bullets in the actual tenant's indexes and fields without being able to query log events, the schema tools physically return metadata, not data, so Plan can't accidentally slip into investigation. Summarize has no tools; it's a single-turn restatement.
* **HTTP Request nodes for reading Slack, Slack node for posting**: the Slack node (v2.4) has `channel.history` but not a thread-replies operation, so reading thread context needs an HTTP call to `conversations.replies` directly. Posting is simpler via the dedicated node.
* **Slack Trigger (events API), not generic Webhook**: handles Slack's URL-verification challenge and request signing automatically. You wire the event subscriptions URL in your Slack app manifest to the trigger's production URL and it just works.
* **`Retry On Fail` only on Execute**: the first two steps are fast and non-critical. The Execute step is the long one that can hit Anthropic overload or MCP transients, retrying there protects the user experience. If Execute still fails after retries, the user has already seen the summary + plan, so they know what was attempted.

## Node by node walkthrough

1. **Slack Trigger** (`n8n-nodes-base.slackTrigger`): subscribes to `app_mention` events. Uses the `Slack account` credential (bot token). Emits the full Slack event envelope as `$json`.
2. **Parse Event** (`n8n-nodes-base.set`): extracts `question` (the mention text with the `<@BOT>` prefix stripped), `channel`, `ts`, `thread_ts`, `user`. Fans out in parallel to steps 3 and 4.
3. **Add Eyes Reaction** (`n8n-nodes-base.slack`, parallel branch): posts a 👀 reaction on the mention message so the user sees immediate acknowledgment. `Continue On Fail` enabled, a failed reaction (e.g., during a canvas smoke test with a fake message ts) must not break the main flow. Does not feed anything downstream; it's fire-and-forget.
4. **In Thread?** (`n8n-nodes-base.if`): branches on whether `thread_ts` is set.
5. **Get Thread Replies** (`n8n-nodes-base.httpRequest`, true branch): GETs `https://slack.com/api/conversations.replies?channel=…&ts=…&limit=50` using the Slack credential.
6. **Get Channel History** (`n8n-nodes-base.httpRequest`, false branch): GETs `https://slack.com/api/conversations.history?channel=…&limit=30`.
7. **Build Context** (`n8n-nodes-base.code`): takes the Slack API response, sorts messages by `ts` ascending, joins them as `<user>: text` lines, and carries forward the fields from Parse Event. Emits `{ question, channel, ts, thread_ts, user, context, thread_parent_ts }`.
8. **Summarize Request** (`@n8n/n8n-nodes-langchain.agent` + Opus 4.7): one-line restatement starting with 💭. System prompt in `prompts/summarize.md`.
9. **Post Summary** (`n8n-nodes-base.slack`): prepends `*[1/3]* ` and posts threaded under `thread_parent_ts`.
10. **Plan Investigation** (`@n8n/n8n-nodes-langchain.agent` + Opus 4.7 + Scanner MCP schema tools): 3-6 bullet plan starting with 📋. May call `get_scanner_context` / `get_top_columns` / `get_docs` to ground the plan. System prompt in `prompts/plan.md`.
11. **Post Plan**: prepends `*[2/3]* ` and posts threaded.
12. **Execute Plan** (`@n8n/n8n-nodes-langchain.agent` + Opus 4.7 + full Scanner MCP): runs the plan against Scanner, produces the finding starting with ✅. Retry On Fail enabled (3 tries, 5s wait). System prompt in `prompts/execute.md`.
13. **Post Result**: prepends `*[3/3]* ` and posts threaded.

## Sub-nodes

* **Anthropic Chat Model** (Opus 4.7) → fanned out to all three agents via `ai_languageModel`.
* **Scanner MCP (Schema)** → Plan Investigation only, via `ai_tool`. Filtered to `get_scanner_context`, `get_top_columns`, `get_docs`. Plan can inspect schema; it cannot query log events.
* **Scanner MCP** (unfiltered) → Execute Plan only, via `ai_tool`. Full Scanner MCP tool set including `execute_query` and `fetch_query_results`.

If you want to trim cost, replace the single chat model with three per-agent models: Haiku 4.5 → Summarize, Sonnet 4.6 → Plan, Opus 4.7 → Execute.

## Setup

See `setup.md` for the Slack app manifest, credential setup, and import steps.

## Sample payload

`sample-payloads/example-app-mention.json`, a representative Slack `app_mention` event (threaded). Also pinned to the Slack Trigger node in `workflow.json` so you can execute the workflow from the canvas without sending a real Slack event.

```bash
# You can also POST the payload directly at the Slack Trigger's test URL for end-to-end testing:
curl -X POST http://localhost:5678/webhook-test/<trigger-id> \
  -H "Content-Type: application/json" \
  -d @sample-payloads/example-app-mention.json
```

## What you need to customize on import

1. **Credentials**: create the three credentials named in `setup.md` before import. n8n resolves them by name.
2. **Scanner MCP endpoint URL**: replace `mcp.your-env.scanner.dev` in the Scanner MCP node with your tenant's MCP hostname.
3. **Slack app**: the Slack app must have `app_mention` event subscribed and the Events URL pointing at the Slack Trigger's Production URL. See `setup.md`.

## Compatibility

Tested against n8n with these minimum node versions: Slack Trigger 1, Slack 2.4, HTTP Request 4.2, If 2.2, Set 3.4, Code 2, AI Agent 1.7, Anthropic Chat Model 1.3, MCP Client Tool 1.2.
