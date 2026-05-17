---
name: report-as-html
description: Render a Scanner-style report (terminal markdown + structured data the calling skill already gathered) as a polished, light-mode, cream/teal HTML file ready to open in the browser. **Not a stand-alone analysis skill — does not generate findings.** Use only as a follow-up step after another skill (`/posture-report`, `/recommend-detections`, `/triage-alert`, `/threat-hunt`, `/investigate`, `/lookup-ioc`) has produced a finished terminal report and the user has answered "yes, render an HTML version." Reads `templates/cream-light.html` for the skeleton and `references/style-guide.md` + `references/components.md` for the component vocabulary, writes a single self-contained HTML file under `/tmp/`, and (if the user separately says yes) opens it via `open`. Use when the user types `/report-as-html`, says "yes" to a follow-up HTML offer from another report skill, or asks "can you make that an HTML report?"
---

# report-as-html

## When to invoke

Trigger on any of:

- Another report skill has just emitted a finished terminal report and asked the user "Want this as an HTML report?" and the user said yes.
- The user types `/report-as-html`.
- The user says "can you turn that into an HTML report?" or "make me an HTML version".

**Do not** invoke this skill to generate analysis from scratch. It is a renderer, not a generator. The calling skill must have already produced a complete report.

## What it produces

A single self-contained HTML file at `/tmp/<slug>-<YYYY-MM-DD>.html`:

- Light cream background (`#fafaf7`), white panels, dark teal accent (`#1f5d56`).
- Serif headings (Charter / Iowan Old Style), sans body, mono for code and field paths.
- Verdict block with severity-colored left border (green / amber / red).
- Stat-tile row (1-5 tiles).
- Section headers in uppercase accent color.
- Component vocabulary: data tables, numbered top-N cards, severity-coded track lists, coverage-matrix heatmap, SVG diagram canvas, key-bullet lists, footer.
- Print-friendly (`@media print` rules).

## Workflow

1. **Confirm scope.** Confirm with the user: which sections from the terminal report should the HTML include? Default is "everything"; offer to trim if the report is very long.
2. **Pick the slug + date.** Default slug = report kind + tenant or topic (e.g. `scanner-recommendations`, `posture-report`, `triage-<alert-id-short>`). Date = today in `YYYY-MM-DD`. Output path = `/tmp/<slug>-<date>.html`.
3. **Map the report to components.** Read `references/components.md`. For each section of the terminal report, pick the matching component from the style guide. Don't invent new ones — if a section doesn't fit any component, fall back to a `<section>` + `<h2>` + paragraph/bullets.
4. **Render.** Read `templates/cream-light.html` as the skeleton. Fill in the content. Don't drop the `<style>` block — it's required for the self-contained file.
5. **Write the file.** Use the `Write` tool to write to the chosen path.
6. **Ask about opening.** After writing, ask the user: "Open `<path>` in your browser now?" If yes, run `open <path>` via Bash. If no, just confirm the path.

## House style

- **No client-side JS, no external resources.** The HTML must be self-contained — viewable offline, no fonts/CDNs/images fetched at render time.
- **Inline CSS** in a `<style>` block in `<head>`. No `<link rel="stylesheet">`.
- **Preserve the calling skill's content faithfully.** If the terminal report uses MITRE tag IDs like `tactics.ta0005.defense_evasion`, the HTML uses the same. Don't rewrite or rephrase findings during rendering — that's not your job.
- **Severity → border color:**
  - `Critical` → red (`var(--red)`)
  - `High` → red (`var(--red)`)
  - `Medium` → amber (`var(--amber)`)
  - `Low` → olive (`var(--olive)`)
  - `Informational` → teal (`var(--teal)`)
  - Correlation cards → green (`var(--green)`)
  - OOB pack cards → plum (`var(--plum)`)
- **Light mode only.** No dark-mode toggle, no `prefers-color-scheme` block.
- **Light tone of voice.** Don't write headlines or summary text yourself — that came from the calling skill. The only text this skill generates is structural (component class names, footer bylines).

## Layout

```
report-as-html/
├── SKILL.md                      # this file
├── templates/
│   └── cream-light.html          # the canonical skeleton (copy + fill)
└── references/
    ├── style-guide.md            # CSS variables + when to use each color
    └── components.md             # markdown → HTML component mapping
```

## Calling-skill integration

Every report-generating skill (`/posture-report`, `/recommend-detections`, `/triage-alert`, `/threat-hunt`, `/investigate`, `/lookup-ioc`) ends with:

1. Emit the terminal report.
2. Ask: **"Want an HTML version of this report?"**
3. If yes, invoke `/report-as-html` and pass in the report content + a sensible slug.
4. After `/report-as-html` writes the file, it asks: **"Open `<path>` in your browser now?"**
5. If yes, `open <path>`.

The two prompts are intentional. Users may want a saved file without a popup browser window (e.g., they're going to attach it to a ticket), and conversely some users want the browser only without saving. Don't fuse them.
