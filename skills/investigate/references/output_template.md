# investigate — output template

The final response of `/investigate` is terminal markdown shaped like this. Adapt the structure to the question — not every section belongs in every answer. A small question (e.g. "did this user log in today?") may need only TL;DR + one or two evidence bullets.

```
✅ Finding

TL;DR: <1-2 sentence direct answer to the user's question>

Evidence:
- <Specific query or lookup → what it returned, with `code` for technical values>
- <Specific query or lookup → what it returned>
- <Specific query or lookup → what it returned>

Timeline:  (include only if a timeline is relevant)
- `<timestamp>` <event>
- `<timestamp>` <event>

> <Blockquote for the single most critical piece of evidence or context>

What I could not confirm:  (include only if there are real visibility gaps)
- <What you searched, what was not found, why it is inconclusive>

Recommended Next Questions:
- <Follow-up that would close a gap or deepen the investigation>
- <Follow-up about broader context>
```

Aim for under 30 lines total. Keep it a reply, not a blog post.

## Formatting rules

- Use backticks for IPs, field names, commands, usernames, hashes, index names, event names, MITRE tags.
- Cite MITRE tactics and techniques by canonical tag (e.g. `techniques.t1078.valid_accounts`), not display name.
- Cite Scanner sources by slug (`aws-cloudtrail`, `okta`).
- Begin the reply with `✅ Finding`. End with the last "Recommended Next Questions" bullet. No preamble, no trailing commentary.
