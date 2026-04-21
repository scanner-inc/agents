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
        Post to #${slackChannelName} (channel ID: ${slackChannelId}) using this template:

        🔍 *Threat Hunt Report*

        *Hunt Target*: [CVE ID] — [Vulnerability Name] | [Vendor/Product]
        *Intel Source*: CISA KEV (added [date]) + [threat report source]

        *TL;DR*: [2 sentence summary: First sentence describes what was hunted and the scope. Second sentence states the key finding — whether evidence of exploitation was found or not, and recommended action.]

        *IOCs Searched*:
        • \`[IP address]\` — [context, e.g. "C2 server from CrowdStrike report"]
        • \`[domain.com]\` — [context]
        • \`[SHA-256 hash]\` — [context, e.g. "malware payload"]

        *Hunt Results*: [🟢 NO EVIDENCE FOUND / 🟡 INCONCLUSIVE / 🔴 EVIDENCE OF COMPROMISE]
        *Confidence*: [XX%] ([High/Medium/Low])
        *Time Range Searched*: [start date] — [end date]

        *Findings*:
        • ✓ or ✗ [Finding 1 — what was searched and what was found/not found]
        • ✓ or ✗ [Finding 2 with \`technical details\`]
        • ✓ or ✗ [Finding 3]

        *Timeline*: [Only if suspicious activity found]
        • \`[Timestamp]\` - [Event description]
        • \`[Timestamp]\` - [Event description]

        *MITRE ATT&CK*: [Tactics and techniques hunted for, e.g. T1190 Exploit Public-Facing Application, T1059 Command & Scripting Interpreter]

        > [Blockquote for most critical finding or context]

        *Visibility Gaps*:
        • [Log source or telemetry that was missing or insufficient]
        • [Time periods with no coverage]

        *Recommended Next Questions*:
        • [Question an analyst should investigate next, e.g. "Are any of these IPs seen in other customer environments?"]
        • [Question about visibility gaps, e.g. "Do we have DNS logs that would show resolution of these C2 domains?"]
        • [Question about broader context, e.g. "Has this vulnerability been exploited against similar environments?"]

        **Slack Formatting Rules**:
        - Use *bold* (single asterisk, not double)
        - Use \`code\` for IPs, usernames, file paths, commands
        - Use > for blockquotes/important notes
        - Use emojis for status indicators
        - Add line breaks between sections for readability
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
