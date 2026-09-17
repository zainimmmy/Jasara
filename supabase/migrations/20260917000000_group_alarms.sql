-- Jasara: group alarms, check-ins, group streaks and wake photos.
-- Requires 20260916000000_friends.sql. Run it the same way, after that one.
--
-- How a group alarm works:
--   * The creator sets a time, the days (or one date), and a cutoff.
--   * Every member picks their own challenge and flips their own on/off toggle.
--   * Toggles lock at the cutoff the night before (default 21:00): a change after
--     that only applies from the following occurrence, so nobody switches off an
--     alarm at 6am to protect a streak.
--   * Times are local to each member. "6:30" means 6:30 wherever you are.
--   * Each phone schedules the alarm itself, so it rings offline. Check-ins are
--     sent when there's a connection and judged against server-computed times.
--   * A day counts for the group streak when everyone who was in woke on time.

-- ─────────────────────────────────────────────────────────────── Tables

create table public.alarm_groups (
  id              uuid primary key default gen_random_uuid(),
  creator_id      uuid not null references public.profiles (id) on delete cascade,
  label           text not null check (char_length(trim(label)) between 1 and 40),
  hour            int  not null check (hour between 0 and 23),
  minute          int  not null check (minute between 0 and 59),
  -- Bit per weekday, bit 0 = Sunday. Zero when the alarm is a one-off on `once_on`.
  weekdays_mask   int  not null default 0 check (weekdays_mask between 0 and 127),
  once_on         date,
  -- Minutes past midnight on the day before each occurrence.
  cutoff_minutes  int  not null default 1260 check (cutoff_minutes between 0 and 1439),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  check ((weekdays_mask > 0) <> (once_on is not null))
);

create table public.alarm_group_members (
  group_id            uuid not null references public.alarm_groups (id) on delete cascade,
  user_id             uuid not null references public.profiles (id) on delete cascade,
  status              text not null default 'invited' check (status in ('invited', 'joined')),
  invited_by          uuid references public.profiles (id) on delete set null,
  -- The member's current choice…
  is_on               boolean not null default true,
  -- …which applies from this occurrence date. Earlier occurrences use previous_is_on.
  toggle_effective_on date,
  previous_is_on      boolean not null default false,
  challenge           text not null default 'math'
                        check (challenge in ('math', 'shake', 'typing', 'tiles', 'overstimulated')),
  tier                int  not null default 2 check (tier between 0 and 6),
  rounds              int  not null default 3 check (rounds between 1 and 100),
  time_zone           text not null default 'UTC',
  joined_at           timestamptz,
  created_at          timestamptz not null default now(),
  primary key (group_id, user_id)
);
create index alarm_group_members_user on public.alarm_group_members (user_id);

-- Who was in for each occurrence, frozen once its cutoff passes. Past days need
-- this: a member's toggle only remembers the latest change.
create table public.alarm_participants (
  group_id      uuid not null references public.alarm_groups (id) on delete cascade,
  occurrence_on date not null,
  user_id       uuid not null references public.profiles (id) on delete cascade,
  scheduled_at  timestamptz not null,
  primary key (group_id, occurrence_on, user_id)
);

create table public.alarm_check_ins (
  group_id          uuid not null references public.alarm_groups (id) on delete cascade,
  user_id           uuid not null references public.profiles (id) on delete cascade,
  occurrence_on     date not null,
  scheduled_at      timestamptz not null,
  woke_at           timestamptz not null,
  received_at       timestamptz not null default now(),
  snoozes           int not null default 0 check (snoozes between 0 and 20),
  emergency_stopped boolean not null default false,
  on_time           boolean not null,
  -- True when the check-in reached the server within 10 minutes of waking.
  -- Offline wakes still count, but moderators can see which ones were late to sync.
  verified          boolean not null,
  photo_path        text,
  photo_added_at    timestamptz,
  primary key (group_id, user_id, occurrence_on)
);

alter table public.reports add column if not exists photo_path text;

-- ─────────────────────────────────────────────────────────────── Rules as functions

create or replace function private.valid_time_zone(tz text)
returns boolean
language sql stable
set search_path = ''
as $$
  select exists (select 1 from pg_catalog.pg_timezone_names where name = tz);
$$;

create or replace function private.occurs_on(g public.alarm_groups, d date)
returns boolean
language sql immutable
set search_path = ''
as $$
  select case
    when g.once_on is not null then d = g.once_on
    else (g.weekdays_mask & (1 << extract(dow from d)::int)) <> 0
  end;
$$;

create or replace function private.scheduled_at(g public.alarm_groups, d date, tz text)
returns timestamptz
language sql stable
set search_path = ''
as $$
  select (d + make_time(g.hour, g.minute, 0)) at time zone tz;
$$;

-- The moment toggles lock for occurrence d: cutoff_minutes past midnight the day before.
create or replace function private.cutoff_at(g public.alarm_groups, d date, tz text)
returns timestamptz
language sql stable
set search_path = ''
as $$
  select ((d - 1) + make_interval(mins => g.cutoff_minutes)) at time zone tz;
$$;

create or replace function private.participates(m public.alarm_group_members, d date)
returns boolean
language sql immutable
set search_path = ''
as $$
  select m.status = 'joined' and case
    when m.toggle_effective_on is null or d >= m.toggle_effective_on then m.is_on
    else m.previous_is_on
  end;
$$;

-- The first occurrence whose cutoff hasn't passed yet: where a change made now lands.
create or replace function private.first_open_occurrence(g public.alarm_groups, tz text)
returns date
language plpgsql stable
set search_path = ''
as $$
declare
  today date := (now() at time zone tz)::date;
  d date;
begin
  for i in 0..8 loop
    d := today + i;
    if private.occurs_on(g, d) and now() < private.cutoff_at(g, d, tz) then
      return d;
    end if;
  end loop;
  return null;   -- a one-off that is already locked or over
end;
$$;

-- The next occurrence that hasn't rung yet, locked or not.
create or replace function private.next_occurrence(g public.alarm_groups, tz text)
returns date
language plpgsql stable
set search_path = ''
as $$
declare
  today date := (now() at time zone tz)::date;
  d date;
begin
  for i in 0..8 loop
    d := today + i;
    if private.occurs_on(g, d) and now() < private.scheduled_at(g, d, tz) then
      return d;
    end if;
  end loop;
  return null;
end;
$$;

-- Freeze participation for every occurrence in the last week whose cutoff has
-- passed. Called before anything that could change the answer, and before reads.
create or replace function private.snapshot_participants(target uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  g public.alarm_groups;
begin
  select * into g from public.alarm_groups where id = target;
  if not found then return; end if;
  insert into public.alarm_participants (group_id, occurrence_on, user_id, scheduled_at)
  select g.id, d::date, m.user_id, private.scheduled_at(g, d::date, m.time_zone)
  from public.alarm_group_members m
  cross join generate_series((current_date - 8)::timestamp, (current_date + 2)::timestamp,
                             interval '1 day') as d
  where m.group_id = g.id
    and private.occurs_on(g, d::date)
    and now() >= private.cutoff_at(g, d::date, m.time_zone)
    and private.participates(m, d::date)
  on conflict do nothing;
end;
$$;

create or replace function private.is_joined(target uuid, who uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (select 1 from public.alarm_group_members
                 where group_id = target and user_id = who and status = 'joined');
$$;

create or replace function private.are_friends(a uuid, b uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (select 1 from public.friendships
                 where status = 'accepted'
                   and least(requester_id, addressee_id) = least(a, b)
                   and greatest(requester_id, addressee_id) = greatest(a, b));
$$;

create or replace function private.check_member_settings(challenge text, tier int, rounds int, tz text)
returns void
language plpgsql stable
set search_path = ''
as $$
begin
  if not private.valid_time_zone(tz) then raise exception 'Unknown time zone.'; end if;
  if challenge not in ('math', 'shake', 'typing', 'tiles', 'overstimulated') then
    raise exception 'Unknown challenge.';
  end if;
  if tier not between 0 and 6 then raise exception 'Unknown difficulty.'; end if;
  if rounds not between 1 and 100 then raise exception 'Rounds must be between 1 and 100.'; end if;
end;
$$;

-- ─────────────────────────────────────────────────────────────── Security

alter table public.alarm_groups        enable row level security;
alter table public.alarm_group_members enable row level security;
alter table public.alarm_participants  enable row level security;
alter table public.alarm_check_ins     enable row level security;
-- No policies: every read and write goes through the functions below.
revoke all on public.alarm_groups, public.alarm_group_members,
              public.alarm_participants, public.alarm_check_ins from anon, authenticated;

-- ─────────────────────────────────────────────────────────────── Groups

create or replace function public.create_alarm_group(
  label text, hour int, minute int, weekdays_mask int, once_on date, cutoff_minutes int,
  time_zone text, challenge text, tier int, rounds int)
returns uuid
language plpgsql security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  g public.alarm_groups;
begin
  if me is null then raise exception 'Not signed in.'; end if;
  perform private.check_member_settings(challenge, tier, rounds, time_zone);
  if (select count(*) from public.alarm_group_members where user_id = me) >= 20 then
    raise exception 'You''re in 20 group alarms already.';
  end if;
  insert into public.alarm_groups (creator_id, label, hour, minute, weekdays_mask, once_on, cutoff_minutes)
  values (me, trim(label), hour, minute, coalesce(weekdays_mask, 0),
          case when coalesce(weekdays_mask, 0) = 0 then once_on end, coalesce(cutoff_minutes, 1260))
  returning * into g;
  insert into public.alarm_group_members
    (group_id, user_id, status, is_on, previous_is_on, toggle_effective_on,
     challenge, tier, rounds, time_zone, joined_at)
  values (g.id, me, 'joined', true, false, private.first_open_occurrence(g, time_zone),
          challenge, tier, rounds, time_zone, now());
  return g.id;
end;
$$;

create or replace function public.update_alarm_group(
  target uuid, label text, hour int, minute int, weekdays_mask int, once_on date, cutoff_minutes int)
returns void
language plpgsql security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from public.alarm_groups where id = target and creator_id = auth.uid()) then
    raise exception 'Only the person who made this group can change it.';
  end if;
  perform private.snapshot_participants(target);
  update public.alarm_groups set
    label = trim(update_alarm_group.label),
    hour = update_alarm_group.hour,
    minute = update_alarm_group.minute,
    weekdays_mask = coalesce(update_alarm_group.weekdays_mask, 0),
    once_on = case when coalesce(update_alarm_group.weekdays_mask, 0) = 0 then update_alarm_group.once_on end,
    cutoff_minutes = coalesce(update_alarm_group.cutoff_minutes, 1260),
    updated_at = now()
  where id = target;
end;
$$;

create or replace function public.delete_alarm_group(target uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
begin
  delete from public.alarm_groups where id = target and creator_id = auth.uid();
  if not found then raise exception 'Only the person who made this group can delete it.'; end if;
end;
$$;

create or replace function public.invite_to_alarm_group(target uuid, friend uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
begin
  if not private.is_joined(target, me) then raise exception 'You''re not in this group.'; end if;
  if not private.are_friends(me, friend) or private.is_blocked_between(me, friend) then
    raise exception 'You can only invite friends.';
  end if;
  if (select count(*) from public.alarm_group_members where group_id = target) >= 20 then
    raise exception 'Groups hold up to 20 people.';
  end if;
  insert into public.alarm_group_members (group_id, user_id, status, invited_by)
  values (target, friend, 'invited', me)
  on conflict do nothing;
end;
$$;

create or replace function public.respond_to_group_invite(
  target uuid, accept boolean, time_zone text, challenge text, tier int, rounds int)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  g public.alarm_groups;
begin
  if not accept then
    delete from public.alarm_group_members
    where group_id = target and user_id = me and status = 'invited';
    return;
  end if;
  perform private.check_member_settings(challenge, tier, rounds, time_zone);
  select * into g from public.alarm_groups where id = target;
  if not found then raise exception 'That group no longer exists.'; end if;
  update public.alarm_group_members set
    status = 'joined',
    joined_at = now(),
    is_on = true,
    previous_is_on = false,
    -- Joining after tonight's cutoff means tomorrow doesn't count for you yet.
    -- 'infinity' covers a one-off that's already locked: you're in, but not for it.
    toggle_effective_on = coalesce(private.first_open_occurrence(g, respond_to_group_invite.time_zone),
                                   'infinity'::date),
    challenge = respond_to_group_invite.challenge,
    tier = respond_to_group_invite.tier,
    rounds = respond_to_group_invite.rounds,
    time_zone = respond_to_group_invite.time_zone
  where group_id = target and user_id = me and status = 'invited';
  if not found then raise exception 'That invite is no longer open.'; end if;
end;
$$;

create or replace function public.leave_alarm_group(target uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  heir uuid;
begin
  perform private.snapshot_participants(target);
  -- Leaving drops you from occurrences that haven't rung yet, not from history.
  delete from public.alarm_participants
  where group_id = target and user_id = me and scheduled_at > now();
  delete from public.alarm_group_members where group_id = target and user_id = me;

  if exists (select 1 from public.alarm_groups where id = target and creator_id = me) then
    select user_id into heir from public.alarm_group_members
    where group_id = target and status = 'joined'
    order by joined_at limit 1;
    if heir is null then
      delete from public.alarm_groups where id = target;
    else
      update public.alarm_groups set creator_id = heir, updated_at = now() where id = target;
    end if;
  end if;
end;
$$;

-- Flip your own toggle. If tonight's cutoff has passed, the change waits for the
-- occurrence after, and the locked one stays exactly as it was.
create or replace function public.set_group_alarm_on(target uuid, turn_on boolean, time_zone text)
returns date
language plpgsql security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  g public.alarm_groups;
  m public.alarm_group_members;
  effective date;
begin
  if not private.valid_time_zone(time_zone) then raise exception 'Unknown time zone.'; end if;
  select * into m from public.alarm_group_members
  where group_id = target and user_id = me and status = 'joined';
  if not found then raise exception 'You''re not in this group.'; end if;
  select * into g from public.alarm_groups where id = target;

  perform private.snapshot_participants(target);
  effective := private.first_open_occurrence(g, time_zone);

  update public.alarm_group_members set
    -- What occurrences before `effective` keep, including any change still pending.
    previous_is_on = private.participates(
                       m, coalesce(effective - 1, (now() at time zone set_group_alarm_on.time_zone)::date + 8)),
    is_on = turn_on,
    -- No open occurrence (a locked one-off): the change never reaches it.
    toggle_effective_on = coalesce(effective, 'infinity'::date),
    time_zone = set_group_alarm_on.time_zone
  where group_id = target and user_id = me;
  return effective;
end;
$$;

-- Challenge, difficulty and rounds are personal and never locked.
create or replace function public.update_my_group_settings(
  target uuid, challenge text, tier int, rounds int, time_zone text)
returns void
language plpgsql security definer
set search_path = ''
as $$
begin
  perform private.check_member_settings(challenge, tier, rounds, time_zone);
  update public.alarm_group_members set
    challenge = update_my_group_settings.challenge,
    tier = update_my_group_settings.tier,
    rounds = update_my_group_settings.rounds,
    time_zone = update_my_group_settings.time_zone
  where group_id = target and user_id = auth.uid() and status = 'joined';
  if not found then raise exception 'You''re not in this group.'; end if;
end;
$$;

-- ─────────────────────────────────────────────────────────────── Waking up

-- On time: finished the challenge (no emergency stop) between 10 minutes before
-- and 30 minutes after the alarm, and synced within 6 hours.
create or replace function public.check_in_group_alarm(
  target uuid, occurrence_on date, woke_at timestamptz, snoozes int, emergency_stopped boolean)
returns boolean
language plpgsql security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  g public.alarm_groups;
  m public.alarm_group_members;
  planned timestamptz;
  woke timestamptz := least(woke_at, now());
  timely boolean;
begin
  select * into m from public.alarm_group_members
  where group_id = target and user_id = me and status = 'joined';
  if not found then raise exception 'You''re not in this group.'; end if;
  select * into g from public.alarm_groups where id = target;
  if not private.occurs_on(g, occurrence_on) then
    raise exception 'This group has no alarm on that day.';
  end if;

  perform private.snapshot_participants(target);
  select scheduled_at into planned from public.alarm_participants p
  where p.group_id = target and p.occurrence_on = check_in_group_alarm.occurrence_on and p.user_id = me;
  if planned is null then
    return false;     -- you weren't in for this one; nothing to count
  end if;

  timely := not emergency_stopped
    and woke >= planned - interval '10 minutes'
    and woke <= planned + interval '30 minutes'
    and now() <= planned + interval '6 hours';

  insert into public.alarm_check_ins
    (group_id, user_id, occurrence_on, scheduled_at, woke_at, snoozes, emergency_stopped, on_time, verified)
  values (target, me, check_in_group_alarm.occurrence_on, planned, woke,
          least(greatest(coalesce(snoozes, 0), 0), 20), emergency_stopped, timely,
          now() - woke <= interval '10 minutes')
  -- The first check-in stands. Retrying can't turn a late wake into an early one.
  -- (Named constraint: the parameter `occurrence_on` would shadow the column.)
  on conflict on constraint alarm_check_ins_pkey do nothing;

  select on_time into timely from public.alarm_check_ins c
  where c.group_id = target and c.user_id = me and c.occurrence_on = check_in_group_alarm.occurrence_on;
  return timely;
end;
$$;

create or replace function public.attach_wake_photo(target uuid, occurrence_on date)
returns text
language plpgsql security definer
set search_path = ''
as $$
declare
  path text := target::text || '/' || occurrence_on::text || '/' || auth.uid()::text || '.jpg';
begin
  update public.alarm_check_ins set photo_path = path, photo_added_at = now()
  where group_id = target and user_id = auth.uid()
    and alarm_check_ins.occurrence_on = attach_wake_photo.occurrence_on
    and not emergency_stopped;
  if not found then raise exception 'Check in before adding a photo.'; end if;
  return path;
end;
$$;

-- ─────────────────────────────────────────────────────────────── Reading

-- Every group you're in or invited to, with what this phone needs to schedule it.
create or replace function public.my_alarm_groups()
returns table (
  group_id uuid, label text, hour int, minute int, weekdays_mask int, once_on date,
  cutoff_minutes int, creator_id uuid, creator_username text, updated_at timestamptz,
  my_status text, invited_by_username text, is_on boolean,
  challenge text, tier int, rounds int,
  member_count int, next_occurrence date, next_locked boolean, counts_next boolean
)
language sql stable security definer
set search_path = ''
as $$
  select g.id, g.label, g.hour, g.minute, g.weekdays_mask, g.once_on,
         g.cutoff_minutes, g.creator_id, cp.username, g.updated_at,
         m.status, ip.username, m.is_on,
         m.challenge, m.tier, m.rounds,
         (select count(*)::int from public.alarm_group_members x
          where x.group_id = g.id and x.status = 'joined'),
         n.d,
         n.d is not null and now() >= private.cutoff_at(g, n.d, m.time_zone),
         n.d is not null and private.participates(m, n.d)
  from public.alarm_group_members m
  join public.alarm_groups g on g.id = m.group_id
  join public.profiles cp on cp.id = g.creator_id
  left join public.profiles ip on ip.id = m.invited_by
  cross join lateral (select private.next_occurrence(g, m.time_zone) as d) n
  where m.user_id = auth.uid()
  order by m.status desc, g.hour, g.minute;
$$;

-- The board for one day: who's in, who's up, who was late, and photos.
create or replace function public.alarm_group_day(target uuid, day date)
returns table (
  user_id uuid, username text, display_name text, avatar_emoji text,
  member_status text, participating boolean, scheduled_at timestamptz,
  checked_in boolean, woke_at timestamptz, on_time boolean, snoozes int,
  emergency_stopped boolean, photo_path text
)
language plpgsql security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
begin
  if not private.is_joined(target, me) then raise exception 'You''re not in this group.'; end if;
  perform private.snapshot_participants(target);
  return query
  select p.id, p.username, p.display_name, p.avatar_emoji,
         coalesce(m.status, 'left'),
         ap.user_id is not null,
         coalesce(ap.scheduled_at, c.scheduled_at),
         c.user_id is not null, c.woke_at, coalesce(c.on_time, false), c.snoozes,
         coalesce(c.emergency_stopped, false),
         -- Photos are visible for 24 hours, and never between blocked people.
         case when c.photo_added_at > now() - interval '24 hours'
                   and not private.is_blocked_between(me, p.id)
              then c.photo_path end
  from public.profiles p
  left join public.alarm_group_members m on m.group_id = target and m.user_id = p.id
  left join public.alarm_participants ap
    on ap.group_id = target and ap.occurrence_on = day and ap.user_id = p.id
  left join public.alarm_check_ins c
    on c.group_id = target and c.occurrence_on = day and c.user_id = p.id
  where (m.user_id is not null or ap.user_id is not null or c.user_id is not null)
    and (p.id = me or not private.is_blocked_between(me, p.id))
  order by p.id = me desc, p.username;
end;
$$;

-- Consecutive occurrences, newest first, where everyone who was in woke on time.
-- An occurrence nobody was in doesn't break it; today doesn't until it's over.
create or replace function public.alarm_group_streak(target uuid)
returns int
language plpgsql security definer
set search_path = ''
as $$
declare
  streak int := 0;
  r record;
begin
  if not private.is_joined(target, auth.uid()) then raise exception 'You''re not in this group.'; end if;
  perform private.snapshot_participants(target);
  for r in
    select ap.occurrence_on,
           bool_and(coalesce(c.on_time, false)) as everyone_on_time,
           max(ap.scheduled_at) as last_scheduled
    from public.alarm_participants ap
    left join public.alarm_check_ins c
      on c.group_id = ap.group_id and c.occurrence_on = ap.occurrence_on and c.user_id = ap.user_id
    where ap.group_id = target
    group by ap.occurrence_on
    order by ap.occurrence_on desc
    limit 400
  loop
    if r.everyone_on_time then
      streak := streak + 1;
    elsif now() <= r.last_scheduled + interval '30 minutes' then
      continue;       -- still open: people can still wake up on time
    else
      exit;
    end if;
  end loop;
  return streak;
end;
$$;

create or replace function public.report_wake_photo(target uuid, occurrence_on date, member uuid, details text default null)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  photo text;
  name text;
begin
  if not private.is_joined(target, auth.uid()) then raise exception 'You''re not in this group.'; end if;
  select c.photo_path into photo from public.alarm_check_ins c
  where c.group_id = target and c.user_id = member and c.occurrence_on = report_wake_photo.occurrence_on;
  select username into name from public.profiles where id = member;
  if photo is null or name is null then raise exception 'That photo is gone.'; end if;
  insert into public.reports (reporter_id, reported_id, reported_username, reason, details, photo_path)
  values (auth.uid(), member, name, 'inappropriate_photo', nullif(trim(details), ''), photo);
end;
$$;

-- ─────────────────────────────────────────────────────────────── Wake photos storage

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('wake-photos', 'wake-photos', false, 2097152, array['image/jpeg'])
on conflict (id) do nothing;

-- Path: <group id>/<occurrence date>/<user id>.jpg
create or replace function private.can_write_wake_photo(object_name text)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.alarm_check_ins c
    where c.group_id::text = split_part(object_name, '/', 1)
      and c.occurrence_on::text = split_part(object_name, '/', 2)
      and c.user_id = auth.uid()
      and split_part(object_name, '/', 3) = auth.uid()::text || '.jpg'
      and not c.emergency_stopped
      and c.received_at > now() - interval '24 hours'
  );
$$;

create or replace function private.can_read_wake_photo(object_name text, created timestamptz)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select created > now() - interval '24 hours'
     and private.is_joined(split_part(object_name, '/', 1)::uuid, auth.uid())
     and not private.is_blocked_between(
           auth.uid(), nullif(split_part(split_part(object_name, '/', 3), '.', 1), '')::uuid);
$$;

create policy "wake photos: upload your own"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'wake-photos' and private.can_write_wake_photo(name));

create policy "wake photos: replace your own"
  on storage.objects for update to authenticated
  using (bucket_id = 'wake-photos' and private.can_write_wake_photo(name))
  with check (bucket_id = 'wake-photos' and private.can_write_wake_photo(name));

create policy "wake photos: group members for 24 hours"
  on storage.objects for select to authenticated
  using (bucket_id = 'wake-photos' and private.can_read_wake_photo(name, created_at));

create policy "wake photos: delete your own"
  on storage.objects for delete to authenticated
  using (bucket_id = 'wake-photos' and split_part(name, '/', 3) = auth.uid()::text || '.jpg');

-- ─────────────────────────────────────────────────────────────── Who may call what

revoke execute on all functions in schema public from public, anon;
revoke execute on all functions in schema private from public, anon;

grant execute on function
  public.create_alarm_group(text, int, int, int, date, int, text, text, int, int),
  public.update_alarm_group(uuid, text, int, int, int, date, int),
  public.delete_alarm_group(uuid),
  public.invite_to_alarm_group(uuid, uuid),
  public.respond_to_group_invite(uuid, boolean, text, text, int, int),
  public.leave_alarm_group(uuid),
  public.set_group_alarm_on(uuid, boolean, text),
  public.update_my_group_settings(uuid, text, int, int, text),
  public.check_in_group_alarm(uuid, date, timestamptz, int, boolean),
  public.attach_wake_photo(uuid, date),
  public.my_alarm_groups(),
  public.alarm_group_day(uuid, date),
  public.alarm_group_streak(uuid),
  public.report_wake_photo(uuid, date, uuid, text)
to authenticated;

-- The revoke above covers every function in public, including the sign-up check
-- from the friends migration, which has to stay callable before sign-in.
grant execute on function public.username_available(text) to anon, authenticated;
grant execute on function
  public.create_profile(text), public.find_profile(text), public.send_friend_request(uuid),
  public.respond_to_friend_request(uuid, boolean), public.remove_friendship(uuid),
  public.block_user(uuid), public.unblock_user(uuid), public.report_user(uuid, text, text),
  public.my_connections(), public.my_blocks(), public.delete_account()
to authenticated;
grant execute on function private.is_blocked_between(uuid, uuid) to authenticated;
grant execute on function private.username_problem(text) to authenticated;
grant execute on function private.profiles_before_write() to authenticated;

-- Storage policies run as the caller.
grant execute on function private.can_write_wake_photo(text) to authenticated;
grant execute on function private.can_read_wake_photo(text, timestamptz) to authenticated;
