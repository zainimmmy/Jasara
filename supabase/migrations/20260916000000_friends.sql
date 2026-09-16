-- Jasara: accounts, friends, blocking and reporting.
--
-- Run once in Supabase → SQL Editor → New query → paste → Run.
--
-- Design: clients may READ their own rows through row level security, but every
-- WRITE goes through a function below. That keeps the rules (no requests to or
-- from blocked users, only the recipient accepts, usernames validated) on the
-- server where a modified app can't skip them.

-- Helpers live in `private`, which the API doesn't expose, so they can be used
-- by policies and triggers without becoming callable endpoints.
create schema if not exists private;
grant usage on schema private to authenticated;

-- ─────────────────────────────────────────────────────────────── Tables

create table public.profiles (
  id                  uuid primary key references auth.users (id) on delete cascade,
  -- Stored as typed; unique and matched case-insensitively via lower().
  username            text not null,
  display_name        text not null default '' check (char_length(display_name) <= 40),
  avatar_emoji        text not null default '🌤️' check (char_length(avatar_emoji) <= 16),
  level               int  not null default 1 check (level between 1 and 365),
  -- Null until the first change, so a typo can be fixed straight after sign-up.
  username_changed_at timestamptz,
  created_at          timestamptz not null default now()
);

create unique index profiles_username_lower on public.profiles (lower(username));

create table public.friendships (
  id           uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.profiles (id) on delete cascade,
  addressee_id uuid not null references public.profiles (id) on delete cascade,
  status       text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at   timestamptz not null default now(),
  responded_at timestamptz,
  check (requester_id <> addressee_id)
);
-- One row per pair, whichever direction the request went.
create unique index friendships_one_per_pair
  on public.friendships (least(requester_id, addressee_id), greatest(requester_id, addressee_id));
create index friendships_addressee on public.friendships (addressee_id);

create table public.blocks (
  blocker_id uuid not null references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);
create index blocks_blocked on public.blocks (blocked_id);

create table public.reports (
  id          uuid primary key default gen_random_uuid(),
  reporter_id uuid references public.profiles (id) on delete set null,
  -- Kept if the reported account is deleted, so moderators still see the history.
  reported_id uuid references public.profiles (id) on delete set null,
  reported_username text not null,
  reason      text not null check (reason in
                ('spam', 'harassment', 'inappropriate_username', 'inappropriate_photo',
                 'impersonation', 'other')),
  details     text check (char_length(details) <= 1000),
  status      text not null default 'open' check (status in ('open', 'reviewed', 'actioned', 'dismissed')),
  created_at  timestamptz not null default now()
);
create index reports_open on public.reports (created_at) where status = 'open';

-- ─────────────────────────────────────────────────────────────── Helpers

-- Returns a reason when a username is unacceptable, or null when it's fine.
create or replace function private.username_problem(name text)
returns text
language plpgsql immutable
set search_path = ''
as $$
declare
  lowered text := lower(coalesce(name, ''));
begin
  if char_length(lowered) < 3 then return 'Usernames are at least 3 characters.'; end if;
  if char_length(lowered) > 20 then return 'Usernames are at most 20 characters.'; end if;
  if lowered !~ '^[a-z0-9_.]+$' then return 'Letters, numbers, underscores and dots only.'; end if;
  if lowered in ('admin', 'administrator', 'support', 'jasara', 'help', 'root',
                 'moderator', 'mod', 'staff', 'official', 'system') then
    return 'That name is reserved.';
  end if;
  -- Deliberately short: this blocks the obvious, reporting handles the rest.
  if lowered ~ '(fuck|shit|bitch|cunt|nigg|rape|nazi|slut|whore|fag)' then
    return 'Pick something else.';
  end if;
  return null;
end;
$$;

create or replace function private.is_blocked_between(a uuid, b uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.blocks
    where (blocker_id = a and blocked_id = b) or (blocker_id = b and blocked_id = a)
  );
$$;

-- Username rules, enforced on every insert and update however the row arrives.
create or replace function private.profiles_before_write()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  problem text;
begin
  if tg_op = 'UPDATE' and new.id <> old.id then
    raise exception 'Profile id cannot change.';
  end if;
  if tg_op = 'INSERT' or new.username is distinct from old.username then
    problem := private.username_problem(new.username);
    if problem is not null then
      raise exception '%', problem using errcode = 'check_violation';
    end if;
  end if;
  if tg_op = 'UPDATE' and lower(new.username) <> lower(old.username) then
    if old.username_changed_at is not null
       and old.username_changed_at > now() - interval '30 days' then
      raise exception 'You can change your username once every 30 days.'
        using errcode = 'check_violation';
    end if;
    new.username_changed_at := now();
  end if;
  if tg_op = 'UPDATE' then
    new.created_at := old.created_at;
  end if;
  return new;
end;
$$;

create trigger profiles_before_write
  before insert or update on public.profiles
  for each row execute function private.profiles_before_write();

-- Email sign-ups pass the username in user metadata, so the profile appears the
-- moment the account does. Sign-ups without one (Sign in with Apple, later)
-- create their profile afterwards with create_profile().
create or replace function private.handle_new_user()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  if new.raw_user_meta_data ? 'username' then
    insert into public.profiles (id, username, display_name)
    values (new.id,
            new.raw_user_meta_data ->> 'username',
            new.raw_user_meta_data ->> 'username');
  end if;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

-- ─────────────────────────────────────────────────────────────── Row level security

alter table public.profiles    enable row level security;
alter table public.friendships enable row level security;
alter table public.blocks      enable row level security;
alter table public.reports     enable row level security;

-- Read: yourself, and anyone you share a friendship row with, unless blocked.
create policy "profiles: read self and connections"
  on public.profiles for select to authenticated
  using (
    id = (select auth.uid())
    or (
      exists (
        select 1 from public.friendships f
        where (f.requester_id = (select auth.uid()) and f.addressee_id = profiles.id)
           or (f.addressee_id = (select auth.uid()) and f.requester_id = profiles.id)
      )
      and not private.is_blocked_between((select auth.uid()), profiles.id)
    )
  );

-- Update: only your own row. The trigger above validates what changes.
create policy "profiles: update self"
  on public.profiles for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

create policy "friendships: read own"
  on public.friendships for select to authenticated
  using ((select auth.uid()) in (requester_id, addressee_id));

create policy "blocks: read own"
  on public.blocks for select to authenticated
  using (blocker_id = (select auth.uid()));

-- Reports are write-only for users; moderators read them from the dashboard.

-- Writes only through the functions below.
revoke insert, update, delete on public.friendships, public.blocks, public.reports
  from anon, authenticated;
revoke insert, delete on public.profiles from anon, authenticated;
revoke all on public.profiles, public.friendships, public.blocks, public.reports from anon;
-- Level, display name and avatar are editable; username goes through the trigger.
revoke update on public.profiles from authenticated;
grant update (username, display_name, avatar_emoji, level) on public.profiles to authenticated;

-- ─────────────────────────────────────────────────────────────── Functions the app calls

-- Live availability check while typing, before an account exists.
create or replace function public.username_available(name text)
returns text
language plpgsql stable security definer
set search_path = ''
as $$
declare
  problem text := private.username_problem(name);
begin
  if problem is not null then return problem; end if;
  if exists (select 1 from public.profiles where lower(username) = lower(name)) then
    return 'That username is taken.';
  end if;
  return null;   -- null means available
end;
$$;

-- For accounts created without a username in their metadata.
create or replace function public.create_profile(name text)
returns public.profiles
language plpgsql security definer
set search_path = ''
as $$
declare
  created public.profiles;
begin
  if auth.uid() is null then raise exception 'Not signed in.'; end if;
  insert into public.profiles (id, username, display_name)
  values (auth.uid(), name, name)
  returning * into created;
  return created;
end;
$$;

-- Exact, case-insensitive username match. No partial search, so nobody can
-- trawl the user list. Blocked pairs don't find each other.
create or replace function public.find_profile(name text)
returns table (id uuid, username text, display_name text, avatar_emoji text, level int)
language sql stable security definer
set search_path = ''
as $$
  select p.id, p.username, p.display_name, p.avatar_emoji, p.level
  from public.profiles p
  where lower(p.username) = lower(trim(name))
    and p.id <> auth.uid()
    and not private.is_blocked_between(auth.uid(), p.id);
$$;

create or replace function public.send_friend_request(target uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  existing public.friendships;
begin
  if me is null then raise exception 'Not signed in.'; end if;
  if target = me then raise exception 'That''s you.'; end if;
  if private.is_blocked_between(me, target) then
    raise exception 'You can''t add this person.';
  end if;

  select * into existing from public.friendships f
  where least(f.requester_id, f.addressee_id) = least(me, target)
    and greatest(f.requester_id, f.addressee_id) = greatest(me, target);

  if found then
    -- They already asked you: sending one back just accepts it.
    if existing.status = 'pending' and existing.addressee_id = me then
      update public.friendships set status = 'accepted', responded_at = now()
      where id = existing.id;
    end if;
    return;
  end if;

  insert into public.friendships (requester_id, addressee_id) values (me, target);
end;
$$;

create or replace function public.respond_to_friend_request(request uuid, accept boolean)
returns void
language plpgsql security definer
set search_path = ''
as $$
begin
  if accept then
    update public.friendships
    set status = 'accepted', responded_at = now()
    where id = request and addressee_id = auth.uid() and status = 'pending';
  else
    delete from public.friendships
    where id = request and addressee_id = auth.uid() and status = 'pending';
  end if;
end;
$$;

-- Unfriend, or cancel a request you sent.
create or replace function public.remove_friendship(other uuid)
returns void
language sql security definer
set search_path = ''
as $$
  delete from public.friendships
  where (requester_id = auth.uid() and addressee_id = other)
     or (addressee_id = auth.uid() and requester_id = other);
$$;

create or replace function public.block_user(target uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or target = auth.uid() then return; end if;
  insert into public.blocks (blocker_id, blocked_id) values (auth.uid(), target)
  on conflict do nothing;
  perform public.remove_friendship(target);
end;
$$;

create or replace function public.unblock_user(target uuid)
returns void
language sql security definer
set search_path = ''
as $$
  delete from public.blocks where blocker_id = auth.uid() and blocked_id = target;
$$;

create or replace function public.report_user(target uuid, reason text, details text default null)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  name text;
begin
  if auth.uid() is null then raise exception 'Not signed in.'; end if;
  select username into name from public.profiles where id = target;
  if name is null then raise exception 'That account no longer exists.'; end if;
  insert into public.reports (reporter_id, reported_id, reported_username, reason, details)
  values (auth.uid(), target, name, reason, nullif(trim(details), ''));
end;
$$;

-- Everything the Friends screen needs in one round trip.
create or replace function public.my_connections()
returns table (
  friendship_id uuid, user_id uuid, username text, display_name text,
  avatar_emoji text, level int, status text, incoming boolean, created_at timestamptz
)
language sql stable security definer
set search_path = ''
as $$
  select f.id, p.id, p.username, p.display_name, p.avatar_emoji, p.level,
         f.status, f.addressee_id = auth.uid(), f.created_at
  from public.friendships f
  join public.profiles p
    on p.id = case when f.requester_id = auth.uid() then f.addressee_id else f.requester_id end
  where auth.uid() in (f.requester_id, f.addressee_id)
  order by f.status, p.username;
$$;

create or replace function public.my_blocks()
returns table (user_id uuid, username text, created_at timestamptz)
language sql stable security definer
set search_path = ''
as $$
  select b.blocked_id, p.username, b.created_at
  from public.blocks b join public.profiles p on p.id = b.blocked_id
  where b.blocker_id = auth.uid()
  order by b.created_at desc;
$$;

-- Apple requires in-app account deletion. Removing the auth user cascades to the
-- profile, friendships and blocks.
create or replace function public.delete_account()
returns void
language plpgsql security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'Not signed in.'; end if;
  delete from auth.users where id = auth.uid();
end;
$$;

-- ─────────────────────────────────────────────────────────────── Who may call what

revoke execute on all functions in schema public from public, anon;
revoke execute on all functions in schema private from public, anon;

grant execute on function public.username_available(text) to anon, authenticated;
grant execute on function
  public.create_profile(text),
  public.find_profile(text),
  public.send_friend_request(uuid),
  public.respond_to_friend_request(uuid, boolean),
  public.remove_friendship(uuid),
  public.block_user(uuid),
  public.unblock_user(uuid),
  public.report_user(uuid, text, text),
  public.my_connections(),
  public.my_blocks(),
  public.delete_account()
to authenticated;

-- Used inside RLS policies and the profile trigger, which run as the caller.
grant execute on function private.is_blocked_between(uuid, uuid) to authenticated;
grant execute on function private.username_problem(text) to authenticated;
grant execute on function private.profiles_before_write() to authenticated;
