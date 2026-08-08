-- Stream 2 · Migration 12 — membership flows + action provenance
--
-- 1. action_source: provenance vocabulary shared with the future multi-agent
--    world (Atlas / Katie interop). record_history rows now say WHAT KIND of
--    actor made a change, alongside changed_by (who). Server-side writers
--    declare themselves via the app.action_source GUC; absent = 'user'.
-- 2. Membership RPCs: invite redemption, invite regeneration, leaving.
--    SECURITY DEFINER because redemption happens before membership exists.
-- 3. Last-admin protection: a household can never lose its final admin
--    through the client (deletion stays service-role-only).

create type public.action_source as enum ('user', 'foodie', 'atlas', 'katie', 'system');

-- ---------------------------------------------------------------------------
-- Provenance on the data-level audit log.
-- ---------------------------------------------------------------------------
alter table public.record_history
  add column source public.action_source not null default 'user';

create or replace function public.current_action_source()
returns public.action_source
language sql
stable
as $$
  select coalesce(
    nullif(current_setting('app.action_source', true), '')::public.action_source,
    'user'
  );
$$;

create or replace function public.log_record_history()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  hh      uuid;
  rec_id  uuid;
  d       jsonb;
begin
  if tg_op = 'INSERT' then
    hh     := (to_jsonb(new) ->> 'household_id')::uuid;
    rec_id := new.id;
    d      := jsonb_build_object('new', to_jsonb(new));
  elsif tg_op = 'UPDATE' then
    hh     := (to_jsonb(new) ->> 'household_id')::uuid;
    rec_id := new.id;
    select jsonb_build_object(
             'changed',
             coalesce(jsonb_object_agg(o.k, jsonb_build_object('old', o.v, 'new', n.v)), '{}'::jsonb))
      into d
      from jsonb_each(to_jsonb(old)) as o(k, v)
      join jsonb_each(to_jsonb(new)) as n(k, v) on n.k = o.k
     where o.v is distinct from n.v
       and o.k <> 'updated_at';
    if d -> 'changed' = '{}'::jsonb then
      return new;
    end if;
  else
    hh     := (to_jsonb(old) ->> 'household_id')::uuid;
    rec_id := old.id;
    d      := jsonb_build_object('old', to_jsonb(old));
  end if;

  insert into public.record_history (household_id, table_name, record_id, op, changed_by, source, diff)
  values (hh, tg_table_name, rec_id, tg_op, auth.uid(), public.current_action_source(), d);

  return coalesce(new, old);
end;
$$;

-- Intent-level audit gets the same provenance (Foodie's executor writes
-- 'foodie'; a future interop layer writes 'atlas'/'katie').
alter table public.agent_actions
  add column source public.action_source not null default 'foodie';

-- Fermentation log authorship migrates to the shared vocabulary.
alter table public.fermentation_logs
  alter column author drop default,
  alter column author type public.action_source using author::text::public.action_source,
  alter column author set default 'user';

drop type public.log_author;

-- ---------------------------------------------------------------------------
-- Last-admin protection on household_members.
-- Blocks deleting or demoting the only admin (RLS already limits who can try;
-- this guards against the permitted cases: self-leave and admin edits).
-- ---------------------------------------------------------------------------
create or replace function public.protect_last_admin()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.role = 'admin'
     and (tg_op = 'DELETE' or new.role <> 'admin')
     and not exists (
       select 1 from household_members m
       where m.household_id = old.household_id
         and m.role = 'admin'
         and m.id <> old.id
     )
  then
    raise exception 'cannot remove or demote the last admin of a household'
      using errcode = 'P0001';
  end if;
  return coalesce(new, old);
end;
$$;

create trigger trg_protect_last_admin
  before update or delete on public.household_members
  for each row execute function public.protect_last_admin();

-- ---------------------------------------------------------------------------
-- Membership RPCs (called from the app via supabase.rpc()).
-- ---------------------------------------------------------------------------

-- Join a household by invite code. SECURITY DEFINER: the caller is not yet a
-- member, so RLS would otherwise hide the household and forbid the insert.
-- Case-insensitive on the code; idempotent for existing members.
create or replace function public.redeem_household_invite(code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  hh uuid;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = 'P0002';
  end if;

  select id into hh
  from households
  where invite_code = lower(trim(code));

  if hh is null then
    raise exception 'invalid invite code' using errcode = 'P0003';
  end if;

  insert into household_members (household_id, user_id, role)
  values (hh, auth.uid(), 'member')
  on conflict (household_id, user_id) do nothing;

  return hh;
end;
$$;

-- Rotate the invite code (admins only). Returns the new code.
create or replace function public.regenerate_invite_code(hh uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  new_code text;
begin
  if not public.is_household_admin(hh) then
    raise exception 'only household admins can regenerate the invite code'
      using errcode = 'P0004';
  end if;

  new_code := encode(gen_random_bytes(6), 'hex');
  update households set invite_code = new_code where id = hh;
  return new_code;
end;
$$;

-- Leave a household. Last-admin protection still applies via the trigger.
create or replace function public.leave_household(hh uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = 'P0002';
  end if;

  delete from household_members
  where household_id = hh and user_id = auth.uid();

  if not found then
    raise exception 'not a member of this household' using errcode = 'P0005';
  end if;
end;
$$;

-- RPCs are executable by signed-in users only.
revoke execute on function public.redeem_household_invite(text) from public;
revoke execute on function public.regenerate_invite_code(uuid) from public;
revoke execute on function public.leave_household(uuid) from public;
grant execute on function public.redeem_household_invite(text) to authenticated;
grant execute on function public.regenerate_invite_code(uuid) to authenticated;
grant execute on function public.leave_household(uuid) to authenticated;

-- Invite codes are stored lowercase; normalize any existing ones.
update public.households set invite_code = lower(invite_code) where invite_code <> lower(invite_code);
