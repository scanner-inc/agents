// threat_hunt.ts — autonomous threat hunting agent
//
// Combines CISA KEV vulnerability data with structured IOCs from threat intel
// feeds, hunts over 1+ years of Scanner logs, and posts findings to Slack.
import { query } from "@anthropic-ai/claude-agent-sdk";
import type { McpHttpServerConfig } from "@anthropic-ai/claude-agent-sdk";
import { config } from "dotenv";

// Allow running inside another Claude Code session (e.g., during testing)
delete process.env.CLAUDECODE;

const CISA_KEV_URL =
  "https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json";

interface KevEntry {
  cveID: string;
  vulnerabilityName: string;
  vendorProject?: string;
  product?: string;
  dateAdded?: string;
  dueDate?: string;
  shortDescription?: string;
}

export async function fetchCisaKev(count = 5): Promise<KevEntry[]> {
  const resp = await fetch(CISA_KEV_URL);
  if (!resp.ok) throw new Error(`CISA KEV fetch failed: ${resp.status}`);
  const data = (await resp.json()) as { vulnerabilities?: KevEntry[] };
  const vulns = data.vulnerabilities ?? [];
  vulns.sort((a, b) => (b.dateAdded ?? "").localeCompare(a.dateAdded ?? ""));
  return vulns.slice(0, count);
}

function requireEnv(name: string): string {
  const val = process.env[name];
  if (!val) throw new Error(`${name} environment variable not set`);
  return val;
}

interface StdioMcpServerConfig {
  type: "stdio";
  command: string;
  args: string[];
  env: Record<string, string>;
}

type McpConfig = Record<string, McpHttpServerConfig | StdioMcpServerConfig>;

export async function runThreatHunt(): Promise<void> {
  config(); // load .env

  const scannerMcpUrl = requireEnv("SCANNER_MCP_URL");
  const scannerMcpApiKey = requireEnv("SCANNER_MCP_API_KEY");
  const slackBotToken = requireEnv("SLACK_BOT_TOKEN");
  const slackTeamId = requireEnv("SLACK_TEAM_ID");
  const slackChannelId = requireEnv("SLACK_CHANNEL_ID");
  const slackChannelName = requireEnv("SLACK_CHANNEL_NAME");
  const otxApiKey = requireEnv("OTX_API_KEY");
  const abusechAuthKey = requireEnv("ABUSECH_AUTH_KEY");

  // Pre-fetch CISA KEV data
  console.log("Fetching CISA Known Exploited Vulnerabilities...");
  const kevVulns = await fetchCisaKev(5);
  const kevContext = kevVulns
    .map(
      (v) =>
        `  - ${v.cveID}: ${v.vulnerabilityName} | ` +
        `Vendor: ${v.vendorProject ?? "N/A"} | ` +
        `Product: ${v.product ?? "N/A"} | ` +
        `Added: ${v.dateAdded ?? "N/A"} | ` +
        `Due: ${v.dueDate ?? "N/A"} | ` +
        `Description: ${v.shortDescription ?? "N/A"}`
    )
    .join("\n");
  console.log(`Fetched ${kevVulns.length} recent KEV entries`);

  const mcpServers: McpConfig = {
    scanner: {
      type: "http",
      url: scannerMcpUrl,
      headers: {
        Authorization: `Bearer ${scannerMcpApiKey}`,
      },
    },
    slack: {
      type: "stdio",
      command: "npx",
      args: ["-y", "@modelcontextprotocol/server-slack"],
      env: {
        SLACK_BOT_TOKEN: slackBotToken,
        SLACK_TEAM_ID: slackTeamId,
      },
    },
    threatintel: {
      type: "stdio",
      command: "npx",
      args: ["-y", "mcp-threatintel-server"],
      env: {
        OTX_API_KEY: otxApiKey,
        ABUSECH_AUTH_KEY: abusechAuthKey,
      },
    },
  };

  const prompt = `
        You are an autonomous threat hunting agent. Your mission is to proactively
        hunt for evidence of compromise in historical logs using threat intelligence.

        **Tool Usage**: If tool responses return large JSON files, use \`jq\` via Bash
        to extract what you need, or use the \`Read\` tool to read files in chunks.
        You only have access to Bash for \`jq\` commands — do not use Bash for anything else.

        **CISA Known Exploited Vulnerabilities (most recently added):**
${kevContext}

        Execute the following 6-phase threat hunt:

        **Phase 1: Environment Discovery**
        - Call \`get_scanner_context\` to understand what log sources are available in Scanner
        - Identify the environment: what platforms, vendors, services, and log types exist
        - Note what kinds of IOCs are searchable (IPs, domains, hashes, user agents, etc.)
        - This context determines which threats are worth hunting for

        **Phase 2: Threat Intelligence Gathering**
        - Review the CISA KEV data above — these are recently added actively exploited vulnerabilities
        - **CRITICAL**: Filter KEV entries for relevance to the environment discovered in Phase 1.
          Skip vulnerabilities for products/vendors not present in your log sources.
          Prioritize vulnerabilities that match your environment (e.g., if you see AWS/cloud logs,
          prioritize cloud-relevant CVEs; if you see identity provider logs, prioritize
          auth-related CVEs).
        - Use \`threatfox_iocs\` to get recent IOCs — focus on IOC types that are actually
          searchable in the available log sources
        - Use \`otx_get_pulses\` or \`otx_search_pulses\` for community intel on relevant CVEs
        - Use \`feodo_tracker\` for botnet C2 IPs
        - Select the most actionable threat: best combination of environment relevance +
          concrete searchable IOCs
        - If no CISA KEV entries are relevant to the environment, pivot to hunting for
          IOCs from ThreatFox/Feodo that match searchable log fields (e.g., known-bad IPs
          in network flow logs, malicious domains in DNS logs)
        - **Determine search time range** based on threat intel:
          - When was the vulnerability first disclosed or added to KEV?
          - When were the IOCs first reported (ThreatFox first_seen, OTX pulse creation date)?
          - When did active exploitation campaigns begin?
          - Set search window from the earliest known threat activity to present.
            For example: a CVE from 2023 with IOCs first seen 18 months ago → search 2+ years.
            A brand-new campaign from last month → 90 days is enough.

        **Phase 3: Announce the Hunt (Slack post #1)**
        - Post to #${slackChannelName} (channel ID: ${slackChannelId}):
          - What CVE/campaign is being hunted
          - Sources: CISA KEV + ThreatFox/OTX/Feodo data
          - Specific IOCs being searched for (IPs, domains, hashes)
          - Time range being searched and why (based on threat timeline)
        - Apply the same chip discipline as Phase 6 (see Slack Formatting Rules below):
          ration backticks to copy-paste-able tokens; plain dates and vendor names stay
          unwrapped. Keep this announcement short — bullets, not paragraphs.

        **Phase 4: Historical Log Analysis via Scanner**
        - Query Scanner using the time range determined in Phase 2

        **Scanner query syntax rules**:
        - Use \`@index=<index-name>\` (not \`%ingest.source_type\`) to narrow searches
        - **NEVER use bare OR between field:value pairs.** It breaks precedence.
          ALWAYS group multiple values for the same field in parentheses:
          ✅ \`sourceIPAddress: ("23.27.124.*" "23.27.140.*")\`
          ❌ \`sourceIPAddress: 23.27.124.* OR sourceIPAddress: 23.27.140.*\`
          ✅ \`eventName: ("CreateFunction20150331" "UpdateFunctionCode20150331v2")\`
          ❌ \`eventName: "X" OR eventName: "Y"\`
        - Wildcard field search: \`**: "value"\` searches across all fields

        **Search strategy — IOC sweep first, then pivot**:
        1. Start with broad IOC sweeps using \`**: "IOC"\` queries (IPs, domains, hashes).
           These are cheap and search everything. Run one query per IOC or small batch.
        2. Only if you find hits: pivot to targeted behavioral queries on the relevant
           index (e.g., \`@index=global-cloudtrail eventName: (...)\`) to build context
           around the match — what happened before/after, same user/source, etc.
        3. If IOC sweeps come back clean, you're done with searching. Do NOT run
           speculative behavioral queries when there are no IOC matches to investigate.
        - Keep total queries minimal: 3-6 for a clean hunt, more only if you find hits

        **Phase 5: Correlation & Assessment**
        - Cross-reference findings across log sources
        - Build timeline of any suspicious activity
        - Map to MITRE ATT&CK matrix
        - Assess scope (affected systems, users, time range)
        - Identify visibility/telemetry gaps

        **Phase 6: Report Findings (Slack post #2)**
        Post to #${slackChannelName} (channel ID: ${slackChannelId}) using this template.
        Lead with the verdict, then justify it.

        🔍 *Threat Hunt Report*

        > [One-line headline verdict in plain English. The most important sentence in the report — what people see in Slack's channel preview. State the result *and* the most consequential nuance, e.g. "🟢 No evidence of SimpleHelp exploitation across 180 days; the real story is that 4 of 5 KEV entries target log sources we don't ingest — coverage gap, not detection gap."]

        *Hunt*: [CVE ID(s)] — [vulnerability or threat name] | [vendor/product or threat family]
        *Range*: [start date] → [end date] · *Confidence*: [XX%] [High/Medium/Low] · *Result*: [🟢 NO EVIDENCE FOUND / 🟡 INCONCLUSIVE / 🔴 EVIDENCE OF COMPROMISE]
        *Intel*: CISA KEV (added [date]) + [ThreatFox / OTX / Feodo / URLhaus / MalwareBazaar as applicable]

        *IOCs searched* — [one-line summary, e.g. "all clean, 786 GB scanned"]
        \`\`\`
        162.243.103.246   Emotet C2   DigitalOcean        seen 2026-03-07
        50.16.16.211      QakBot C2   AWS EC2 (online)    seen 2025-12-30
        ...
        \`\`\`
        [1-2 lines of prose context — what each threat-intel tool returned, e.g. "ThreatFox had no IOCs for CVE-2024-57726; OTX Akira pulse yielded contextual TTPs only."]

        [Pick one — *Why this came back clean* for hunts with no hits, *Findings* for hunts with positive hits. Don't emit both.]

        *Why this came back clean*:
        [1-3 sentences explaining the analytical insight — *why* nothing matched. Examples: "Four of five KEV entries target on-prem appliances not represented in this cloud-native environment." or "Hunt scope necessarily pivoted to generic C2 sweeps because ThreatFox had no IOCs seeded for these CVEs."]

        *Findings*:
        • ✓ or ✗ [What was searched and what was or was not found, with \`technical details\`]
        • ✓ or ✗ [Next finding]

        *Timeline* (only if suspicious activity found; omit the whole section if not):
        • \`[Timestamp]\` [Event description]
        • \`[Timestamp]\` [Event description]

        *MITRE ATT&CK*: [Tactics and techniques hunted for, cited by canonical tag: \`tactics.ta0011.command_and_control\`, \`techniques.t1190.exploit_public_facing_application\`, etc.]

        *Visibility gaps* (in order of fixability — closable gaps first, environmental facts last; cap at 4):
        • *[Most-actionable gap]* — [what hunting capability it would unlock, name the specific IOC or TTP it relates to, e.g. "would have caught egress C2 to AWS-hosted QakBot node \`50.16.16.211\`"]
        • [Next gap, same structure]

        *Next questions* (cap at 2; only include if they would actually unblock further work):
        • [Follow-up that would close the most actionable visibility gap or confirm an applicability question]
        • [Follow-up about scope or broader context]

        **Slack Formatting Rules**:

        Use:
        - \`*bold*\` for bold (single asterisk, not double)
        - Single-backtick \`code\` formatting for things a reader might copy: IPs, domains, file hashes, CVE IDs, MITRE tag IDs (\`techniques.t1190.exploit_public_facing_application\`), exact field names, Scanner query fragments.
        - **Ration the chips.** Plain dates (2026-04-24), vendor/product names mentioned in prose, severity labels, and result counts stay unwrapped. Chips lose meaning when half the message is orange — if you've used more than ~10 in the response, you've over-wrapped.
        - \`•\` for top-level bullets, \`◦\` for sub-bullets.
        - \`>\` at the start of a line for the headline blockquote at the top.
        - Triple-backtick fenced code blocks (multi-line) for tabular data — the *IOCs searched* list is the textbook case. Align columns with spaces. Tables-as-prose ("\`162.243.103.246\` (Emotet C2, DigitalOcean), \`50.16.16.211\` (QakBot C2, AWS), …") is the chip-soup failure mode in disguise.
        - Literal Unicode emoji (🔍, 🟢, 🟡, 🔴, ✓, ✗), never shortcodes.

        Do not use:
        - \`#\` or \`##\` headers; use \`*Bold Text*\` for section titles.
        - \`**double asterisk**\` for bold (renders as literal asterisks).
        - \`- \` or \`* \` for bullets; use \`•\`.
        - \`---\` or \`***\` separators.
        - Triple-backtick code fences **around the entire response**. (Targeted multi-line code blocks for tabular data are encouraged — see "Use" above.)
    `;

  const start = Date.now();

  const q = query({
    prompt,
    options: {
      model: process.env.MODEL || "claude-opus-4-6",
      permissionMode: "bypassPermissions",
      allowDangerouslySkipPermissions: true,
      mcpServers: mcpServers as Record<string, never>,
      allowedTools: [
        // Scanner
        "mcp__scanner__get_scanner_context",
        "mcp__scanner__execute_query",
        "mcp__scanner__fetch_query_results",
        // File reading and JSON processing (for large tool responses)
        "Read",
        "Bash(jq:*)",
        // Slack
        "mcp__slack__slack_post_message",
        "mcp__slack__slack_list_channels",
        // Threat intel
        "mcp__threatintel__threatfox_iocs",
        "mcp__threatintel__threatfox_search",
        "mcp__threatintel__urlhaus_recent",
        "mcp__threatintel__malwarebazaar_recent",
        "mcp__threatintel__feodo_tracker",
        "mcp__threatintel__otx_get_pulses",
        "mcp__threatintel__otx_search_pulses",
        "mcp__threatintel__threatintel_lookup_ip",
        "mcp__threatintel__threatintel_lookup_domain",
        "mcp__threatintel__threatintel_lookup_hash",
        "mcp__threatintel__threatintel_lookup_url",
        "mcp__threatintel__threatintel_status",
      ],
    },
  });

  for await (const message of q) {
    if (message.type === "assistant") {
      for (const block of message.message.content) {
        if (block.type === "text") {
          console.log(block.text);
        } else if (block.type === "tool_use") {
          console.log(JSON.stringify({
            step: "tool_call",
            tool: block.name,
            input: block.input,
          }));
        }
      }
    }
  }

  const durationMs = Date.now() - start;
  console.log(
    JSON.stringify({
      timestamp: new Date().toISOString(),
      agent: "threat-hunt",
      duration_ms: durationMs,
    })
  );
}

if (require.main === module) {
  runThreatHunt().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
