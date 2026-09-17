-- One-time cleanup: removes an older, incompatible Jasara schema (profiles,
-- friendships, alarms, groups, group_members) so the real migrations can run.
--
-- Safe by design: if ANY of those tables contains even one row, it stops before
-- changing anything, and nothing is deleted. Your auth users (logins) are never
-- touched.
--
-- Run this first, then migrations/20260916000000_friends.sql, then
-- migrations/20260917000000_group_alarms.sql.

do $$
declare
  t text;
  n bigint;
begin
  foreach t in array array['profiles', 'friendships', 'alarms', 'groups', 'group_members'] loop
    if to_regclass('public.' || t) is not null then
      execute format('select count(*) from public.%I', t) into n;
      if n > 0 then
        raise exception 'Stopped: public.% has % row(s). Nothing was changed.', t, n;
      end if;
    end if;
  end loop;
end $$;

-- An old sign-up trigger would try to write into the old profiles table and make
-- every new sign-up fail. Remove any custom triggers on auth.users.
do $$
declare
  trig record;
begin
  for trig in
    select tgname from pg_trigger
    where tgrelid = 'auth.users'::regclass and not tgisinternal
  loop
    execute format('drop trigger %I on auth.users', trig.tgname);
    raise notice 'Removed old trigger % on auth.users', trig.tgname;
  end loop;
end $$;

drop function if exists public.handle_new_user() cascade;

drop table if exists
  public.group_members,
  public.groups,
  public.alarms,
  public.friendships,
  public.profiles
cascade;

select 'Old schema removed. Now run the friends migration.' as result;
