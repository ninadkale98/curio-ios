# Curio content pipeline

A two-wing system that keeps Curio's feed growing without manual authoring.

- **Aggregator wing** (this folder, built): fetches candidates from many sources,
  dedups them, and writes them into a Supabase `content_queue` table as
  `pending`. Deterministic, no LLM. Runs daily via GitHub Actions.
- **Writer wing** (not built yet): drains `content_queue` FIFO / by signal, does
  the editorial write (restructure into a Curio blog per
  `../CURIO_BLOG_SPEC.md`), inserts into `stories`, marks the row `done`.

The two wings are independent so their cadences tune separately.

## Channels (all live)

Each channel is a `sources/<name>.py` module exposing a generator with the same
contract, wired into `run.py`'s `SOURCES` dict. Every item is **metadata-only** —
the aggregator never downloads the full artifact (README / PDF / article body);
the writer wing fetches that at write time and does quality judgment then.

| source | dedup key (`source_key`) | ranking signal (`raw_json`) | notes |
|---|---|---|---|
| `github` | numeric repo id | `stars_per_day` | ~40 topics × {all-time stars, <6mo breakouts} |
| `arxiv` | `arxiv_id` | `upvotes` (HF) / `citations_per_month` (S2) | HF Daily curated + Semantic Scholar citation search, merged by arxiv_id |
| `rss` | article URL | source authority + recency | 22 hand-picked feeds; no engagement signal exists |
| `blog` | article URL | source authority + recency | Framer search-index sites (Perplexity Research) |
| `hn` | HN objectID | `score` (points) + comments | Algolia search; the linked article is the content |

## `content_queue` schema

`supabase/migrations/0006_content_queue.sql`. Generic, source-agnostic:
`source`, `source_key` (unique together), `url`, `title`, `summary`, `raw_text`,
`raw_json` (per-source signal + metadata), `image_url`, `topic`, `published_at`,
`status` (pending/claimed/done/skipped/error), timestamps. RLS on, no policies →
only the service-role connection writes it.

## Dedup — three layers, per channel

1. **In-run `seen` set** — the same item surfaced by two queries in one run is
   collected once.
2. **DB unique index** on `(source, source_key)` — the hard guarantee across runs
   (upsert merges, never duplicates). This is the real safety net.
3. **Cross-check vs published `stories.source_url`** — never re-queue something
   already live in the app.

The `existing_keys()` pre-filter is **paginated** (PostgREST caps a single GET at
1000 rows — a naive fetch silently truncates and makes runs re-process
everything; see `db._paginate`).

## Running

```bash
cd pipeline
python3.13 -m venv .venv && source .venv/bin/activate   # note: py3.14 venv is broken on this box
pip install -r requirements.txt
cp .env.example .env    # fill SUPABASE_SERVICE_ROLE_KEY (+ optional GITHUB_TOKEN, SEMANTIC_SCHOLAR_KEY)

# One-time deep pull per channel:
python -m aggregator.run --backfill --only github
python -m aggregator.run --backfill --only arxiv
python -m aggregator.run --only rss --only blog     # (feeds have no historical depth)
python -m aggregator.run --backfill --only hn

# Steady-state (what the daily cron runs — all channels, incremental):
python -m aggregator.run
```

`--backfill` = deep one-time pull; default = incremental skim. `--resume`
continues a crashed backfill (per-topic checkpoint in `state/`). Each run mirrors
results to `state/<source>.jsonl` for inspection and upserts to the DB.

## How to add a new channel (the pattern)

1. Create `sources/<name>.py` with a generator:
   `iter_...(backfill, existing_keys, existing_story_urls, done_topics)` that
   `yield`s `(unit_name, [QueueItem])` per unit (topic / feed / query). Build
   each `QueueItem` (`queue_item.py`) from data the source gives for free — no
   per-item deep fetches. Put the channel's quality signal in `raw_json`.
2. Add it to `SOURCES` in `run.py` (`"<name>": <module>.iter_...`).
3. If it needs a new `source` value, extend the check constraint in a migration
   (existing values: github, arxiv, hf, rss, blog, hn, youtube).
4. Test one unit live, run the backfill, then re-run and confirm **0 new**
   (proves dedup). Regenerate the JSONL from the DB if you deleted rows.

## Automation

- **GitHub Actions** (`.github/workflows/aggregator.yml`) runs the incremental
  pull daily and sends a Pushover summary of what was added. Secrets:
  `SUPABASE_SERVICE_ROLE_KEY`, `SEMANTIC_SCHOLAR_KEY` (optional),
  `PUSHOVER_TOKEN`, `PUSHOVER_USER`.
- **launchd watchdog** (`ops/`) checks the latest Action run daily and
  Pushover-notifies (and re-triggers) on failure or a missed run.

## Cadence notes / open refinements

- HF Daily updates daily (fresh); Semantic Scholar citations move slowly
  (~weekly, months-scale) — so the S2 path could run less often than daily.
  Currently the daily cron runs everything; splitting cadence is a future tweak.
- Citations grow over time — a future refinement re-scores `citations_per_month`
  on already-queued papers each run so late bloomers climb the ranking.
- YouTube channel is designed-for but not built (needs a Google Data API v3 key).
