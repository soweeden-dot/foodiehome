-- Stream 1 · Migration 02 — core: profiles, households, membership, devices

create type foodie.member_role as enum ('admin', 'member');
create type foodie.device_profile as enum ('kitchen_ipad', 'ipad', 'phone', 'other');

-- ---------------------------------------------------------------------------
-- profiles — 1:1 with auth.users. App-visible identity + contact details.
-- Foodie's OWN profile table, distinct from anything Keep Track may have.
-- ---------------------------------------------------------------------------
create table foodie.profiles (
  id            uuid primary key references auth.users (id) on delete cascade,
  display_name  text not null default '',
  avatar_path   text,
  -- E.164 phone number; used later by the SMS notification channel (Twilio).
  phone_number  text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create trigger trg_profiles_updated_at
  before update on foodie.profiles
  for each row execute function foodie.set_updated_at();

-- Auto-create a Foodie profile row whenever an auth user is created.
create or replace function foodie.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = foodie, pg_temp
as $$
begin
  insert into foodie.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', split_part(new.email, '@', 1), ''))
  on conflict (id) do nothing;
  return new;
end;
$$;

-- SHARED-TABLE TOUCHPOINT: auth.users is Supabase-managed and shared with
-- Keep Track. This is Foodie's ONLY object on a table it doesn't own, and it
-- is deliberately isolated:
--   * uniquely named (trg_foodie_new_auth_user) so it cannot collide with,
--     shadow, or be confused with any trigger Keep Track (or anything else)
--     already has on this table;
--   * calls only foodie.handle_new_auth_user(), which touches foodie.profiles
--     exclusively;
--   * additive only — Postgres runs multiple AFTER INSERT triggers on the
--     same table independently, in name order, so this coexists with any
--     pre-existing Keep Track trigger on auth.users without altering,
--     replacing, or depending on it in any way.
create trigger trg_foodie_new_auth_user
  after insert on auth.users
  for each row execute function foodie.handle_new_auth_user();

-- ---------------------------------------------------------------------------
-- households
-- ---------------------------------------------------------------------------
create table foodie.households (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  created_by  uuid not null references foodie.profiles (id),
  -- Invite code for joining (redemption flow is Stream 2; column exists so the
  -- schema doesn't change).
  -- 12 hex chars derived from gen_random_uuid() rather than pgcrypto's
  -- gen_random_bytes(): gen_random_uuid() has been a core Postgres builtin
  -- (pg_catalog, always implicitly searched) since PG13, so this never
  -- depends on knowing which schema pgcrypto happens to be installed in —
  -- important now that SECURITY DEFINER functions pin search_path to
  -- `foodie` and can no longer assume pgcrypto is reachable unqualified.
  invite_code text unique default substr(replace(gen_random_uuid()::text, '-', ''), 1, 12),
  timezone    text not null default 'UTC',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create trigger trg_households_updated_at
  before update on foodie.households
  for each row execute function foodie.set_updated_at();

-- ---------------------------------------------------------------------------
-- household_members — join table between users and households
-- ---------------------------------------------------------------------------
create table foodie.household_members (
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references foodie.households (id) on delete cascade,
  user_id       uuid not null references foodie.profiles (id) on delete cascade,
  role          foodie.member_role not null default 'member',
  joined_at     timestamptz not null default now(),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (household_id, user_id)
);

create index idx_household_members_user on foodie.household_members (user_id);

create trigger trg_household_members_updated_at
  before update on foodie.household_members
  for each row execute function foodie.set_updated_at();

-- Creating a household makes the creator its admin. SECURITY DEFINER because
-- at that moment the creator is not yet a member, so RLS on household_members
-- would reject the insert.
create or replace function foodie.handle_new_household()
returns trigger
language plpgsql
security definer
set search_path = foodie, pg_temp
as $$
begin
  insert into foodie.household_members (household_id, user_id, role)
  values (new.id, new.created_by, 'admin');
  return new;
end;
$$;

create trigger trg_on_household_created
  after insert on foodie.households
  for each row execute function foodie.handle_new_household();

-- ---------------------------------------------------------------------------
-- Membership helper functions — the single RLS predicate used everywhere.
-- SECURITY DEFINER so they read household_members without re-entering its own
-- RLS policies (avoids recursive policy evaluation). search_path is pinned to
-- foodie (+ pg_temp) so these can never accidentally resolve an unqualified
-- name against public/Keep Track objects.
-- ---------------------------------------------------------------------------
create or replace function foodie.is_household_member(hh uuid)
returns boolean
language sql
stable
security definer
set search_path = foodie, pg_temp
as $$
  select exists (
    select 1 from foodie.household_members m
    where m.household_id = hh and m.user_id = auth.uid()
  );
$$;

create or replace function foodie.is_household_admin(hh uuid)
returns boolean
language sql
stable
security definer
set search_path = foodie, pg_temp
as $$
  select exists (
    select 1 from foodie.household_members m
    where m.household_id = hh and m.user_id = auth.uid() and m.role = 'admin'
  );
$$;

create or replace function foodie.shares_household_with(other uuid)
returns boolean
language sql
stable
security definer
set search_path = foodie, pg_temp
as $$
  select exists (
    select 1
    from foodie.household_members a
    join foodie.household_members b on b.household_id = a.household_id
    where a.user_id = auth.uid() and b.user_id = other
  );
$$;

-- ---------------------------------------------------------------------------
-- devices — one row per app installation. Devices are not identities; they
-- record which physical device a session runs on (layout pinning, sync
-- bookkeeping, later: per-device dashboard layout).
-- ---------------------------------------------------------------------------
create table foodie.devices (
  id            uuid primary key,                    -- generated by the client install
  household_id  uuid not null references foodie.households (id) on delete cascade,
  owner_user_id uuid references foodie.profiles (id) on delete set null,
  name          text not null,
  profile       foodie.device_profile not null default 'other',
  last_seen_at  timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index idx_devices_household on foodie.devices (household_id);

create trigger trg_devices_updated_at
  before update on foodie.devices
  for each row execute function foodie.set_updated_at();

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
alter table foodie.profiles          enable row level security;
alter table foodie.households        enable row level security;
alter table foodie.household_members enable row level security;
alter table foodie.devices           enable row level security;

-- profiles: read self + anyone sharing a household; write self only.
create policy profiles_select on foodie.profiles
  for select using (id = auth.uid() or foodie.shares_household_with(id));
create policy profiles_insert on foodie.profiles
  for insert with check (id = auth.uid());
create policy profiles_update on foodie.profiles
  for update using (id = auth.uid()) with check (id = auth.uid());

-- households: members read; any authenticated user may create one for
-- themselves; admins update. No client-side delete (deliberate).
create policy households_select on foodie.households
  for select using (foodie.is_household_member(id));
create policy households_insert on foodie.households
  for insert with check (created_by = auth.uid());
create policy households_update on foodie.households
  for update using (foodie.is_household_admin(id))
  with check (foodie.is_household_admin(id));

-- household_members: members see the roster; admins manage it. Bootstrap
-- insert (creator) happens via the SECURITY DEFINER trigger above; invite
-- redemption arrives in Stream 2 as a SECURITY DEFINER function.
create policy household_members_select on foodie.household_members
  for select using (foodie.is_household_member(household_id));
create policy household_members_insert on foodie.household_members
  for insert with check (foodie.is_household_admin(household_id));
create policy household_members_update on foodie.household_members
  for update using (foodie.is_household_admin(household_id))
  with check (foodie.is_household_admin(household_id));
create policy household_members_delete on foodie.household_members
  for delete using (foodie.is_household_admin(household_id) or user_id = auth.uid());

-- devices: standard member access.
create policy devices_member_all on foodie.devices
  for all using (foodie.is_household_member(household_id))
  with check (foodie.is_household_member(household_id));
