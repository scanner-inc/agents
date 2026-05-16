# Style guide — light-mode & dark-mode report themes

This is the visual vocabulary the `report-as-html` skill uses. Every HTML report follows it. If a calling skill produces content that doesn't fit a documented component, fall back to a plain `<section>` + `<h2>` + paragraph/bullets — don't invent new component classes.

Two templates ship:

- **`light-mode`** (`templates/light-mode.html`) — cream + teal, serif headings. Best for shareable PDFs, printable reports, ticket attachments.
- **`dark-mode`** (`templates/dark-mode.html`) — Scanner's actual product theme. Near-black + cool-blue accent, Inter + Sometype Mono. Best for on-screen review when you want the report to feel like part of the Scanner app.

The two templates share **identical CSS variable names** (`--bg`, `--panel`, `--ink`, `--accent`, `--green`, `--red`, …) and **identical component class names** (`.verdict`, `.stat`, `.track`, `.matrix`, `.cmd`, …). Only the *values* differ. That means the component snippets in `references/components.md` render correctly in either template, unchanged.

## Picking a template

- Default: `light-mode`.
- Use `dark-mode` if the user asks for "dark mode" / "dark theme" / "match the Scanner app" / "Scanner dark", or if the report is being reviewed live in a terminal-adjacent UI and the user wants it to feel native.
- Don't try to support both in one file. There is no toggle, no `prefers-color-scheme` block. Each file is one mode, baked at render time.

## Page chrome — both modes

- Body font: Inter (dark) / system sans (light). Both fall back to system stacks; no `@import url(...)` and no `<link rel="stylesheet">`.
- Mono: Sometype Mono (dark) / SF Mono-Menlo (light). Used for field paths, rule IDs, IP addresses, tag IDs, code, commands.
- Page max-width: 960px. Side padding: 40px desktop. Print-friendly.
- Hairline borders, almost no shadow. Scanner's house style is "borders do the work of elevation."

## Light-mode palette

| CSS var       | Hex      | Use for                                                       |
|---------------|----------|---------------------------------------------------------------|
| `--bg`        | `#fafaf7` | Page background (cream)                                      |
| `--panel`     | `#ffffff` | Card / table / panel fills                                   |
| `--ink`       | `#14171a` | Primary text                                                 |
| `--ink-2`     | `#3b4147` | Secondary text                                               |
| `--ink-3`     | `#6b7177` | Tertiary text / captions                                     |
| `--line`      | `#e6e4dc` | Hairline borders                                             |
| `--line-2`    | `#d2cfc4` | Active / hover borders                                       |
| `--accent`    | `#1f5d56` | Primary teal — section headers, links, numbered-card badges |
| `--green`     | `#2b7a4b` | "All clear" verdicts, correlation cards, healthy coverage    |
| `--amber`     | `#a26418` | "Attention" verdicts, Medium severity, warn stat tiles       |
| `--red`       | `#a32a2a` | "Bad" verdicts, High/Critical severity, bad stat tiles       |
| `--plum`      | `#6b3f7a` | OOB pack cards, MITRE tag pills                              |
| `--teal`      | `#2d6e8f` | Informational severity, regime pills                         |
| `--rust`      | `#b35a3b` | Networking-flow accents in diagrams                          |
| `--olive`     | `#6f7a30` | Low severity, "medium" coverage cells                        |

Headings use a serif stack (Charter / Iowan Old Style / Georgia). Bodies use system sans.

## Dark-mode palette (Scanner product theme)

| CSS var         | Value                       | Use for                                                       |
|-----------------|-----------------------------|---------------------------------------------------------------|
| `--bg`          | `#0a0a0a`                   | Page background — Scanner's `bg-base`                        |
| `--panel`       | `#141414`                   | Card / table / panel fills — Scanner's `bg-elevated`         |
| `--panel-2`     | `#1a1a1a`                   | Code blocks, table header strips                             |
| `--ink`         | `#f7f7f7`                   | Primary text                                                 |
| `--ink-2`       | `#ababab`                   | Secondary text                                               |
| `--ink-3`       | `#6e6e6e`                   | Tertiary text / captions                                     |
| `--line`        | `#1f1f1f`                   | Default hairline borders                                     |
| `--line-2`      | `#383838`                   | Active / hover borders                                       |
| `--accent`      | `rgb(140,180,255)`          | Cool blue — section headers, links, numbered badges          |
| `--accent-soft` | `rgba(140,180,255,0.14)`    | Soft fills behind accent pills / matrix cells                |
| `--green`       | `rgb(102,173,31)`           | Scanner `status-positive`. Correlation cards, healthy cells. |
| `--amber`       | `rgb(220,180,140)`          | Warm tan. Medium severity, "attention" verdicts.             |
| `--red`         | `rgb(247,108,108)`          | Scanner `status-negative`. High/Critical, "bad" verdicts.    |
| `--plum`        | `rgb(200,160,240)`          | OOB pack cards, MITRE tag pills.                             |
| `--teal`        | `rgb(140,180,255)`          | Informational severity, regime pills (same blue as accent).  |
| `--rust`        | `rgb(255,170,110)`          | Networking-flow / pipe accents in diagrams.                  |
| `--olive`       | `rgb(170,210,140)`          | Low severity, "medium" coverage cells.                       |

Headings use Inter (`var(--sans)`) — Scanner does **not** use serif for headings. The `--serif` variable still exists in dark-mode but aliases to `--sans` so the same component CSS (which references `var(--serif)` for stat-tile numerals) renders correctly.

Sources for the dark palette:

- `~/src/tasks/2026_05_May/architecture_review_slides/Architecture Review/colors_and_type.css` — Scanner design system tokens (Figma `11-20-25-Handoff/color`, `/type`).
- `~/src/tasks/2026_05_May/architecture_review_slides/Architecture Review/components.jsx` — accent / severity colors borrowed from the SPL syntax-highlighting palette (`QL_COLORS` map) so they read at the right visual weight on the dark background.

## Soft-fill backgrounds (both modes)

Use these for verdict-block fills, pill backgrounds, coverage-matrix heat cells:

- Light mode: `--green-bg`, `--amber-bg`, `--red-bg`, `--accent-soft` (solid pastels).
- Dark mode: same variable names, but the values are low-opacity overlays of the accent hue (e.g. `rgba(102,173,31,0.14)` for `--green-bg`).

## Component severity → border-color mapping (both modes)

For `<ul class="track">` entry cards:

| Class             | Border         | When to use                              |
|-------------------|----------------|------------------------------------------|
| `sev-critical`    | red            | Critical-severity items                  |
| `sev-high`        | red            | High-severity items                      |
| `sev-medium`      | amber          | Medium-severity items                    |
| `sev-low`         | olive          | Low-severity items                       |
| `sev-info`        | teal           | Informational items, "spot-check" advice |
| `sev-corr`        | green          | Correlation cards                        |
| `sev-pack`        | plum           | OOB pack recommendations                 |

## Verdict variants (both modes)

- `<div class="verdict">` — green (default, "all clear" / "looks normal").
- `<div class="verdict amber">` — amber (attention / housekeeping needed).
- `<div class="verdict red">` — red (active problem / malicious finding).

Pick based on the calling skill's headline. If the headline says "junk + gaps + housekeeping" → amber. If it says "MALICIOUS, evidence of compromise" → red. If it says "Normal admin / SRE activity" → green.

## House-style do/don't

- **Do** preserve the calling skill's content verbatim. Don't rewrite findings.
- **Do** keep MITRE tags as canonical IDs (`tactics.ta0005.defense_evasion`).
- **Do** show numeric counts as large numerals in stat tiles for that "report" feel (serif in light, sans-medium in dark).
- **Don't** add JavaScript. Don't fetch external resources. The file must be portable.
- **Don't** invent emoji or icons the calling skill didn't include.
- **Don't** add a generated-at-timestamp footer different from the calling skill's date.
- **Don't** include "Generated by Claude" or AI-attribution boilerplate.

## Footer

Two-column mono footer:

- Left: skill name (`scanner-soc-skills:posture-report`, `scanner-soc-skills:recommend-detections`, …).
- Right: scope metadata (tenant id, time window, event count).
