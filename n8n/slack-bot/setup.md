# Slack bot workflow: setup

## Prerequisites

* n8n instance reachable from Slack. For local development use `--tunnel` or an ngrok URL so Slack can POST events to the trigger.
* Anthropic API key.
* Scanner account with MCP access. Scanner MCP URL in the form `https://mcp.<your-env>.scanner.dev/v1/mcp` and a Scanner MCP API key (read-only scope).
* An [AlienVault OTX](https://otx.alienvault.com/) API key (free).
* An [abuse.ch](https://auth.abuse.ch/) auth key (free). Used for the ThreatFox API.
* Slack workspace admin (or someone who can install a new Slack app).

## 1. Create the Slack app

The bot needs a Slack app with event subscriptions. Use the manifest below as a starting point at <https://api.slack.com/apps> → **Create New App** → **From an app manifest**.

```yaml
display_information:
  name: Scanner Bot
  description: Scanner-powered SOC assistant. @-mention to investigate alerts in thread or channel.
  background_color: "#0b0e1a"
features:
  bot_user:
    display_name: scanner-bot
    always_online: true
oauth_config:
  scopes:
    bot:
      - app_mentions:read    # receive @-mentions
      - channels:history     # read public channel history for context
      - groups:history       # read private channel history (only for channels the bot is in)
      - im:history           # read DM history (if you @-mention the bot in a DM)
      - mpim:history         # read group DM history
      - chat:write           # post replies
      - reactions:write      # add :eyes: ack reactions
      - users:read           # resolve user IDs to display names in thread context
settings:
  event_subscriptions:
    request_url: https://<your-n8n-host>/webhook/slack-bot-app-mention
    bot_events:
      - app_mention
  interactivity:
    is_enabled: false
  org_deploy_enabled: false
  socket_mode_enabled: false
  token_rotation_enabled: false
```

After creating the app:

1. Install it into your workspace. Copy the **Bot User OAuth Token** (`xoxb-…`), you'll paste it into the n8n Slack credential.
2. Invite the bot to any channel where you want to be able to @-mention it: `/invite @scanner-bot`.
3. Leave the Event Subscriptions "Request URL" field blank for now, you'll fill it in after importing the n8n workflow and copying the Slack Trigger's Production URL.

## 2. Credentials to create in n8n

Before importing `workflow.json`, create these credentials in n8n's **Credentials** UI. Names must match exactly so the workflow references resolve on import.

1. **Slack account** (type: Slack API)
   * Access Token: paste the bot token (`xoxb-…`) from step 1.
   * Used by: Slack Trigger, both HTTP Request nodes (for reading Slack history), and all three Slack Send Message nodes.

2. **Anthropic account** (type: Anthropic API)
   * API Key: your Anthropic key.

3. **Scanner API/MCP Bearer Auth account** (type: HTTP Bearer Auth)
   * Bearer Token: your Scanner MCP API key. Paste just the token; n8n adds the `Bearer ` prefix.

4. **OTX Header Auth** (type: HTTP Header Auth)
   * Name: `X-OTX-API-KEY`
   * Value: your AlienVault OTX API key.

5. **Threatfox Abuse.ch Header Credential** (type: HTTP Header Auth)
   * Name: `Auth-Key`
   * Value: your abuse.ch auth key. Used for the ThreatFox endpoint.

## 3. Import the workflow

1. In n8n, go to **Workflows** → **Import from File**.
2. Select `workflow.json`.
3. Open each node and verify:
   * **Slack Trigger**: events list shows `app_mention`. Credential is "Slack account". Copy the **Production URL** from this node, you'll paste it into the Slack app's Event Subscriptions "Request URL" field.
   * **Get Thread Replies** and **Get Channel History**: credential type is "Predefined Credential Type" → "Slack API" → "Slack account".
   * **Resolve User Names**: Code node that extracts user IDs from the context, calls `users.info` per ID in parallel via the Slack credential, and rewrites the context with display names. Uses the "Slack account" credential internally via `this.helpers.httpRequestWithAuthentication`. No configuration needed on the node itself.
   * **Anthropic Chat Model**: credential is "Anthropic account", model is Claude Opus 4.7. Verify the model name resolves in the dropdown; older n8n builds may not list 4.x models, upgrade your n8n image if it's missing.
   * **Scanner MCP (Schema Tools Only)** and **Scanner MCP**: both endpoint URLs are your tenant's MCP URL (replace `mcp.your-env.scanner.dev` with the real hostname in *both* nodes). Credential is "Scanner API/MCP Bearer Auth account" on both. On the **Scanner MCP (Schema Tools Only)** node, verify the tool filter shows only `get_scanner_context`, `get_top_columns`, `get_docs`, the field may be labeled "Tools to Include" or "Included Tools" in the n8n UI. If the filter dropdown looks empty after import, reselect those three tools manually.
   * **ThreatFox IOC Lookup**: credential is "Threatfox Abuse.ch Header Credential". Connected to Execute Plan only.
   * **OTX IOC Lookup**: credential is "OTX Header Auth". Connected to Execute Plan only.
   * **Detection Rules API**: URL is your tenant's Scanner API endpoint (replace `api.your-env.scanner.dev` with the real hostname). In the query parameters, replace `REPLACE_WITH_TENANT_UUID` with your Scanner tenant ID (UUID). Credential is "Scanner API/MCP Bearer Auth account". Connected to Execute Plan only.
   * **Summarize / Plan / Execute agents**: system message field is populated (paste from `prompts/summarize.md`, `prompts/plan.md`, `prompts/execute.md` if anything looks truncated). Execute agent has Retry On Fail enabled (3 tries, 5s wait).
   * **Post Summary / Post Plan / Post Result**: channelId is `={{ $('Build Context').item.json.channel }}`. Other Options shows `thread_ts` set to `={{ $('Build Context').item.json.thread_parent_ts }}`. Slack credential is "Slack account".

## 4. Complete the Slack app configuration

Once the workflow is imported and activated:

1. Go back to your Slack app at <https://api.slack.com/apps>.
2. **Event Subscriptions** → **Request URL** → paste the Production URL from the n8n Slack Trigger node. Slack will send a URL-verification challenge; n8n responds automatically. You should see "Verified ✓" within a second.
3. Confirm `app_mention` is listed under Subscribe to bot events.
4. If you change scopes after the initial install, re-install the app to your workspace.

## 5. Test locally

1. Start n8n with the tunnel option so Slack can reach it:
   ```bash
   docker run -it --rm \
     -p 5678:5678 \
     -v ~/.n8n:/home/node/.n8n \
     -e N8N_SECURE_COOKIE=false \
     n8nio/n8n start --tunnel
   ```
2. **Update the pinned test data with a real channel ID**. The pinned payload on the Slack Trigger node has `"channel": "REPLACE_WITH_TEST_CHANNEL_ID"`, you must replace this before the smoke test will run, because the HTTP Request nodes use it to fetch history and the Slack Post nodes use it to reply:
   * Invite the bot to a test channel: `/invite @scanner-bot` in Slack.
   * Copy the channel ID (right-click the channel → **View channel details** → scroll to the bottom, or use the "Copy link" option and grab the trailing ID segment). Channel IDs start with `C` for public, `G` for private group DMs, or `D` for direct messages.
   * In the n8n UI, open the **Slack Trigger** node, click the "Pinned data" tab (or the small pin icon), edit the JSON, and replace `REPLACE_WITH_TEST_CHANNEL_ID` with the real ID. Save.
3. Activate the workflow.
4. **Canvas-only smoke test**: click **Execute workflow** in the n8n UI. The (now-edited) pinned payload runs through the whole chain without needing a real Slack mention. Expected flow:
   * `Get Channel History` returns the last ~30 messages of your test channel.
   * Three Slack posts land in the channel: `*[1/3]* 💭`, `*[2/3]* 📋`, `*[3/3]* ✅`.
   * The default pin has no `thread_ts`, so the three posts start a new thread rooted at the mention's `ts`. To test the thread-replies branch instead, either set `thread_ts` in the pinned data to the ts of a real thread in that channel, or use the fuller `sample-payloads/example-app-mention.json` (which has `thread_ts` set, same channel edit required).
5. **Real Slack test**:
   * In the test channel, start a thread, then in the thread reply: `@scanner-bot what happened to this user in the last 4 hours?`
   * Expected: a 👀 reaction appears on your mention within ~1 second (instant "I heard you" ack), then within a few more seconds you see `*[1/3]* 💭` (summary), then within ~10-20 seconds `*[2/3]* 📋` (plan, which may call Scanner schema tools first), then within 30s–2min `*[3/3]* ✅` (finding).
   * If the mention is posted outside a thread, the three replies start a new thread rooted at the mention.

## 6. Operating notes

* **Which channels does it work in?** Only channels the bot has been `/invite`'d to. Without `channels:history` (public) or `groups:history` (private) access, context fetching returns empty and the bot will still answer but without thread awareness.
* **Rate limits**: Slack's `chat.write` tier is high but not unlimited; three posts per mention means ~3x the volume of a single-reply bot. Keep an eye on bursts in a busy incident channel.
* **Cost profile per mention**: three Opus 4.7 calls per mention (~$0.05–$0.30 total depending on context size, query count, and tool output size). Execute dominates, Summarize and Plan each close in a single LLM turn since they have no tools.
* **Cheaper mix**: if cost matters more than peak quality on the preamble steps, split the shared Anthropic Chat Model into three per-agent models, Haiku 4.5 on Summarize, Sonnet 4.6 on Plan, Opus 4.7 on Execute. This cuts ~70% of tokens on the first two steps.
* **Model overload fallback**: if Opus is overloaded frequently, change the Anthropic Chat Model sub-node's model to `claude-sonnet-4-6`. The agent prompts work well with either.

## Security considerations

* Slack signing secrets + the bot token are the security boundary. n8n's Slack Trigger handles signature verification automatically; don't weaken that by replacing it with a generic Webhook node.
* The bot has MCP read access to Scanner and write access only to Slack. It takes no response actions. If you extend this workflow to call write APIs (disable user, isolate host), add a **Wait** node with a Slack button approval before any write step.
* Scanner MCP API keys should be scoped to read-only permissions. Do not use an admin key here.
* The bot reads whatever channels it's been invited to. Don't invite it to channels containing secrets you don't want Anthropic to see (the context goes into the Claude prompt).

## Troubleshooting

* **URL verification fails**: the Slack Trigger must be in an activated workflow before Slack can verify. Activate first, then paste the URL.
* **"not_in_channel" errors on Get History / Get Replies**: the bot hasn't been invited to that channel. `/invite @scanner-bot` in Slack.
* **Summary posted but plan never arrives**: check the Plan Investigation node's execution log. Most common cause is a dropped Anthropic credential. Re-select "Anthropic account" in the Sonnet Chat Model node.
* **Execute timed out / Anthropic overloaded**: Retry On Fail covers most transients. For persistent overload, swap the Opus sub-node to Sonnet 4.6.
* **MCP Client authentication failed**: credential value wrong, or Scanner MCP endpoint unreachable. Test the MCP URL with `curl` using the bearer token outside of n8n first.
* **Posts land in the wrong thread**: verify the Post nodes' `thread_ts` expression reads `$('Build Context').item.json.thread_parent_ts`. That field falls back to the mention's own `ts` when the mention wasn't in an existing thread.
* **Bot replies to itself in a loop**: Slack delivers its own messages to the bot via `message` events, not `app_mention`. The trigger subscribes only to `app_mention` so this shouldn't happen. If it does, double-check the Slack app's event subscriptions, you should not see `message.channels` listed.
