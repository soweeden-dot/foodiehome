-- Stream 1 · Migration 07 — assets: tracked components (filters) &
-- household supplies
--
-- "Filters" are modeled as the general tracked_components so any future
-- replaceable (vacuum parts, smoke-detector batteries, water-pitcher
-- cartridges) needs zero schema work. Replacement history is append-only;
-- next-due is COMPUTED (latest replacement, else installed_on, plus
-- replace_interval_days).

create type public.supply_tracking_mode as enum ('count', 'level');

create table public.tracked_components (
  id                    uuid primary key default gen_random_uuid(),
  household_id          uuid not null references public.households (id) on delete cascade,
  kind                  text not null default 'filter',  -- filter|battery|cartridge|... free text
  system_name           text not null,          -- "Kitchen fridge", "Bedroom air purifier"
  component_name        text not null,          -- "Water filter"
  brand                 text,
  model                 text,
  installed_on          date,
  replace_interval_days integer check (replace_interval_days > 0),
  spares_count          integer not null default 0 check (spares_count >= 0),
  product_url           text,
  notes                 text,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  deleted_at            timestamptz
);

create index idx_tracked_components_household
  on public.tracked_components (household_id) where deleted_at is null;

create table public.component_replacements (
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references public.households (id) on delete cascade,
  component_id  uuid not null references public.tracked_components (id) on delete cascade,
  replaced_on   date not null default current_date,
  replaced_by   uuid references public.profiles (id) on delete set null,
  notes         text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index idx_component_replacements_component
  on public.component_replacements (component_id, replaced_on desc);

-- ---------------------------------------------------------------------------
-- household_supplies — consumables (detergent, sponges, paper products...).
-- Countable ("23 dishwasher tablets") or approximate (full/good/low/...).
-- ---------------------------------------------------------------------------
create table public.household_supplies (
  id                uuid primary key default gen_random_uuid(),
  household_id      uuid not null references public.households (id) on delete cascade,
  name              text not null,
  category          text,                        -- laundry|dishes|paper|... free text
  tracking_mode     public.supply_tracking_mode not null default 'level',
  count             integer check (count >= 0),
  level             public.supply_level,
  -- When count drops to/below this, the supply counts as "low" (count mode).
  restock_threshold integer check (restock_threshold >= 0),
  preferred_product text,
  notes             text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz,
  unique (household_id, name)
);

create trigger trg_tracked_components_updated_at     before update on public.tracked_components     for each row execute function public.set_updated_at();
create trigger trg_component_replacements_updated_at before update on public.component_replacements for each row execute function public.set_updated_at();
create trigger trg_household_supplies_updated_at     before update on public.household_supplies     for each row execute function public.set_updated_at();

alter table public.tracked_components     enable row level security;
alter table public.component_replacements enable row level security;
alter table public.household_supplies     enable row level security;

create policy tracked_components_member_all on public.tracked_components
  for all using (public.is_household_member(household_id)) with check (public.is_household_member(household_id));
create policy component_replacements_member_all on public.component_replacements
  for all using (public.is_household_member(household_id)) with check (public.is_household_member(household_id));
create policy household_supplies_member_all on public.household_supplies
  for all using (public.is_household_member(household_id)) with check (public.is_household_member(household_id));
