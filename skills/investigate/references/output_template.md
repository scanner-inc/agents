# investigate — output template

The final response of `/investigate` is terminal markdown shaped like this. Adapt the structure to the question — not every section belongs in every answer. A small question (e.g. "did this user log in today?") may need only the verdict blockquote + TL;DR + one or two evidence bullets.

````
✅ Finding

> <One-line headline answer — the verdict in plain English. The most important sentence in the response, the one a reader who reads nothing else would walk away with.>

TL;DR: <1-2 sentences. First: what you checked. Second: the one thing that matters and the recommended next move.>

[For each topic in scope, one section. Lead with a status read, then the supporting data. Use a fenced code block for any 2+ column data or 3+ aligned rows.]

**<Topic>** — <one-line health/status read, e.g. "healthy", "under-utilized", "anomalous">
```
col-1-header  col-2-header  col-3-header
row-1-val     row-1-val     row-1-val
row-2-val     row-2-val     row-2-val
```
<1-2 lines of prose context if the table doesn't speak for itself.>

Timeline (only when a timeline is the answer):
- `<timestamp>` <event>
- `<timestamp>` <event>

What I could not confirm (only if there's an analyst-relevant visibility gap — not parser quirks or implementation noise):
- <What you searched, what was not found, why it is inconclusive>

Next questions (cap at 2; only include if they would actually unblock further work):
- <Follow-up that would close a gap or deepen the investigation>
- <Follow-up about broader context>
````

Aim for under 30 lines total. Keep it a reply, not a blog post.

## Output rules

- The verdict blockquote leads. There is no other blockquote in the response — don't scatter `>` lines across sections.
- For each topic, lead with a one-line health/status read (`healthy`, `under-utilized`, `anomalous`, `noisy`, etc.), then the data, then 1-2 lines of prose context.
- Tables go in fenced code blocks with aligned columns. Tables-as-prose ("a (3.09B), b (1.14B), c (1.08B), …") is harder to scan; use the fenced block for any 2+ column data or 3+ aligned rows.
- *What I could not confirm* is for analyst-relevant visibility gaps only — parser quirks, missing optional fields, and implementation noise don't belong here.
- Cap *Next questions* at 2, and skip the section if the only follow-ups would be filler.

## Formatting rules

- Use backticks for IPs, field names, commands, usernames, hashes, index names, event names, MITRE tags.
- Cite MITRE tactics and techniques by canonical tag (e.g. `techniques.t1078.valid_accounts`), not display name.
- Cite Scanner sources by slug (`aws-cloudtrail`, `okta`).
- Begin the reply with `✅ Finding`. End with the last *Next questions* bullet (or with the topic sections if no follow-ups are worth listing). No preamble, no trailing commentary.
