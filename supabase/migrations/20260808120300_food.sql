-- Stream 1 · Migration 04 — food domain: catalog, inventory, recipes,
-- meal plans, grocery
--
-- food_items is the hub identity: recipes, inventory, and grocery items all
-- reference the same catalog row, which is what makes "we used the last
-- onion" and grocery generation possible. Free-text fallbacks are allowed
-- everywhere so data entry never fights the user.

-- Where a record came from — shared by inventory and grocery.
create type foodie.entry_source as enum
  ('manual', 'scan', 'agent', 'meal_plan', 'low_supply', 'import');

-- Approximate stock level — shared by inventory and household supplies.
create type foodie.supply_level as enum
  ('full', 'good', 'low', 'almost_empty', 'out');

create type foodie.meal_slot as enum ('breakfast', 'lunch', 'dinner', 'snack', 'prep');
create type foodie.meal_entry_status as enum ('planned', 'prepped', 'cooked', 'skipped');

-- ---------------------------------------------------------------------------
-- inventory_locations — pantry / fridge / freezer / user-defined.
-- ---------------------------------------------------------------------------
create table foodie.inventory_locations (
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references foodie.households (id) on delete cascade,
  name          text not null,
  kind          text not null default 'other',   -- pantry|fridge|freezer|other; free text on purpose
  position      integer not null default 0,      -- display ordering
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz,
  unique (household_id, name)
);

-- ---------------------------------------------------------------------------
-- food_items — the household's food catalog (identity, not stock).
-- ---------------------------------------------------------------------------
create table foodie.food_items (
  id                      uuid primary key default gen_random_uuid(),
  household_id            uuid not null references foodie.households (id) on delete cascade,
  name                    text not null,
  category                text,                  -- produce|dairy|... free text, app suggests
  default_unit            text,                  -- g|ml|piece|... free text
  default_shelf_life_days integer check (default_shelf_life_days > 0),
  default_location_id     uuid references foodie.inventory_locations (id) on delete set null,
  aliases                 text[] not null default '{}',   -- "scallion" -> "green onion"
  notes                   text,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  deleted_at              timestamptz,
  unique (household_id, name)
);

-- ---------------------------------------------------------------------------
-- inventory_items — stock on hand ("inventory entries").
-- Either a precise quantity+unit or an approximate level; both optional
-- because "we have some rice" is valid household data.
-- ---------------------------------------------------------------------------
create table foodie.inventory_items (
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references foodie.households (id) on delete cascade,
  food_item_id  uuid references foodie.food_items (id) on delete set null,
  name          text,                            -- free-text fallback when not cataloged
  location_id   uuid references foodie.inventory_locations (id) on delete set null,
  quantity      numeric(12, 3) check (quantity >= 0),
  unit          text,
  level         foodie.supply_level,
  expires_on    date,
  opened_on     date,
  source        foodie.entry_source not null default 'manual',
  notes         text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz,
  check (food_item_id is not null or name is not null)
);

create index idx_inventory_items_food_item on foodie.inventory_items (food_item_id);
create index idx_inventory_items_expiry
  on foodie.inventory_items (household_id, expires_on)
  where deleted_at is null and expires_on is not null;

-- ---------------------------------------------------------------------------
-- recipes + structured steps + ingredients
-- ---------------------------------------------------------------------------
create table foodie.recipes (
  id                uuid primary key default gen_random_uuid(),
  household_id      uuid not null references foodie.households (id) on delete cascade,
  title             text not null,
  description       text,
  servings          numeric(6, 2) check (servings > 0),
  prep_minutes      integer check (prep_minutes >= 0),
  cook_minutes      integer check (cook_minutes >= 0),
  source_url        text,
  image_path        text,                        -- Supabase Storage path
  tags              text[] not null default '{}',
  -- Per-serving nutrition; loosely structured on purpose (calories, protein_g,
  -- carbs_g, fat_g, ...). Promoted to columns only if we ever query on it.
  nutrition         jsonb,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz
);

-- Structured steps from day one — required later by Cooking Mode and voice.
create table foodie.recipe_steps (
  id               uuid primary key default gen_random_uuid(),
  household_id     uuid not null references foodie.households (id) on delete cascade,
  recipe_id        uuid not null references foodie.recipes (id) on delete cascade,
  position         integer not null check (position >= 1),
  instruction      text not null,
  duration_seconds integer check (duration_seconds > 0),  -- drives suggested timers
  temperature      text,                                  -- "180°C" / "350°F"; display value
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (recipe_id, position)
);

create index idx_recipe_steps_recipe on foodie.recipe_steps (recipe_id);

create table foodie.recipe_ingredients (
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references foodie.households (id) on delete cascade,
  recipe_id     uuid not null references foodie.recipes (id) on delete cascade,
  food_item_id  uuid references foodie.food_items (id) on delete set null,
  name          text,                            -- free-text fallback
  quantity      numeric(12, 3) check (quantity >= 0),
  unit          text,
  preparation   text,                            -- "diced", "room temperature"
  position      integer not null default 0,
  optional      boolean not null default false,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  check (food_item_id is not null or name is not null)
);

create index idx_recipe_ingredients_recipe on foodie.recipe_ingredients (recipe_id);
create index idx_recipe_ingredients_food_item on foodie.recipe_ingredients (food_item_id);

-- ---------------------------------------------------------------------------
-- meal plans — a date-ranged container with per-slot entries.
-- Per-slot rows (not a week blob) keep sync conflict granularity high.
-- ---------------------------------------------------------------------------
create table foodie.meal_plans (
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references foodie.households (id) on delete cascade,
  name          text,
  start_date    date not null,
  end_date      date not null,
  notes         text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz,
  check (end_date >= start_date)
);

create table foodie.meal_plan_entries (
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references foodie.households (id) on delete cascade,
  meal_plan_id  uuid not null references foodie.meal_plans (id) on delete cascade,
  plan_date     date not null,
  slot          foodie.meal_slot not null,
  recipe_id     uuid references foodie.recipes (id) on delete set null,
  title         text,                            -- "leftovers", "eating out" (no recipe)
  -- Servings per household member, keyed by user id; null = household default.
  servings_by_member jsonb,
  status        foodie.meal_entry_status not null default 'planned',
  notes         text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz,
  check (recipe_id is not null or title is not null)
);

create index idx_meal_plan_entries_plan on foodie.meal_plan_entries (meal_plan_id);
create index idx_meal_plan_entries_date
  on foodie.meal_plan_entries (household_id, plan_date)
  where deleted_at is null;

-- ---------------------------------------------------------------------------
-- grocery lists
-- ---------------------------------------------------------------------------
create table foodie.grocery_lists (
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references foodie.households (id) on delete cascade,
  name          text not null default 'Groceries',
  archived_at   timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);

create table foodie.grocery_items (
  id              uuid primary key default gen_random_uuid(),
  household_id    uuid not null references foodie.households (id) on delete cascade,
  grocery_list_id uuid not null references foodie.grocery_lists (id) on delete cascade,
  food_item_id    uuid references foodie.food_items (id) on delete set null,
  name            text,                          -- free-text fallback
  quantity        numeric(12, 3) check (quantity >= 0),
  unit            text,
  store_section   text,
  source          foodie.entry_source not null default 'manual',
  -- What generated this item (meal_plan_entry id, supply id, ...) so
  -- recalculation can update instead of duplicating.
  source_ref      uuid,
  checked_at      timestamptz,
  checked_by      uuid references foodie.profiles (id) on delete set null,
  notes           text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz,
  check (food_item_id is not null or name is not null)
);

create index idx_grocery_items_list on foodie.grocery_items (grocery_list_id);
create index idx_grocery_items_source_ref on foodie.grocery_items (source_ref)
  where source_ref is not null;

-- ---------------------------------------------------------------------------
-- updated_at triggers
-- ---------------------------------------------------------------------------
create trigger trg_inventory_locations_updated_at before update on foodie.inventory_locations for each row execute function foodie.set_updated_at();
create trigger trg_food_items_updated_at          before update on foodie.food_items          for each row execute function foodie.set_updated_at();
create trigger trg_inventory_items_updated_at     before update on foodie.inventory_items     for each row execute function foodie.set_updated_at();
create trigger trg_recipes_updated_at             before update on foodie.recipes             for each row execute function foodie.set_updated_at();
create trigger trg_recipe_steps_updated_at        before update on foodie.recipe_steps        for each row execute function foodie.set_updated_at();
create trigger trg_recipe_ingredients_updated_at  before update on foodie.recipe_ingredients  for each row execute function foodie.set_updated_at();
create trigger trg_meal_plans_updated_at          before update on foodie.meal_plans          for each row execute function foodie.set_updated_at();
create trigger trg_meal_plan_entries_updated_at   before update on foodie.meal_plan_entries   for each row execute function foodie.set_updated_at();
create trigger trg_grocery_lists_updated_at       before update on foodie.grocery_lists       for each row execute function foodie.set_updated_at();
create trigger trg_grocery_items_updated_at       before update on foodie.grocery_items       for each row execute function foodie.set_updated_at();

-- ---------------------------------------------------------------------------
-- Row Level Security — standard member policy on every table.
-- ---------------------------------------------------------------------------
alter table foodie.inventory_locations enable row level security;
alter table foodie.food_items          enable row level security;
alter table foodie.inventory_items     enable row level security;
alter table foodie.recipes             enable row level security;
alter table foodie.recipe_steps        enable row level security;
alter table foodie.recipe_ingredients  enable row level security;
alter table foodie.meal_plans          enable row level security;
alter table foodie.meal_plan_entries   enable row level security;
alter table foodie.grocery_lists       enable row level security;
alter table foodie.grocery_items       enable row level security;

create policy inventory_locations_member_all on foodie.inventory_locations
  for all using (foodie.is_household_member(household_id)) with check (foodie.is_household_member(household_id));
create policy food_items_member_all on foodie.food_items
  for all using (foodie.is_household_member(household_id)) with check (foodie.is_household_member(household_id));
create policy inventory_items_member_all on foodie.inventory_items
  for all using (foodie.is_household_member(household_id)) with check (foodie.is_household_member(household_id));
create policy recipes_member_all on foodie.recipes
  for all using (foodie.is_household_member(household_id)) with check (foodie.is_household_member(household_id));
create policy recipe_steps_member_all on foodie.recipe_steps
  for all using (foodie.is_household_member(household_id)) with check (foodie.is_household_member(household_id));
create policy recipe_ingredients_member_all on foodie.recipe_ingredients
  for all using (foodie.is_household_member(household_id)) with check (foodie.is_household_member(household_id));
create policy meal_plans_member_all on foodie.meal_plans
  for all using (foodie.is_household_member(household_id)) with check (foodie.is_household_member(household_id));
create policy meal_plan_entries_member_all on foodie.meal_plan_entries
  for all using (foodie.is_household_member(household_id)) with check (foodie.is_household_member(household_id));
create policy grocery_lists_member_all on foodie.grocery_lists
  for all using (foodie.is_household_member(household_id)) with check (foodie.is_household_member(household_id));
create policy grocery_items_member_all on foodie.grocery_items
  for all using (foodie.is_household_member(household_id)) with check (foodie.is_household_member(household_id));
