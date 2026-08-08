-- Stream 1 · Migration 03 — shared recurrence rules
--
-- One recurrence vocabulary reused by everything that repeats (cleaning
-- tasks, reminder rules; future: anything else). Rules are descriptions, not
-- schedules-of-records: occurrences are always COMPUTED (last completion /
-- last fire + rule), never pre-generated as rows.

create type public.interval_unit as enum ('day', 'week', 'month', 'year');

create table public.recurrence_rules (
  id             uuid primary key default gen_random_uuid(),
  household_id   uuid not null references public.households (id) on delete cascade,
  -- "every <interval_count> <interval_unit>", e.g. every 2 week = biweekly,
  -- every 3 month = quarterly, every 6 month = biannually.
  interval_unit  public.interval_unit not null,
  interval_count integer not null default 1 check (interval_count >= 1),
  -- Preferred weekday for week-based rules (0 = Sunday .. 6 = Saturday).
  weekday        smallint check (weekday between 0 and 6),
  -- Preferred day-of-month for month/year-based rules.
  month_day      smallint check (month_day between 1 and 31),
  -- Month for year-based rules (1..12).
  month          smallint check (month between 1 and 12),
  -- Preferred local time-of-day (interpreted in the household's timezone).
  time_of_day    time,
  -- Anchor for computing the cycle when there is no completion history yet
  -- (e.g. quarterly starting from this date).
  anchor_date    date,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create index idx_recurrence_rules_household on public.recurrence_rules (household_id);

create trigger trg_recurrence_rules_updated_at
  before update on public.recurrence_rules
  for each row execute function public.set_updated_at();

alter table public.recurrence_rules enable row level security;

create policy recurrence_rules_member_all on public.recurrence_rules
  for all using (public.is_household_member(household_id))
  with check (public.is_household_member(household_id));
