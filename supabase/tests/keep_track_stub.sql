-- Simulates Keep Track's pre-existing footprint in `public`, so the
-- coexistence test can prove Foodie's migrations neither collide with nor
-- disturb it. NEVER deployed — this exists purely to make the isolation
-- guarantee testable locally, ahead of ever touching the real shared
-- project. Modeled on the two collision candidates identified during
-- design: a `profiles` table and a `set_updated_at()` trigger helper, both
-- extremely common Supabase-tutorial names, plus the standard
-- auth.users-provisioning trigger pattern.
--
-- Run this AFTER auth_stub.sql and BEFORE the Foodie migrations.

create table public.profiles (
  id                 uuid primary key references auth.users (id),
  -- Distinctive marker: if this row shape or its data ever changes as a
  -- side effect of applying Foodie's migrations, something is wrong.
  keep_track_marker  text not null default 'keep-track-owns-this',
  updated_at         timestamptz not null default now()
);

-- A same-named trigger helper as Foodie's own foodie.set_updated_at() —
-- deliberately behaves differently (bumps a counter via a notice) so a
-- silent CREATE OR REPLACE overwrite by a same-named Foodie function would
-- be detectable, not just "still present".
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  raise notice 'keep_track.set_updated_at fired for %', tg_table_name;
  return new;
end;
$$;

create trigger trg_keep_track_profiles_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- The standard Supabase auth-provisioning pattern: a trigger on the SHARED
-- auth.users table, calling a same-domain function name. This is the
-- sharpest test of "multiple independent triggers must coexist" — Foodie's
-- own trigger on auth.users must not collide with, replace, or interfere
-- with this one.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
as $$
begin
  insert into public.profiles (id) values (new.id) on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
