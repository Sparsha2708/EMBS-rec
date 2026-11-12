-- =====================================================================
-- redstone_rx : Supabase schema
-- Run once in: Supabase Dashboard > SQL Editor > New query > Run
-- Safe to re-run (idempotent).
-- =====================================================================

-- ---------- 1. Admins (organizers) ----------
create table if not exists public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.admins enable row level security;

-- security definer so policies can check admin status without recursion
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.admins where user_id = auth.uid());
$$;

-- An admin may see the admin list; nobody can write it from the client.
drop policy if exists "admins read own row" on public.admins;
create policy "admins read own row" on public.admins
  for select to authenticated using (user_id = auth.uid());

-- ---------- 2. Registrations ----------
create table if not exists public.registrations (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null unique references auth.users(id) on delete cascade,
  email       text not null,
  team_name   text not null,
  leader_name text not null,
  phone       text not null,
  college     text not null,
  team_size   int  not null,
  members     text not null default '',
  member_list jsonb not null default '[]'::jsonb,
  track       text not null,
  abstract    text not null default '',
  agreed      boolean not null default false,
  status      text not null default 'pending',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  constraint reg_team_size_ck  check (team_size between 1 and 4),
  constraint reg_team_name_ck  check (team_name ~ '^[A-Za-z0-9_ .''-]{3,30}$'),
  constraint reg_phone_ck      check (phone ~ '^\+?\d[\d ]{8,13}$'),
  constraint reg_track_ck      check (length(btrim(track)) > 0),
  constraint reg_agreed_ck     check (agreed is true),
  constraint reg_abstract_ck   check (length(abstract) <= 2000),
  constraint reg_status_ck     check (status in ('pending','approved','rejected','waitlisted'))
);

-- If a `registrations` table already existed (older version), the CREATE above was skipped.
-- Add any missing columns so the app's inserts and upserts work.
alter table public.registrations
  add column if not exists email       text        not null default '',
  add column if not exists team_name   text        not null default '',
  add column if not exists leader_name text        not null default '',
  add column if not exists phone       text        not null default '',
  add column if not exists college     text        not null default '',
  add column if not exists team_size   int         not null default 1,
  add column if not exists members     text        not null default '',
  add column if not exists member_list jsonb       not null default '[]'::jsonb,
  add column if not exists track       text        not null default '',
  add column if not exists abstract    text        not null default '',
  add column if not exists agreed      boolean     not null default false,
  add column if not exists status      text        not null default 'pending',
  add column if not exists created_at  timestamptz not null default now(),
  add column if not exists updated_at  timestamptz not null default now();

-- The app upserts on user_id, which needs a unique index
create unique index if not exists registrations_user_id_uq on public.registrations (user_id);

-- Team names must be unique, ignoring case and surrounding spaces
create unique index if not exists registrations_team_name_uq
  on public.registrations (lower(btrim(team_name)));

create index if not exists registrations_status_idx on public.registrations (status);
create index if not exists registrations_track_idx  on public.registrations (track);

-- ---------- 3. Guard trigger ----------
-- Non-admins can never choose or change `status`, `user_id`, or `email`.
create or replace function public.registrations_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  admin boolean := public.is_admin();
begin
  if tg_op = 'INSERT' then
    if not admin then
      new.status := 'pending';
      new.email  := coalesce(auth.jwt() ->> 'email', new.email);
    end if;
  else
    if not admin then
      new.status  := old.status;
      new.user_id := old.user_id;
      new.email   := old.email;
    end if;
    new.updated_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists registrations_guard_trg on public.registrations;
create trigger registrations_guard_trg
  before insert or update on public.registrations
  for each row execute function public.registrations_guard();

-- ---------- 4. Row Level Security ----------
alter table public.registrations enable row level security;

-- Participants: read their own application
drop policy if exists "own select" on public.registrations;
create policy "own select" on public.registrations
  for select to authenticated
  using (user_id = auth.uid());

-- Participants: create exactly one application for themselves
drop policy if exists "own insert" on public.registrations;
create policy "own insert" on public.registrations
  for insert to authenticated
  with check (user_id = auth.uid());

-- Participants: edit their own application only while it is still pending
drop policy if exists "own update while pending" on public.registrations;
create policy "own update while pending" on public.registrations
  for update to authenticated
  using      (user_id = auth.uid() and status = 'pending')
  with check (user_id = auth.uid());

-- Organizers: full read + update (approve / reject / waitlist)
drop policy if exists "admin select all" on public.registrations;
create policy "admin select all" on public.registrations
  for select to authenticated using (public.is_admin());

drop policy if exists "admin update all" on public.registrations;
create policy "admin update all" on public.registrations
  for update to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "admin delete" on public.registrations;
create policy "admin delete" on public.registrations
  for delete to authenticated using (public.is_admin());

-- ---------- 5. Privileges ----------
revoke all on public.registrations from anon;
revoke all on public.admins        from anon, authenticated;
grant select, insert, update, delete on public.registrations to authenticated;
grant select on public.admins to authenticated;

-- =====================================================================
-- 6. MAKE YOURSELF AN ORGANIZER
--    First sign up on the site with your email, then run (edit the email):
--
--    insert into public.admins (user_id)
--    select id from auth.users where email = 'you@example.com'
--    on conflict do nothing;
-- =====================================================================

-- Make the API pick up new/changed columns immediately
notify pgrst, 'reload schema';
