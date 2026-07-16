# Adding a blog to Curio (Supabase)

Self-contained instructions for adding one new blog to the live Curio app.
The app (Curio/NewsService.swift → `SupabaseNewsService`) fetches the feed
live from this database — **adding a row here is all it takes**. No app
rebuild or TestFlight upload is needed for content changes.

## Content rules — read this first

The goal: **the reader should enjoy this and not get bored — but every fact is
real.** Full voice + structure in `CURIO_BLOG_SPEC.md` ("Content voice —
grounded but engaging"). In short:

- **Grounded but engaging.** Shape a compelling read — a hook lead, a clear
  "why it matters", plain-language explanation, a bottom-line callout — but the
  engagement comes from *framing and picking the best facts*, never from
  inventing numbers, quotes, or claims. Accuracy is non-negotiable.
- Use the source's own headline as the `title` (verbatim/near-verbatim, no
  clickbait). Keep the source's real examples, numbers, and quotes.
- **Visuals required:** generate **1-3 inline `<svg>` `.viz` diagrams** per blog
  (concept/flow/comparison) so it's easy to understand — don't rely on finding
  images. Plus tables for comparisons and code blocks where the source has code.
- Don't sprinkle em-dashes ("—") as a tic. Prefer periods, commas, colons.
- ~500-900 reader words, scannable headings, short paragraphs.

## The two payloads

Every story is **two independent pieces of content**, stored in one DB row:

1. **`blocks`** (jsonb) — the reel card's teaser + the double-tap inline
   expand. Short: a `lead` + 1–2 `paragraph`s, maybe one `quote` or
   `heading`. This is a trailer, not the article.
2. **`body_html`** (text) — the full reader article, as an HTML **fragment**
   (no `<html>`/`<head>`/`<body>`, no page-level `<style>` — the app supplies
   the hero image, masthead, and house stylesheet automatically around it).

## Project details

- Project name: **Curio**, ref `mixkzotcnwvkdvlxhobe`
- REST base URL: `https://mixkzotcnwvkdvlxhobe.supabase.co/rest/v1/stories`
- The **anon** key (safe to reference, it's already public in the shipped app
  and in `Curio/NewsService.swift`) is read-only — Row Level Security allows
  SELECT only. Writing requires the **service_role** key, which is never
  shipped in the app or committed to git.

### Getting the service_role key

```bash
# One-time: authenticate the Supabase CLI (needs a personal access token,
# generate one at https://supabase.com/dashboard/account/tokens)
supabase login --token sbp_xxxxxxxxxxxxxxxxxxxxx

# Fetch the keys
supabase projects api-keys --project-ref mixkzotcnwvkdvlxhobe
```

Use the `service_role` value from that output for the insert below. **Never**
paste it into a committed file, a script that gets checked in, or hand it to
anyone outside this workflow.

## Table schema (`public.stories`)

| column | type | meaning |
|---|---|---|
| `id` | text, primary key | stable slug, e.g. `some-blog-slug` |
| `category` | text | eyebrow shown on the card, e.g. `ROBOTICS` |
| `source` | text | publication name shown on the card |
| `mono` | text | 2-letter badge shown in a chip (card + byline) |
| `author` | text | byline name |
| `date` | text | display date, e.g. `Jun 26, 2026` |
| `read_time` | text | e.g. `5 min` |
| `title` | text | **the source's own headline** |
| `summary` | text | 1–2 sentence standfirst for the card |
| `image_url` | text | hero image URL (https) |
| `likes` | integer | starting like count |
| `hue` | double | 0–1, gradient fallback tint if the image fails to load |
| `chat_intro` | text | one-line internal framing (currently unused by any UI — fill with a short one-line summary) |
| `blocks` | jsonb | array of card teaser blocks (see below) |
| `prompts` | jsonb | array of `{question, answer}` — currently unused, pass `[]` |
| `body_html` | text | the full reader HTML fragment |
| `published_at` | timestamptz | sort key for the feed — set to a real, distinct timestamp (not `now()` for a batch of several rows, or they'll tie and order will be unstable) |

### `blocks` JSON shape

```json
[
  {"type": "lead", "text": "..."},
  {"type": "paragraph", "text": "... supports **bold**, *italic*, [link](url) ..."},
  {"type": "heading", "text": "..."},
  {"type": "quote", "text": "...", "cite": "Attribution or null"},
  {"type": "image", "url": "https://...", "caption": "or null"},
  {"type": "table", "head": ["Col A", "Col B"], "rows": [["a1", "b1"]]},
  {"type": "diagram", "title": "or null", "steps": ["step one", "step two"]}
]
```

## HTML toolkit for `body_html`

Write clean semantic HTML. The house stylesheet (dark theme, Curio's bundled
fonts) styles all of this automatically:

```html
<p class="lead">Opening standfirst — larger, brighter text.</p>
<p>Body paragraph with <strong>bold</strong>, <em>italic</em>, a <a href="#">link</a>, inline <code>code</code>.</p>

<h2>Section heading</h2>
<h3>Subsection</h3>

<ul><li>Bulleted item</li></ul>
<ol><li>Numbered item</li></ol>

<blockquote>
  <p>A pulled quote.</p>
  <cite>Name, Source</cite>
</blockquote>

<figure>
  <img src="https://..." alt="">
  <figcaption>Caption in muted italic.</figcaption>
</figure>

<table>
  <thead><tr><th>Col</th><th>Col</th></tr></thead>
  <tbody><tr><td>...</td><td>...</td></tr></tbody>
</table>

<pre><code>escaped &lt; &gt; &amp; code block</code></pre>

<div class="callout">
  <div class="k">LABEL IN CAPS</div>
  <p>Boxed takeaway or key point.</p>
</div>
```

For custom diagrams/visualizations, wrap inline SVG (preferred — no JS, always
renders) or `<canvas>`/`<script>` in a `.viz` card:

```html
<div class="viz">
  <svg viewBox="0 0 320 150" width="100%">...</svg>
  <div class="cap">CAPTION IN MONO, UPPERCASE</div>
</div>
```

Palette to match inside custom SVG/canvas: `--bg:#08090B` `--surface:#101216`
`--elevated:#1A1D23` `--text:#F4F5F6` `--accent:#6AA0FF`
`--line:rgba(255,255,255,.09)`.

**Rules for `body_html`:** fragment only (no document/head/body/style
wrapper) · dark theme is automatic, don't set page-level colors · escape
`<` `>` `&` inside `<pre><code>` · images/video must be https URLs.

## How to insert the row

Two options — pick whichever is available.

### Option A — Supabase Studio (simplest, no keys needed)

Dashboard → Table Editor → `stories` → Insert row. Paste `blocks` and
`prompts` as JSON directly into their columns; paste `body_html` into its
text column.

### Option B — REST API with the service_role key (scriptable)

```bash
SERVICE_KEY="<paste from `supabase projects api-keys`>"

curl -s -X POST "https://mixkzotcnwvkdvlxhobe.supabase.co/rest/v1/stories" \
  -H "apikey: $SERVICE_KEY" \
  -H "Authorization: Bearer $SERVICE_KEY" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=minimal" \
  --data '{
    "id": "some-blog-slug",
    "category": "ROBOTICS",
    "source": "Example",
    "mono": "EX",
    "author": "Author Name",
    "date": "Jul 1, 2026",
    "read_time": "5 min",
    "title": "The source'"'"'s own headline",
    "summary": "1-2 sentence standfirst.",
    "image_url": "https://images.unsplash.com/photo-...",
    "likes": 1000,
    "hue": 0.5,
    "chat_intro": "One-line summary.",
    "blocks": [{"type":"lead","text":"..."}],
    "prompts": [],
    "body_html": "<p class=\"lead\">...</p>",
    "published_at": "2026-07-01T09:00:00Z"
  }'
```

Expect `HTTP 201`. To update an existing row instead of inserting, use
`PATCH` with a `?id=eq.<slug>` query filter on the same URL.

### Verify

```bash
ANON_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1peGt6b3Rjbnd2a2R2bHhob2JlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI4NzI0ODYsImV4cCI6MjA5ODQ0ODQ4Nn0.3ALwtoucsBj976IN02l4bvkHz2Vaog6fVQaPvxHDVOE"
curl -s "https://mixkzotcnwvkdvlxhobe.supabase.co/rest/v1/stories?id=eq.some-blog-slug&select=id,title" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $ANON_KEY"
```

That's it — no app rebuild needed. The new blog appears next time the app
launches (or relaunches), ordered by `published_at`.
