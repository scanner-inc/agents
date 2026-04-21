/**
 * Test the threat hunting agent with mocked SDK and CISA KEV (no API calls).
 */

delete process.env.SCANNER_MCP_URL;
delete process.env.SCANNER_MCP_API_KEY;
delete process.env.CLAUDECODE;

// Set required env vars for tests
process.env.SCANNER_MCP_URL = "https://mcp.scanner.test/sse";
process.env.SCANNER_MCP_API_KEY = "test-scanner-key";
process.env.SLACK_BOT_TOKEN = "xoxb-test-token";
process.env.SLACK_TEAM_ID = "T12345";
process.env.SLACK_CHANNEL_ID = "C12345";
process.env.SLACK_CHANNEL_NAME = "test-channel";
process.env.OTX_API_KEY = "test-otx-key";
process.env.ABUSECH_AUTH_KEY = "test-abusech-key";

const mockQueryFn = jest.fn();

jest.mock("@anthropic-ai/claude-agent-sdk", () => ({
  query: (...args: unknown[]) => {
    mockQueryFn(...args);
    return {
      async *[Symbol.asyncIterator]() {
        yield {
          type: "assistant",
          message: {
            content: [
              { type: "text", text: "Hunt complete. No evidence of compromise found." },
            ],
          },
        };
      },
    };
  },
}));

jest.mock("dotenv", () => ({
  config: jest.fn(),
}));

import { runThreatHunt, fetchCisaKev } from "./threat_hunt.js";

// Mock global fetch for CISA KEV
const mockFetch = jest.fn();
global.fetch = mockFetch as unknown as typeof fetch;

const SAMPLE_KEV = {
  vulnerabilities: [
    {
      cveID: "CVE-2024-1234",
      vulnerabilityName: "Test Vulnerability",
      vendorProject: "TestVendor",
      product: "TestProduct",
      dateAdded: "2024-12-01",
      dueDate: "2024-12-15",
      shortDescription: "A test vulnerability for unit testing",
    },
  ],
};

beforeEach(() => {
  mockQueryFn.mockClear();
  mockFetch.mockClear();
  mockFetch.mockResolvedValue({
    ok: true,
    json: async () => SAMPLE_KEV,
  });
});

test("fetchCisaKev returns sorted entries", async () => {
  const result = await fetchCisaKev(1);
  expect(result).toHaveLength(1);
  expect(result[0].cveID).toBe("CVE-2024-1234");
  expect(mockFetch).toHaveBeenCalledTimes(1);
});

test("threat hunt completes with mocked SDK and KEV", async () => {
  await runThreatHunt();
  expect(mockQueryFn).toHaveBeenCalledTimes(1);
});

test("threat hunt passes correct tools and MCP servers", async () => {
  await runThreatHunt();
  const callArgs = mockQueryFn.mock.calls[0][0];

  expect(callArgs).toHaveProperty("prompt");
  expect(callArgs.prompt).toContain("CVE-2024-1234");
  expect(callArgs.prompt).toContain("threat hunt");

  expect(callArgs).toHaveProperty("options");
  expect(callArgs.options.allowedTools).toContain("mcp__scanner__execute_query");
  expect(callArgs.options.allowedTools).toContain("mcp__slack__slack_post_message");
  expect(callArgs.options.allowedTools).toContain("mcp__threatintel__threatfox_iocs");
  expect(callArgs.options.allowedTools).toContain("mcp__threatintel__feodo_tracker");
});

test("threat hunt configures all three MCP servers", async () => {
  await runThreatHunt();
  const callArgs = mockQueryFn.mock.calls[0][0];
  const servers = callArgs.options.mcpServers;

  expect(servers).toHaveProperty("scanner");
  expect(servers.scanner.type).toBe("http");

  expect(servers).toHaveProperty("slack");
  expect(servers.slack.type).toBe("stdio");
  expect(servers.slack.command).toBe("npx");

  expect(servers).toHaveProperty("threatintel");
  expect(servers.threatintel.type).toBe("stdio");
  expect(servers.threatintel.command).toBe("npx");
});
