# Daily reporting workflow: setup

## Prerequisites

* n8n instance.
* Anthropic API key.
* Scanner account with MCP access and a Scanner API key with read permission on the Detection Rules API.
* Scanner tenant id (UUID). Find it in the Scanner UI under **Settings**; you will paste it into the Detection Rules API tool on import.
* Slack workspace connected to n8n.

## Credentials to create in n8n

Create these credentials in n8n's **Credentials** UI. Names must match the references in `workflow.json`.

1. **Anthropic account** (type: Anthropic API)
   * API Key: your Anthropic key.

2. **Bearer Auth account** (type: HTTP Bearer Auth)
   * Bearer Token: your Scanner API key. n8n prepends `Bearer ` automatically. The same credential works for both the Scanner MCP and the Scanner REST API.

3. **Slack account** (type: Slack API or Slack OAuth2)
   * Follow n8n's prompts to connect your workspace.

## Import the workflow

1. In n8n, **Workflows** → **Import from File**, select `workflow.json`.
2. Open each node and verify:
   * **Schedule Trigger**: cron is `0 8 * * *` (08:00 UTC daily). Adjust to your timezone.
   * **Anthropic Chat Model**: credential set to "Anthropic account". Model is `claude-opus-4-7`.
   * **Scanner MCP**: endpoint URL is your tenant's MCP URL (replace `mcp.your-env.scanner.dev` with the real hostname). Credential is "Bearer Auth account".
   * **Detection Rules API**: URL is `https://api.your-env.scanner.dev/v1/detection_rule` (replace `your-env` with your tenant hostname). Credential is "Bearer Auth account". In Query Parameters, replace `REPLACE_WITH_TENANT_UUID` on the `tenant_id` parameter with your actual tenant UUID.
   * **Daily Report Agent**: system message field contains the full body of `prompts/reporting-agent.md`. Paste it if the import did not populate it.
   * **Send a message**: channel ID is your reporting Slack channel.

## Test

1. Activate the workflow.
2. Click **Execute workflow** to run it once manually (does not wait for the cron). The execution log will show the agent making tool calls, ending with a Slack post.
3. Confirm the Slack message arrived and the formatting renders cleanly (bold asterisks, code ticks, bullets).

## Scheduling notes

* `0 8 * * *` = 08:00 UTC daily. For Pacific time, use `0 16 * * *` (16:00 UTC = 08:00 PST / 09:00 PDT). Daylight saving drift is a known n8n annoyance; consider setting the schedule to a time that matters less to your team, or use the n8n "Timezone" setting on the Schedule Trigger.
* For weekly reports instead of daily, use `0 8 * * 1` (Monday at 08:00 UTC).

## Tuning knobs

* Drop the pagination cap below 10 pages (described in the prompt) if you have fewer rules.
* Switch from daily to weekly cadence.
* Swap the model to `claude-sonnet-4-7` if you want a faster, lighter run; you give up some judgment quality on the recommendations.

## Troubleshooting

* **HTTP 401 on Detection Rules API**: the Bearer Auth credential value is wrong or the API key does not have read access to detection rules. Verify with `curl`:
  ```bash
  curl -H "Authorization: Bearer YOUR_KEY" \
    "https://api.your-env.scanner.dev/v1/detection_rule?tenant_id=YOUR_TENANT_ID&pagination[page_size]=1"
  ```
* **Agent hangs / truncates response**: the rule library is larger than the pagination cap. Raise the cap in the prompt or increase the agent's Max Tries / timeout.
* **Empty Slack message**: the agent returned a non-text output. Check the AI Agent node execution log; the final output should be a single string starting with 📊.
