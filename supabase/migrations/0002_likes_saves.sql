-- Real, per-user likes and saves — one row per (user, story). RLS scopes
-- every read/write to the signed-in user via auth.uid(); the app writes
-- with the user's own access token, never the anon key or service_role.
create table if not exists public.likes (
  user_id    uuid not null references auth.users(id) on delete cascade,
  story_id   text not null references public.stories(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, story_id)
);

alter table public.likes enable row level security;

create policy "Users manage their own likes"
  on public.likes
  for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create table if not exists public.saves (
  user_id    uuid not null references auth.users(id) on delete cascade,
  story_id   text not null references public.stories(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, story_id)
);

alter table public.saves enable row level security;

create policy "Users manage their own saves"
  on public.saves
  for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
