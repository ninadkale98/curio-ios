-- Curio stories table: one row per blog. Two independent payloads per story,
-- matching the app's design: `blocks` (reel card teaser + double-tap expand)
-- and `body_html` (full house-styled reader article).
create table if not exists public.stories (
  id            text primary key,
  category      text not null,
  source        text not null,
  mono          text not null,
  author        text not null,
  date          text not null,
  read_time     text not null,
  title         text not null,
  summary       text not null,
  image_url     text not null,
  likes         integer not null default 0,
  hue           double precision not null default 0.5,
  chat_intro    text not null default '',
  blocks        jsonb not null default '[]'::jsonb,
  prompts       jsonb not null default '[]'::jsonb,
  body_html     text,
  published_at  timestamptz not null default now(),
  created_at    timestamptz not null default now()
);

-- Sort key for the future Today / Explore (infinite) feed split + keyset pagination.
create index if not exists stories_published_at_idx
  on public.stories (published_at desc, id desc);

-- Public, read-only via the anon key. Inserts/updates/deletes require the
-- service_role key (used only from local admin scripts / the dashboard —
-- never shipped in the app).
alter table public.stories enable row level security;

create policy "Public read access"
  on public.stories
  for select
  to anon, authenticated
  using (true);
