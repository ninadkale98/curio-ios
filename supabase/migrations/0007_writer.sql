-- Writer wing support: a rank_score on the queue + three scoped, anon-callable
-- functions so the writer routines need only the public anon key (no
-- service_role embedded in any routine config).

-- Ranking signal the writer claims by (0-1, computed by the scoring pass).
alter table public.content_queue
  add column if not exists rank_score double precision not null default 0;

create index if not exists content_queue_rank_idx
  on public.content_queue (rank_score desc)
  where status = 'pending';


-- Atomically claim the next item to write. mode='backlog' → highest rank_score;
-- mode='fresh' → newest. FOR UPDATE SKIP LOCKED means concurrent writer routines
-- never grab the same row. Returns the claimed row as jsonb, or null if the
-- queue is empty.
create or replace function public.claim_next_item(p_mode text default 'backlog')
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  claimed public.content_queue;
begin
  if p_mode = 'fresh' then
    update public.content_queue
       set status = 'claimed', claimed_at = now()
     where id = (
       select id from public.content_queue
        where status = 'pending'
        order by created_at desc
        limit 1
        for update skip locked
     )
    returning * into claimed;
  else
    update public.content_queue
       set status = 'claimed', claimed_at = now()
     where id = (
       select id from public.content_queue
        where status = 'pending'
        order by rank_score desc, created_at desc
        limit 1
        for update skip locked
     )
    returning * into claimed;
  end if;

  if claimed.id is null then
    return null;
  end if;
  return to_jsonb(claimed);
end;
$$;


-- Insert a finished blog. Generalized insert_pipeline_story: any https
-- source_url (not just github), dedup on source_url, no 1/hour pacing (the
-- writer is controlled). Required fields enforced so a malformed payload can't
-- create a half-broken card.
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
    coalesce((story->>'likes')::int, 1200),
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


-- Move a queue row through its lifecycle (claimed → done / skipped / error).
create or replace function public.mark_queue_status(
  p_source text, p_source_key text, p_status text, p_error text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.content_queue
     set status  = p_status,
         done_at = case when p_status = 'done' then now() else done_at end,
         error   = p_error
   where source = p_source and source_key = p_source_key;
end;
$$;


grant execute on function public.claim_next_item(text) to anon, authenticated;
grant execute on function public.insert_story(jsonb) to anon, authenticated;
grant execute on function public.mark_queue_status(text, text, text, text) to anon, authenticated;
