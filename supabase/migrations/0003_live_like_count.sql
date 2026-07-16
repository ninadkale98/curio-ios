-- stories.likes was a static seed number; the app now shows real per-user
-- likes on top of it (see 0002_likes_saves.sql), so this trigger keeps it
-- live: baseline seed + real likes, maintained automatically on every
-- insert/delete of the (RLS-locked, per-user-only) `likes` table.
--
-- SECURITY DEFINER because `authenticated` only has SELECT on `stories`
-- (see the "Public read access" policy) — the trigger needs to update it.
create or replace function public.sync_story_like_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if (tg_op = 'INSERT') then
    update public.stories set likes = likes + 1 where id = new.story_id;
    return new;
  elsif (tg_op = 'DELETE') then
    update public.stories set likes = greatest(0, likes - 1) where id = old.story_id;
    return old;
  end if;
  return null;
end;
$$;

drop trigger if exists likes_sync_count on public.likes;
create trigger likes_sync_count
  after insert or delete on public.likes
  for each row execute function public.sync_story_like_count();

-- One-time backfill: fold in likes created during testing, before this
-- trigger existed, so they aren't silently undercounted.
update public.stories s
set likes = s.likes + (
  select count(*) from public.likes l where l.story_id = s.id
)
where exists (select 1 from public.likes l where l.story_id = s.id);
