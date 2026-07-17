# Curio Blog Authoring Spec

Every Curio story is **two independent payloads**. Generate both.

1. **CARD** (the reel) — the teaser card + the double-tap inline expand. Short, punchy, the hook.
2. **READER** (`bodyHTML`) — the full premium article, as semantic HTML. Depth lives here.

They are stored separately and do **not** have to match. The card is a trailer; the reader is the film.

---

## 1. CARD payload (the reel — unchanged design)

Fields per story:

| field | meaning |
|---|---|
| `id` | stable slug |
| `category` | eyebrow, e.g. `SEMICONDUCTOR` |
| `source` | publication, e.g. `Circuit` |
| `mono` | 2-letter badge, e.g. `CI` |
| `author` | byline name |
| `date` | display date, e.g. `Jun 24, 2025` |
| `readTime` | e.g. `6 min` |
| `title` | headline |
| `summary` | 1–2 sentence standfirst shown on the card |
| `imageURL` | hero image (https) |
| `hue` | 0–1 gradient fallback tint |
| `likes` | integer |
| `blocks[]` | the **teaser** shown on the collapsed card **and** the double-tap inline expand |

**`blocks` is a short teaser, NOT the full article.** A good teaser: a `lead` + one or two `paragraph`s, maybe one `quote` or `image`. Block types:

- `lead(text)` – opening standfirst
- `heading(text)`
- `paragraph(text)` – supports inline markdown: `**bold**`, `*italic*`, `[link](url)`
- `quote(text, cite?)`
- `image(url, caption?)`
- `table(head[], rows[][])`
- `diagram(title?, steps[])` – renders as a numbered callout

---

## 2. READER payload — `bodyHTML`

A **fragment** of semantic HTML — the article body only.

**Do NOT include** `<html>`, `<head>`, `<body>`, `<title>`, or a page-level `<style>`. The app wraps your fragment automatically with:
- the Curio **house stylesheet** (dark theme, brand fonts, reading measure),
- the **hero image** (from `imageURL`),
- the **masthead** (category → title → byline).

So do **not** repeat the title, author, or hero — just write the article body.

### Elements the house stylesheet already styles (just write semantic HTML)

```html
<p class="lead">Opening standfirst — larger, brighter.</p>
<p>Body paragraph with <strong>bold</strong>, <em>italic</em>, <a href="…">a link</a>, and inline <code>code</code>.</p>

<h2>Section heading</h2>
<h3>Subsection</h3>

<ul><li>Bulleted item</li></ul>
<ol><li>Numbered item</li></ol>   <!-- markers are accent-colored -->

<blockquote>
  <p>A pulled quote.</p>
  <cite>Name · Source</cite>
</blockquote>

<figure>
  <img src="https://…" alt="">
  <figcaption>Caption in muted italic.</figcaption>
</figure>

<table>
  <thead><tr><th>Chip</th><th>Watts</th></tr></thead>
  <tbody><tr><td>H100</td><td>700 W</td></tr></tbody>
</table>

<pre><code>escaped &lt; &gt; &amp; code block</code></pre>

<hr>

<div class="callout">
  <div class="k">THE BOTTOM LINE</div>
  <p>Boxed takeaway.</p>
</div>
```

### Custom visualizations — the ceiling

For bespoke diagrams, charts, animations, embeds — wrap them in a `.viz` card for a consistent frame:

```html
<div class="viz">
  <svg viewBox="0 0 320 150" width="100%">…</svg>   <!-- static: best, no JS -->
  <div class="cap">CAPTION IN MONO</div>
</div>
```

Also supported inside `.viz` (or anywhere): `<canvas>` + `<script>` (JS runs), `<video>`, animated GIFs, inline `<svg>` with CSS `@keyframes`. Use these for anything the standard elements can't express.

### Palette to match inside custom SVG/canvas/CSS

```
--bg       #08090B      --surface  #101216      --elevated #1A1D23
--text     #F4F5F6      --accent   #6AA0FF      --line     rgba(255,255,255,.09)
fonts: Schibsted Grotesk (display/headlines) · Hanken Grotesk (body)
```

### Rules

- **Fragment only** — no document/`<head>`/page `<style>` wrappers.
- **Dark theme is automatic.** Don't set text colors or page backgrounds; the stylesheet owns them. Only set colors *inside* your custom `.viz` widgets.
- **Escape** `<` `>` `&` inside `<pre><code>`.
- Images/video must be **https** URLs (bundled assets can come later).
- Keep the reader for depth; keep the card `blocks` short.

---

## Reference examples

All 7 live stories (`ReaderContent.*` in `Curio/DetailView.swift`) exercise the
full toolkit and are written **close to their ground-truth source** (see
`CONTENT VOICE` below) — good references for structure:
- **ros** — custom inline-SVG diagram in a `.viz` card, code blocks, a table.
- **okf** — a directory-tree + YAML frontmatter inside `<pre><code>`, `.callout` boxes.
- **openpilot** / **rcclx** — numbered sections, multiple tables, ordered lists.
- **physisforcing** — math/pseudocode blocks, dense benchmark tables.

## Content voice — grounded but engaging

The reader should *enjoy* this and not get bored — but every fact is real.
Engagement comes from **structure, framing, picking the most interesting facts,
and visuals**, never from inventing anything.

**Structure each blog as:**
1. **Hook lead** — open with the single most interesting thing (a surprising
   number, a bold claim the source itself makes, the problem it kills). Not
   "X is a library that…".
2. **Why it matters** — the stakes / what changes, in plain language.
3. **How it works** — the real mechanism, using the source's own concrete
   specifics (numbers, examples, commands, benchmarks).
4. **Notable details** — the 2-3 genuinely interesting facts, not a feature dump.
5. **Bottom line** — a `.callout` closing takeaway.

Scannable `<h2>/<h3>` + short paragraphs; a punchy `blocks` teaser that earns
the swipe; ~500-900 reader words, no padding. **Accuracy is non-negotiable** —
real numbers/quotes only; if unsure, leave it out.

**Reader**: a developer/engineer, reading in an idle moment — wants to be
entertained *and* learn something real, not lectured at. Assume general
engineering baseline, but zero prior knowledge of this specific tool/paper —
explain it from scratch every time.

**Title and headings**: short and plain, no em-dash, no colon-split subtitle —
e.g. `DuckDB Runs SQL Without a Server`, not `DuckDB — An In-Process SQL
Database Built for Analytics, Not Servers`. No em-dashes anywhere in the piece
(title, headings, or body prose) — use periods, commas, colons instead.

**Depth without density**: go genuinely deep on the real mechanism, but never
let it read dense. Simple English, short sentences, one idea per sentence.
Layer it: plain explanation first, then the deeper mechanism built on top, so
a reader who's tired can still follow without re-reading a paragraph.

### Visuals are required — generate inline SVG

Every blog must carry visuals that make it easier to understand. **Generate
them as inline `<svg>`** (no image hunting, always renders) — do not rely on
finding real images.
- **1-3 inline-SVG `.viz` cards per blog**: a concept diagram, an
  architecture/data-flow diagram, a comparison bar chart, a before/after, a
  pipeline. Whatever actually clarifies the piece.
- Also use `<table>` for comparisons and `<pre><code>` where the source has
  real code/commands.
- Match the house palette inside SVG (`--bg #08090B`, `--surface #101216`,
  `--elevated #1A1D23`, `--text #F4F5F6`, `--accent #6AA0FF`,
  `--line rgba(255,255,255,.09)`); label each with a `.cap` in mono caps.
- **Hero (`imageURL`)**: use the best real source image (github social-preview
  `opengraph.githubassets.com/1/{owner}/{repo}`, HF paper thumbnail, article
  `og:image`); if there's none, any https image is fine — the app falls back to
  the `hue` gradient if it fails to load.

## Dev wiring (how the two payloads reach the app)

- **Live app:** fetches both payloads from Supabase (`NewsService.swift` →
  `SupabaseNewsService`) — see `ADD_BLOG_TO_SUPABASE.md` for how to add a row.
- Card payload → `Story` fields + `blocks`.
- Reader payload → `Story.bodyHTML: String?`. If `nil`, the reader auto-derives HTML from `blocks` (so a story always renders).
- Assembly happens in `ReaderHTML.page(for:)`: house CSS + hero + masthead + your `bodyHTML`, loaded in a `WKWebView`.
- `Curio/SampleData.swift` + `ReaderContent` in `DetailView.swift` are the local fallback (used by `MockNewsService` and #Previews) — keep them in sync with the DB when content changes.
