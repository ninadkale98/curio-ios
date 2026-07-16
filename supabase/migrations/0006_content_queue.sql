-- Aggregator wing's output: one generic queue table every source scraper
-- writes into. The writer wing (not built yet) drains this FIFO by
-- created_at and turns each row into a Curio blog in `stories`.
create table public.content_queue (
  id           bigint generated always as identity primary key,
  source       text not null check (source in ('github','arxiv','hf','rss','blog','hn','youtube')),
  source_key   text not null,   -- the source's own unique id (github_id, arxiv_id, hn_id, video_id, or url for rss/blog)
  url          text not null,   -- canonical human-facing link
  title        text not null,
  summary      text,            -- native description/abstract from the source
  raw_text     text,            -- richest available full text (README, abstract, post body) — so the writer wing never has to refetch
  raw_json     jsonb not null default '{}'::jsonb,  -- full parsed record (stars, authors, language, channel, etc.)
  image_url    text,
  topic        text,            -- search topic/category/query that surfaced it
  published_at timestamptz,     -- item's own original publish date
  status       text not null default 'pending' check (status in ('pending','claimed','done','skipped','error')),
  claimed_at   timestamptz,
  done_at      timestamptz,
  error        text,
  created_at   timestamptz not null default now()
);

create unique index content_queue_source_key_uidx on public.content_queue (source, source_key);
create index content_queue_pending_fifo_idx on public.content_queue (created_at) where status = 'pending';

alter table public.content_queue enable row level security;
-- No policies: only the service_role connection (GitHub Actions secret) ever touches this table, same defensive posture as `stories`.
