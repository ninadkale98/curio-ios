-- Dedup key for the automated content pipeline: has this specific source
-- (e.g. a GitHub repo) already been turned into a Curio blog? Nullable since
-- the 7 hand-written stories have no single canonical source URL.
alter table public.stories
  add column if not exists source_url text;

create unique index if not exists stories_source_url_key
  on public.stories (source_url)
  where source_url is not null;
