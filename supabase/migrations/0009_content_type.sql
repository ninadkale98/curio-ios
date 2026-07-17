-- The client has no way to know whether a story came from a GitHub repo, an
-- arXiv paper, an RSS/blog article, or Hacker News — content_queue.source
-- (which already carries this) is dropped once the writer publishes into
-- stories. Add a column so the card can show a per-type icon and the reader
-- can show type-specific actions (Open in GitHub, etc).
alter table public.stories
  add column if not exists content_type text
    check (content_type is null or content_type in ('github', 'arxiv', 'rss', 'blog', 'hn'));

-- Backfill existing rows from source_url, best-effort. Rows with no
-- source_url (the original 7 hand-written stories) are left null.
update public.stories
   set content_type = 'github'
 where content_type is null and source_url like '%github.com%';

update public.stories
   set content_type = 'arxiv'
 where content_type is null and source_url like '%arxiv.org%';

-- Everything else with a source_url but not github/arxiv came in through the
-- rss/blog/hn channels, which all look like generic article URLs and can't be
-- told apart after the fact — default the remainder to 'blog' as the closest
-- generic bucket.
update public.stories
   set content_type = 'blog'
 where content_type is null and source_url is not null;

-- insert_story now accepts and stores content_type (nullable — omit for
-- hand-written stories or anything that doesn't fit the five known types).
create or replace function public.insert_story(story jsonb)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id text;
begin
  if story->>'source_url' is null or story->>'source_url' !~ '^https://' then
    raise exception 'source_url must be an https URL';
  end if;
  if exists (select 1 from public.stories where source_url = story->>'source_url') then
    raise exception 'source_url already covered: %', story->>'source_url';
  end if;
  if coalesce(story->>'id', '') = '' or coalesce(story->>'title', '') = ''
     or coalesce(story->>'body_html', '') = '' or coalesce(story->>'image_url', '') = '' then
    raise exception 'id, title, body_html, image_url are required';
  end if;

  insert into public.stories (
    id, category, source, mono, author, date, read_time, title, summary,
    image_url, likes, hue, chat_intro, blocks, prompts, body_html,
    published_at, source_url, content_type
  )
  values (
    story->>'id',
    coalesce(story->>'category', ''), coalesce(story->>'source', ''),
    coalesce(story->>'mono', ''), coalesce(story->>'author', ''),
    coalesce(story->>'date', ''), coalesce(story->>'read_time', ''),
    story->>'title', coalesce(story->>'summary', ''), story->>'image_url',
    coalesce((story->>'likes')::int, 0),
    coalesce((story->>'hue')::double precision, 0.5),
    coalesce(story->>'chat_intro', ''),
    coalesce(story->'blocks', '[]'::jsonb),
    coalesce(story->'prompts', '[]'::jsonb),
    story->>'body_html',
    coalesce((story->>'published_at')::timestamptz, now()),
    story->>'source_url',
    story->>'content_type'
  )
  returning id into new_id;

  return new_id;
end;
$$;
