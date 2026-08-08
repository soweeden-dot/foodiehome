-- Stream 1 · Migration 05 — fermentation lab
--
-- Projects are live processes, not recipes. Logs are one append-only stream:
-- log_type + structured payload distinguishes feedings, turnings,
-- observations, temperature checks, and stage changes.

create type public.fermentation_status as enum
  ('planned', 'active', 'paused', 'completed', 'discarded');

create type public.fermentation_log_type as enum
  ('observation', 'feeding', 'turning', 'temperature', 'stage_change', 'ai_observation');

create type public.log_author as enum ('user', 'foodie');

create table public.fermentation_projects (
  id             uuid primary key default gen_random_uuid(),
  household_id   uuid not null references public.households (id) on delete cascade,
  project_type   text not null,                  -- 'cacao', 'sourdough_starter', ...
  name           text not null,
  status         public.fermentation_status not null default 'active',
  started_at     timestamptz not null default now(),
  ended_at       timestamptz,
  current_stage  text,
  -- Target parameters: temps, ratios, expected stage durations, flour type...
  -- Varies wildly by fermentation type, hence jsonb.
  target_params  jsonb,
  next_check_at  timestamptz,                    -- drives event reminders later
  safety_notes   text,
  notes          text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz
);

create index idx_fermentation_projects_next_check
  on public.fermentation_projects (household_id, next_check_at)
  where deleted_at is null and status = 'active';

create table public.fermentation_logs (
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references public.households (id) on delete cascade,
  project_id    uuid not null references public.fermentation_projects (id) on delete cascade,
  logged_at     timestamptz not null default now(),
  log_type      public.fermentation_log_type not null,
  -- Structured measurements: {"temp_c": 31}, {"starter_g": 10, "flour_g": 50,
  -- "water_g": 50, "flour_type": "rye"}, {"stage": "day 3"}...
  payload       jsonb,
  -- Free-text observation: smell, appearance, texture, anything.
  notes         text,
  author        public.log_author not null default 'user',
  created_by    uuid references public.profiles (id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index idx_fermentation_logs_project
  on public.fermentation_logs (project_id, logged_at);

create table public.fermentation_photos (
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references public.households (id) on delete cascade,
  project_id    uuid not null references public.fermentation_projects (id) on delete cascade,
  log_id        uuid references public.fermentation_logs (id) on delete set null,
  storage_path  text not null,                   -- Supabase Storage; bytes never in Postgres
  taken_at      timestamptz not null default now(),
  caption       text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index idx_fermentation_photos_project
  on public.fermentation_photos (project_id, taken_at);

create trigger trg_fermentation_projects_updated_at before update on public.fermentation_projects for each row execute function public.set_updated_at();
create trigger trg_fermentation_logs_updated_at     before update on public.fermentation_logs     for each row execute function public.set_updated_at();
create trigger trg_fermentation_photos_updated_at   before update on public.fermentation_photos   for each row execute function public.set_updated_at();

alter table public.fermentation_projects enable row level security;
alter table public.fermentation_logs     enable row level security;
alter table public.fermentation_photos   enable row level security;

create policy fermentation_projects_member_all on public.fermentation_projects
  for all using (public.is_household_member(household_id)) with check (public.is_household_member(household_id));
-- Logs/photos: members may insert, read, correct, and delete their household's
-- entries (humans make typos); durable immutability lives in record_history.
create policy fermentation_logs_member_all on public.fermentation_logs
  for all using (public.is_household_member(household_id)) with check (public.is_household_member(household_id));
create policy fermentation_photos_member_all on public.fermentation_photos
  for all using (public.is_household_member(household_id)) with check (public.is_household_member(household_id));
