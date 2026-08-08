-- Stream 1 · Migration 08 — preferences
--
-- household_preferences is a namespaced key/value store: household-wide when
-- user_id is null, per-member when set. Typed columns are deliberately
-- avoided — preference shapes will evolve constantly and none are queried
-- relationally. Foodie's curated memory store (Stream 3) is separate; this
-- table is for app settings and explicit user preferences.

create table foodie.household_preferences (
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references foodie.households (id) on delete cascade,
  user_id       uuid references foodie.profiles (id) on delete cascade,
  key           text not null,                   -- namespaced: "food.dislikes", "dashboard.cards"
  value         jsonb not null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique nulls not distinct (household_id, user_id, key)
);

create index idx_household_preferences_household
  on foodie.household_preferences (household_id, key);

create trigger trg_household_preferences_updated_at
  before update on foodie.household_preferences
  for each row execute function foodie.set_updated_at();

alter table foodie.household_preferences enable row level security;

create policy household_preferences_member_all on foodie.household_preferences
  for all using (foodie.is_household_member(household_id))
  with check (foodie.is_household_member(household_id));
