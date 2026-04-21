/**
 * Test the Lambda handler with mocked SDK (no API calls).
 */
import { handler, extractJson } from "./handler.js";

delete process.env.SCANNER_MCP_URL;
delete process.env.SCANNER_MCP_API_KEY;
delete process.env.CLAUDECODE;

const SAMPLE_RESULT = {
  classification: "SUSPICIOUS",
  confidence: "medium",
  confidence_pct: 65,
  summary:
    "Multiple failed SSH logins from external IP. Pattern suggests brute-force attempt.",
  timeline: [
    {
      timestamp: "2025-01-15T10:00:00Z",
      event: "First failed SSH login from 203.0.113.42",
    },
    {
      timestamp: "2025-01-15T10:05:00Z",
      event: "15 additional failed attempts over 5 minutes",
    },
  ],
  hypothesis_testing: {
    confirmed:
      "Brute-force pattern: rapid sequential failures from single IP",
    ruled_out: [
      "Legitimate user: no successful logins from this IP in past 90 days",
      "Misconfiguration: pattern is external, not internal service",
    ],
  },
  key_evidence: [
    "16 failed SSH logins in 5 minutes from 203.0.113.42",
    "IP not seen in previous 90-day baseline",
  ],
  mitre_attack: [],
  next_questions: [
    "Is 203.0.113.42 associated with any known VPN or proxy service?",
    "Were any successful logins observed from this IP after the alert window?",
  ],
};

// Mock the SDK query function
jest.mock("@anthropic-ai/claude-agent-sdk", () => ({
  query: jest.fn(() => ({
    async *[Symbol.asyncIterator]() {
      yield {
        type: "result",
        subtype: "success",
        result: JSON.stringify(SAMPLE_RESULT),
      };
    },
  })),
}));

// --- Lambda handler tests ---

test("lambda handler returns 200 with expected schema", async () => {
  const event = {
    alert_id: "test-001",
    alert_summary: "Multiple failed SSH logins from IP 203.0.113.42",
  };

  const response = await handler(event, {} as never, (() => {}) as never);

  expect(response.statusCode).toBe(200);
  const body = JSON.parse(response.body);
  expect(body.alert_id).toBe("test-001");

  const result = body.result;
  const requiredKeys = [
    "classification",
    "confidence",
    "confidence_pct",
    "summary",
    "timeline",
    "hypothesis_testing",
    "key_evidence",
    "mitre_attack",
    "next_questions",
  ];
  for (const key of requiredKeys) {
    expect(result).toHaveProperty(key);
  }
  expect(["BENIGN", "SUSPICIOUS", "MALICIOUS"]).toContain(result.classification);
  expect(["high", "medium", "low"]).toContain(result.confidence);
  expect(typeof result.confidence_pct).toBe("number");
  expect(result.confidence_pct).toBeGreaterThanOrEqual(0);
  expect(result.confidence_pct).toBeLessThanOrEqual(100);
  expect(Array.isArray(result.timeline)).toBe(true);
  expect(typeof result.hypothesis_testing).toBe("object");
  expect(result.hypothesis_testing).toHaveProperty("confirmed");
  expect(result.hypothesis_testing).toHaveProperty("ruled_out");
  expect(Array.isArray(result.key_evidence)).toBe(true);
  expect(Array.isArray(result.next_questions)).toBe(true);
  expect(result.next_questions.length).toBeGreaterThan(0);
});

test("lambda handler returns 400 for missing fields", async () => {
  const response = await handler({}, {} as never, (() => {}) as never);
  expect(response.statusCode).toBe(400);
});

// --- extractJson unit tests ---

test("extractJson parses plain JSON", () => {
  expect(extractJson('{"a": 1}')).toEqual({ a: 1 });
});

test("extractJson parses code block", () => {
  const text = '```json\n{"classification": "BENIGN"}\n```';
  expect(extractJson(text)).toEqual({ classification: "BENIGN" });
});

test("extractJson parses JSON surrounded by text", () => {
  const text =
    'Here is my analysis:\n{"classification": "SUSPICIOUS"}\nEnd of analysis.';
  expect(extractJson(text)).toHaveProperty("classification", "SUSPICIOUS");
});

test("extractJson throws on invalid input", () => {
  expect(() => extractJson("no json here at all")).toThrow(
    /Could not extract JSON/
  );
});
