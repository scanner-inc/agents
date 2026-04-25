# Scanner query syntax cheatsheet

Read this file when you are about to compose a Scanner query for the hunt (Phase 3) or for any investigation that needs to express OR / wildcard / IOC sweep semantics.

## Core rules

- Use `@index=<index-name>` to narrow searches. Examples: `@index=global-cloudtrail`, `@index=okta`, `@index=_detections`.
- **Never** use bare `OR` between `field:value` pairs — it breaks operator precedence. Always group multiple values for the same field in parentheses:
  - ✅ `sourceIPAddress: ("23.27.124.*" "23.27.140.*")`
  - ❌ `sourceIPAddress: 23.27.124.* OR sourceIPAddress: 23.27.140.*`
  - ✅ `eventName: ("CreateFunction20150331" "UpdateFunctionCode20150331v2")`
  - ❌ `eventName: "X" OR eventName: "Y"`
- Wildcard field search across all fields: `**: "value"`. Use this for cheap IOC sweeps when you don't yet know which field will hold the indicator.
- Aggregations: `| groupbycount <field>`, `| count`, `| where @q.count > N`. Pipe operators come after the filter expression.
- Time ranges are passed via `from` / `to` parameters on `execute_query`, not embedded in the query string. Use ISO 8601.

## IOC sweep pattern

For the threat hunt, start broad then pivot:

1. One cheap wildcard sweep per IOC: `**: "23.27.124.45"`. Run several in parallel.
2. Only on a hit, pivot to a targeted query against the relevant index to gather context: `@index=global-cloudtrail sourceIPAddress: "23.27.124.45" | groupbycount eventName, userIdentity.arn`.
3. If sweeps come back clean, you are done. Do **not** speculate with extra behavioral queries when there is no IOC match to investigate.

## Tool reminders

- Always call `get_scanner_context` first if you have not already in this session — it returns the available log indices and a context token required by `execute_query`.
- Use `get_top_columns` to discover what fields exist in a given index when you are unsure.
- Use `get_docs` for syntax questions you can't resolve from this cheatsheet.
- Run multiple `execute_query` calls in parallel when the queries are independent.
