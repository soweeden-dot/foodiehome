-- Stream 1 · Migration 02 — core: profiles, households, membership, devices

create type public.member_role as enum ('admin', 'member');
create type public.device_profile as enum ('kitchen_ipad', 'ipad', 'phone', 'other');

-- ---------------------------------------------------------------------------
-- profiles — 1:1 with auth.users. App-visible identity + contact details.
-- ---------------------------------------------------------------------------
create table public.profiles (
  id            uuid primary key references auth.users (id) on delete cascade,
  display_name  text not null default '',
  avatar_path   text,
  -- E.164 phone number; used later by the SMS notification channel (Twilio).
  phone_number  text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create trigger trg_profiles_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- Auto-create a profile row whenever an auth user is created.
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', split_part(new.email, '@', 1), ''))
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger trg_on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();

-- ---------------------------------------------------------------------------
-- households
-- ---------------------------------------------------------------------------
create table public.households (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  created_by  uuid not null references public.profiles (id),
  -- Invite code for joining (redemption flow is Stream 2; column exists so the
  -- schema doesn't change).
  invite_code text unique default encode(gen_random_bytes(6), 'hex'),
  timezone    text not null default 'UTC',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create trigger trg_households_updated_at
  before update on public.households
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- household_members — join table between users and households
-- ---------------------------------------------------------------------------
create table public.household_members (
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references public.households (id) on delete cascade,
  user_id       uuid not null references public.profiles (id) on delete cascade,
  role          public.member_role not null default 'member',
  joined_at     timestamptz not null default now(),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (household_id, user_id)
);

create index idx_household_members_user on public.household_members (user_id);

create trigger trg_household_members_updated_at
  before update on public.household_members
  for each row execute function public.set_updated_at();

-- Creating a household makes the creator its admin. SECURITY DEFINER because
-- at that moment the creator is not yet a member, so RLS on household_members
-- would reject the insert.
create or replace function public.handle_new_household()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.household_members (household_id, user_id, role)
  values (new.id, new.created_by, 'admin');
  return new;
end;
$$;

create trigger trg_on_household_created
  after insert on public.households
  for each row execute function public.handle_new_household();

-- ---------------------------------------------------------------------------
-- Membership helper functions — the single RLS predicate used everywhere.
-- SECURITY DEFINER so they read household_members without re-entering its own
-- RLS policies (avoids recursive policy evaluation).
-- ---------------------------------------------------------------------------
create or replace function public.is_household_member(hh uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from household_members m
    where m.household_id = hh and m.user_id = auth.uid()
  );
$$;

create or replace function public.is_household_admin(hh uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from household_members m
    where m.household_id = hh and m.user_id = auth.uid() and m.role = 'admin'
  );
$$;

create or replace function public.shares_household_with(other uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from household_members a
    join household_members b on b.household_id = a.household_id
    where a.user_id = auth.uid() and b.user_id = other
  );
$$;

-- ---------------------------------------------------------------------------
-- devices — one row per app installation. Devices are not identities; they
-- record which physical device a session runs on (layout pinning, sync
-- bookkeeping, later: per-device dashboard layout).
-- ---------------------------------------------------------------------------
create table public.devices (
  id            uuid primary key,                    -- generated by the client install
  household_id  uuid not null references public.households (id) on delete cascade,
  owner_user_id uuid references public.profiles (id) on delete set null,
  name          text not null,
  profile       public.device_profile not null default 'other',
  last_seen_at  timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index idx_devices_household on public.devices (household_id);

create trigger trg_devices_updated_at
  before update on public.devices
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
alter table public.profiles          enable row level security;
alter table public.households        enable row level security;
alter table public.household_members enable row level security;
alter table public.devices           enable row level security;

-- profiles: read self + anyone sharing a household; write self only.
create policy profiles_select on public.profiles
  for select using (id = auth.uid() or public.shares_household_with(id));
create policy profiles_insert on public.profiles
  for insert with check (id = auth.uid());
create policy profiles_update on public.profiles
  for update using (id = auth.uid()) with check (id = auth.uid());

-- households: members read; any authenticated user may create one for
-- themselves; admins update. No client-side delete (deliberate).
create policy households_select on public.households
  for select using (public.is_household_member(id));
create policy households_insert on public.households
  for insert with check (created_by = auth.uid());
create policy households_update on public.households
  for update using (public.is_household_admin(id))
  with check (public.is_household_admin(id));

-- household_members: members see the roster; admins manage it. Bootstrap
-- insert (creator) happens via the SECURITY DEFINER trigger above; invite
-- redemption arrives in Stream 2 as a SECURITY DEFINER function.
create policy household_members_select on public.household_members
  for select using (public.is_household_member(household_id));
create policy household_members_insert on public.household_members
  for insert with check (public.is_household_admin(household_id));
create policy household_members_update on public.household_members
  for update using (public.is_household_admin(household_id))
  with check (public.is_household_admin(household_id));
create policy household_members_delete on public.household_members
  for delete using (public.is_household_admin(household_id) or user_id = auth.uid());

-- devices: standard member access.
create policy devices_member_all on public.devices
  for all using (public.is_household_member(household_id))
  with check (public.is_household_member(household_id));
