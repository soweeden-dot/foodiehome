-- Stream 1 · Migration 08 — preferences
--
-- household_preferences is a namespaced key/value store: household-wide when
-- user_id is null, per-member when set. Typed columns are deliberately
-- avoided — preference shapes will evolve constantly and none are queried
-- relationally. Foodie's curated memory store (Stream 3) is separate; this
-- table is for app settings and explicit user preferences.

create table public.household_preferences (
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references public.households (id) on delete cascade,
  user_id       uuid references public.profiles (id) on delete cascade,
  key           text not null,                   -- namespaced: "food.dislikes", "dashboard.cards"
  value         jsonb not null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique nulls not distinct (household_id, user_id, key)
);

create index idx_household_preferences_household
  on public.household_preferences (household_id, key);

create trigger trg_household_preferences_updated_at
  before update on public.household_preferences
  for each row execute function public.set_updated_at();

alter table public.household_preferences enable row level security;

create policy household_preferences_member_all on public.household_preferences
  for all using (public.is_household_member(household_id))
  with check (public.is_household_member(household_id));
