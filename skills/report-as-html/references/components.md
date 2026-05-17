# Component vocabulary

Markdown → HTML component mapping. Each component below has a snippet you can paste into the `{{CONTENT}}` placeholder of `templates/cream-light.html`. Use these patterns rather than inventing new ones.

## 1. Verdict block (always near the top)

The opinionated one-line headline that the calling skill produced. Lifts straight from the markdown blockquote (`> …`).

```html
<div class="verdict amber" role="status">
  <span class="badge">🟡 coverage gaps + housekeeping</span>
  <p><strong>{{ONE-LINE HEADLINE WITH BOLDED PHRASE}}</strong> {{rest of the sentence}}.</p>
</div>
```

Variants: drop `amber` (default green), or replace with `red`. Badge text comes from the calling skill — use traffic-light emoji (🟢 🟡 🔴) only when the calling skill itself used them.

## 2. Stat tiles row (1–5 tiles)

For top-level counts.

```html
<div class="stats">
  <div class="stat"><div class="num">113</div><div class="lbl">total rules</div></div>
  <div class="stat warn"><div class="num">3</div><div class="lbl">sources w/ no coverage</div></div>
  <div class="stat good"><div class="num">2</div><div class="lbl">oob packs available</div></div>
</div>
```

Use `.warn`/`.bad`/`.good` modifier classes only when the number itself encodes a state (a *count* of broken things vs a *count* of total things). Don't color neutral counts.

## 3. Section header

```html
<section>
  <h2>🎯 Section title</h2>
  …content…
</section>
```

Emojis are optional and live on the `h2` (the CSS makes them uppercase-letterspaced — emoji renders fine alongside).

## 4. Numbered top-N cards (top-5 next moves)

For prioritized action lists.

```html
<ol class="top">
  <li>
    <div class="title">{{Action verb + target}}</div>
    <div class="desc">{{One-line rationale.}}</div>
    <div class="cmd"><span class="arr">→</span><span class="skill">/skill-name</span>{{args}}</div>
  </li>
  …more list items…
</ol>
```

For UI-step commands (no slash command), use `<div class="cmd ui">` and start with `▶` instead of `→`.

## 5. Track entry cards (Track A / B / C / OOB)

For lists of recommendations or findings. Each entry can carry a severity-coded left border.

```html
<ul class="track">
  <li class="sev-high">
    <div class="entry-title">{{Concrete behaviour or rule name}}</div>
    <div class="meta">
      <span class="pill source">source.github</span>
      <span class="pill tag">techniques.t1567.exfiltration_over_web_service</span>
      <span class="pill regime">needle-in-haystack</span>
    </div>
    <pre class="codeblock">{{filter sketch or query fragment}}</pre>
    <div class="body">{{One-line rationale.}}</div>
    <div class="cmd"><span class="arr">→</span><span class="skill">/write-detection</span>{{prompt}}</div>
  </li>
</ul>
```

Severity class is required: `sev-critical`, `sev-high`, `sev-medium`, `sev-low`, `sev-info`, `sev-corr`, `sev-pack`. Pills are optional; common variants: `pill.source`, `pill.tag`, `pill.regime`, `pill.sev`, `pill.fires`.

## 6. Coverage matrix (tactic × source heat-table)

```html
<table class="matrix">
  <thead>
    <tr>
      <th class="tac">Tactic</th>
      <th>cloudtrail</th><th>auth0</th><th>github</th>
    </tr>
  </thead>
  <tbody>
    <tr><td class="tac">initial_access</td><td class="cov-lo">3</td><td class="cov-lo">3</td><td class="cov-0">0</td></tr>
    <tr><td class="tac">defense_evasion</td><td class="cov-hi">32</td><td class="cov-md">9</td><td class="cov-0">0</td></tr>
  </tbody>
</table>
<div class="matrix-note">{{One-line summary highlighting the biggest hole.}}</div>
```

Cell classes (cell value still goes inside `<td>`):
- `.cov-0`  — zero rules (greyed out background)
- `.cov-lo` — 1–4 rules (amber background)
- `.cov-md` — 5–10 rules (olive-green background)
- `.cov-hi` — 11+ rules (green background)

## 7. Data table (top operations, accounts, IPs, regions, errors)

```html
<table class="data">
  <thead><tr><th class="num">Events</th><th>Operation</th><th>Read</th></tr></thead>
  <tbody>
    <tr><td class="num">80,416</td><td><code class="inline">s3:DeleteObject</code></td><td class="note">bulk S3 cleanup</td></tr>
  </tbody>
</table>
```

For bar-graph cells (e.g., percentage-of-total):

```html
<td class="bar-cell"><div class="bar" style="width:62.6%;"><div class="bar-fill" style="width:100%;"></div></div></td>
```

The outer `.bar` width is the value-scale; `.bar-fill` is normally 100% (the inner bar is purely visual).

## 8. SVG diagram canvas

For flow / column / Sankey-style diagrams (see `/tmp/leo-aws-30d.html` for a reference). Wrap the SVG in:

```html
<div class="diagram">
  <svg viewBox="0 0 920 640" xmlns="http://www.w3.org/2000/svg">…</svg>
  <div class="diagram-caption">{{caption}}</div>
</div>
```

Use the same palette CSS variables inside the SVG. Don't try to inline these via JS — just write the SVG by hand. Width: `width="100%"` via CSS; keep the `viewBox` so it scales.

## 9. Bulleted interpretation list

For "notable interpretations" style narrative bullets.

```html
<ul class="bullets">
  <li><strong>{{key phrase}}.</strong> {{sentence-or-two of context.}}</li>
</ul>
```

## 10. Two-column row

For side-by-side small tables (e.g., "Source IPs | Regions").

```html
<div class="row2">
  <section>…</section>
  <section>…</section>
</div>
```

Collapses to one column under 720px.

## What goes where (cheat sheet)

| Calling-skill section          | Component                                  |
|--------------------------------|--------------------------------------------|
| Verdict / headline             | `verdict` block                            |
| 1–5 top-level counts           | `stats` row                                |
| Top-N next moves               | `<ol class="top">`                         |
| New rule / tuning / correlation suggestions | `<ul class="track">`            |
| OOB pack recommendations       | `<ul class="track">` with `sev-pack`       |
| MITRE-tactic-by-source matrix  | `table.matrix`                             |
| Lists of events / IPs / errors | `table.data`                               |
| Architectural / flow diagrams  | `.diagram` (SVG)                           |
| Narrative interpretation       | `<ul class="bullets">`                     |
| Side-by-side tables            | `.row2`                                    |
| Trailing skill name + scope    | `<footer>` (in the template)               |
