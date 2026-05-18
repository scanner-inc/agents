---
name: report-as-html
description: Render a Scanner-style report (terminal markdown + structured data the calling skill already gathered) as a polished, self-contained HTML file ready to open in the browser. Two templates ship — `light-mode` (cream + teal, default for shareable PDFs / printable reports / tickets) and `dark-mode` (Scanner's actual dark-first theme with Inter + Sometype Mono, matches the Scanner app aesthetic). **Not a stand-alone analysis skill — does not generate findings.** Use only as a follow-up step after another skill (`/posture-report`, `/recommend-detections`, `/triage-alert`, `/threat-hunt`, `/investigate`, `/lookup-ioc`) has produced a finished terminal report and the user has answered "yes, render an HTML version." Reads `templates/light-mode.html` or `templates/dark-mode.html` for the skeleton and `references/style-guide.md` + `references/components.md` for the component vocabulary, writes a single self-contained HTML file under `/tmp/`, and (if the user separately says yes) opens it via `open`. Use when the user types `/report-as-html`, says "yes" to a follow-up HTML offer from another report skill, or asks "can you make that an HTML report?"
---

# report-as-html

## When to invoke

Trigger on any of:

- Another report skill has just emitted a finished terminal report and asked the user "Want this as an HTML report?" and the user said yes.
- The user types `/report-as-html`.
- The user says "can you turn that into an HTML report?" or "make me an HTML version".

**Do not** invoke this skill to generate analysis from scratch. It is a renderer, not a generator. The calling skill must have already produced a complete report.

## What it produces

A single self-contained HTML file at `/tmp/<slug>-<YYYY-MM-DD>-<theme>.html` (e.g. `/tmp/posture-report-2026-05-17-light.html`), rendered from one of two templates:

- **`light-mode`** (default — `templates/light-mode.html`): cream background (`#fafaf7`), white panels, dark teal accent (`#1f5d56`). Serif headings (Charter / Iowan Old Style), sans body, mono for code and field paths. Best for shareable PDFs, printable reports, attachments to tickets.
- **`dark-mode`** (`templates/dark-mode.html`): Scanner's actual product theme — near-black background (`#0a0a0a`), slightly elevated panels (`#141414`), Inter for body + headings, Sometype Mono for code/eyebrows/labels, cool-blue accent (`rgb(140,180,255)`). Hairline borders, almost no shadow. Best when the user is reviewing on-screen and wants the report to feel like part of the Scanner app.

Both templates share the same component vocabulary (verdict blocks, stat tiles, top-N cards, severity-coded track lists, coverage matrix, data tables, bullets) — only the `<style>` block differs. The component snippets in `references/components.md` work unchanged in either template.

## Workflow

1. **Confirm scope.** Confirm with the user: which sections from the terminal report should the HTML include? Default is "everything"; offer to trim if the report is very long.
2. **Pick the template.** Default = `light-mode`. Use `dark-mode` if the user asks for "dark mode", "dark theme", "Scanner dark", "match the Scanner app", or the report is being reviewed on-screen rather than shared/printed. When unsure, ask once.
3. **Pick the slug + date + theme suffix.** Default slug = report kind + tenant or topic (e.g. `scanner-recommendations`, `posture-report`, `triage-<alert-id-short>`). Date = today in `YYYY-MM-DD`. Theme suffix = `light` or `dark` (from step 2). Output path = `/tmp/<slug>-<date>-<theme>.html`. The theme suffix is mandatory — it lets a user render the same report in both modes without either overwriting the other.
4. **Map the report to components.** Read `references/components.md`. For each section of the terminal report, pick the matching component from the style guide. Don't invent new ones — if a section doesn't fit any component, fall back to a `<section>` + `<h2>` + paragraph/bullets.
5. **Render.** Read the chosen template (`templates/light-mode.html` or `templates/dark-mode.html`) as the skeleton. Fill in the content. Don't drop the `<style>` block — it's required for the self-contained file.
6. **Write the file.** Use the `Write` tool to write to the chosen path.
7. **Ask about opening.** After writing, ask the user: "Open `<path>` in your browser now?" If yes, run `open <path>` via Bash. If no, just confirm the path.

## House style

- **No client-side JS, no external resources.** The HTML must be self-contained — viewable offline, no fonts/CDNs/images fetched at render time. (Dark mode references Inter and Sometype Mono by name but falls back to system fonts; no `@import url(...)` and no `<link rel="stylesheet">` to Google Fonts.)
- **Inline CSS** in a `<style>` block in `<head>`. No `<link rel="stylesheet">`.
- **Preserve the calling skill's content faithfully.** If the terminal report uses MITRE tag IDs like `tactics.ta0005.defense_evasion`, the HTML uses the same. Don't rewrite or rephrase findings during rendering — that's not your job.
- **Severity → border color (both templates):**
  - `Critical` → red (`var(--red)`)
  - `High` → red (`var(--red)`)
  - `Medium` → amber (`var(--amber)`)
  - `Low` → olive (`var(--olive)`)
  - `Informational` → teal (`var(--teal)`)
  - Correlation cards → green (`var(--green)`)
  - OOB pack cards → plum (`var(--plum)`)
- **No mode toggle, no `prefers-color-scheme` block.** Each file is one mode, baked at render time. If the user wants the other mode, render again — the new file gets the other theme suffix, so the original render stays on disk for side-by-side comparison.
- **Never overwrite the opposite-theme file.** If `/tmp/<slug>-<date>-light.html` already exists and the user now wants dark, write `/tmp/<slug>-<date>-dark.html` next to it — don't touch the light one. If the user explicitly asks for "both", render twice in one turn and confirm both paths.
- **Light tone of voice.** Don't write headlines or summary text yourself — that came from the calling skill. The only text this skill generates is structural (component class names, footer bylines).

## Layout

```
report-as-html/
├── SKILL.md                      # this file
├── templates/
│   ├── light-mode.html           # cream + teal — default, print-friendly
│   └── dark-mode.html            # Scanner dark theme — Inter + Sometype Mono
└── references/
    ├── style-guide.md            # CSS variables + when to use each color (both modes)
    └── components.md             # markdown → HTML component mapping (works in both)
```

## Calling-skill integration

Every report-generating skill that proactively offers HTML (`/posture-report`, `/recommend-detections`, `/triage-alert`, `/threat-hunt`, `/investigate`) ends with the same standardized two-prompt block:

1. Emit the terminal report.
2. Ask, verbatim: **"Want this as an HTML report? *(light theme by default — say "dark" for the Scanner-app theme.)*"**
3. If the user says "yes" / "light" / "sure", invoke `/report-as-html` with `light` theme. If the user says "dark" / "dark mode" / "Scanner dark" / "Scanner theme" / etc., invoke with `dark` theme. If the user says "both", render twice (once each theme).
4. Pass the report content + a sensible slug to `/report-as-html`.
5. After `/report-as-html` writes the file, it asks: **"Open `<path>` in your browser now?"**
6. If yes, `open <path>`.

`/lookup-ioc` is deliberately *reactive* — it doesn't proactively offer HTML (most IOC lookups are quick chat replies); it only renders if the user explicitly asks "make that an HTML report".

The two prompts are intentional. Users may want a saved file without a popup browser window (e.g., they're going to attach it to a ticket), and conversely some users want the browser only without saving. Don't fuse them.

The inline theme hint in the HTML-offer prompt is mandatory. Without it, users don't know dark exists.
