-- Write path for the automated content pipeline (a cloud-scheduled routine
-- with no access to service_role). Rather than handing that routine a
-- god-mode credential, expose exactly one narrow capability: insert a single
-- GitHub-sourced story, with its own validation, callable with the anon key
-- that's already public (shipped in the app, already documented as safe to
-- reference in ADD_BLOG_TO_SUPABASE.md). No new secret to protect.
create or replace function public.insert_pipeline_story(story jsonb)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id text;
begin
  if story->>'source_url' is null or story->>'source_url' !~ '^https://github\.com/[^/]+/[^/]+$' then
    raise exception 'source_url must look like https://github.com/{owner}/{repo}';
  end if;

  if exists (select 1 from public.stories where source_url = story->>'source_url') then
    raise exception 'source_url already covered: %', story->>'source_url';
  end if;

  if coalesce(story->>'id', '') = '' or coalesce(story->>'title', '') = ''
     or coalesce(story->>'body_html', '') = '' then
    raise exception 'id, title, and body_html are required';
  end if;

  -- Basic pacing guard: at most one pipeline-inserted story per hour, so a
  -- misbehaving or replayed call can't flood the feed.
  if exists (
    select 1 from public.stories
    where source_url is not null
      and created_at > now() - interval '1 hour'
  ) then
    raise exception 'a pipeline story was already inserted in the last hour';
  end if;

  insert into public.stories (
    id, category, source, mono, author, date, read_time, title, summary,
    image_url, likes, hue, chat_intro, blocks, prompts, body_html,
    published_at, source_url
  )
  values (
    story->>'id', story->>'category', story->>'source', story->>'mono',
    story->>'author', story->>'date', story->>'read_time', story->>'title',
    story->>'summary', story->>'image_url',
    coalesce((story->>'likes')::int, 1000),
    coalesce((story->>'hue')::double precision, 0.5),
    coalesce(story->>'chat_intro', ''),
    coalesce(story->'blocks', '[]'::jsonb),
    coalesce(story->'prompts', '[]'::jsonb),
    story->>'body_html',
    coalesce((story->>'published_at')::timestamptz, now()),
    story->>'source_url'
  )
  returning id into new_id;

  return new_id;
end;
$$;

-- Only this function can write stories with the anon key — there is still no
-- direct INSERT/UPDATE/DELETE grant on the table itself for anon/authenticated.
grant execute on function public.insert_pipeline_story(jsonb) to anon, authenticated;
