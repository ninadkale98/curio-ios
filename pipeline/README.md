# Curio content pipeline — aggregator wing

Two independent wings, tuned on separate cadences:

- **Aggregator** (this folder): fetches raw candidates from each source,
  dedups, and inserts them into `content_queue` as `pending`. Zero LLM
  judgment — plain deterministic scripts. Runs via GitHub Actions cron.
- **Writer** (not built yet): drains `content_queue` FIFO, does the
  editorial write (restructure into a Curio blog per `CURIO_BLOG_SPEC.md`),
  inserts into `stories`, marks the row `done`.

Currently scoped to **GitHub only** — the other sources (arxiv, hf, rss,
blog, hn, youtube) follow the same `sources/<name>.py` → `QueueItem` →
`db.upsert()` pattern once this one is proven end-to-end.

## Setup

```bash
cd pipeline
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env   # fill in SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY
```

`SUPABASE_SERVICE_ROLE_KEY` is required because `content_queue` has RLS
enabled with no policies (same defensive posture as `stories`) — only a
service-role write can touch it. Get it fresh via:
`supabase projects api-keys --project-ref mixkzotcnwvkdvlxhobe` (never
commit it — `.env` is gitignored).

## Running

```bash
# One-time, deep historical pull (see aggregator/sources/github.py for what
# "deep" means per source — for GitHub it's more pages per topic, sorted by
# stars, since stars already surface old-but-great repos).
python -m aggregator.run --backfill --only github

# Steady-state: what the GitHub Actions cron actually runs.
python -m aggregator.run --only github

# Re-run either mode again immediately to sanity-check dedup: row count in
# content_queue must not increase.
```

## Dedup model

Every row's identity is `(source, source_key)` — for GitHub, `source_key`
is the repo's numeric `github_id` (stable even across renames). Re-running
an already-queued item refreshes volatile fields (stars, description) via
a merge-upsert but never touches `status`/`claimed_at`/`done_at` — so a
re-crawl can't accidentally un-claim or un-finish something the writer wing
already picked up.
