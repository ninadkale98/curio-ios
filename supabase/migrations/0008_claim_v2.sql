-- Writer v2 selection: claim by modality + strategy, a "fresh = queued today"
-- mode, and a per-source daily-written count for balancing. Plus likes default 0.

-- insert_story: seed likes at 0 (no dummy counts) instead of 1200.
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
    published_at, source_url
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
    story->>'source_url'
  )
  returning id into new_id;

  return new_id;
end;
$$;


-- Drop the 0007 single-arg version so the new 3-arg one (with defaults) isn't
-- ambiguous when called with just p_mode.
drop function if exists public.claim_next_item(text);

-- claim_next_item v2: mode (fresh|backlog) + optional source filter + ordering
-- strategy. Atomic (FOR UPDATE SKIP LOCKED). Returns the claimed row as jsonb,
-- or null if nothing matches.
create or replace function public.claim_next_item(
  p_mode text default 'backlog',
  p_source text default null,
  p_strategy text default 'top'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  claimed public.content_queue;
begin
  update public.content_queue
     set status = 'claimed', claimed_at = now()
   where id = (
     select id from public.content_queue
      where status = 'pending'
        and (p_source is null or source = p_source)
        and (p_mode <> 'fresh' or created_at >= date_trunc('day', now()))
      order by
        case when p_strategy = 'random' then random() end asc,
        case when p_strategy = 'recent' then published_at end desc nulls last,
        rank_score desc,
        created_at desc
      limit 1
      for update skip locked
   )
  returning * into claimed;

  if claimed.id is null then
    return null;
  end if;
  return to_jsonb(claimed);
end;
$$;


-- Today's written (done) count per source — the dispatcher uses this to pick
-- the under-represented modality and to enforce the daily cap.
create or replace function public.written_today_by_source()
returns jsonb
language sql
security definer
set search_path = public
as $$
  select coalesce(jsonb_object_agg(source, n), '{}'::jsonb)
  from (
    select source, count(*) as n
    from public.content_queue
    where status = 'done' and done_at >= date_trunc('day', now())
    group by source
  ) t;
$$;


grant execute on function public.claim_next_item(text, text, text) to anon, authenticated;
grant execute on function public.written_today_by_source() to anon, authenticated;
