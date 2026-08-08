-- Stream 1 · Migration 06 — home care: non-daily cleaning & maintenance
--
-- Tasks are rule + completion-history. Next-due is COMPUTED from the last
-- completion and the recurrence rule — occurrence rows are never
-- pre-generated.

create table foodie.cleaning_tasks (
  id                 uuid primary key default gen_random_uuid(),
  household_id       uuid not null references foodie.households (id) on delete cascade,
  name               text not null,
  area               text,                       -- room / zone, free text
  -- Ordered checklist template: [{"text": "wipe shelves"}, ...]
  checklist          jsonb,
  recurrence_rule_id uuid references foodie.recurrence_rules (id) on delete set null,
  assigned_user_id   uuid references foodie.profiles (id) on delete set null,
  is_active          boolean not null default true,
  notes              text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  deleted_at         timestamptz
);

create index idx_cleaning_tasks_household
  on foodie.cleaning_tasks (household_id) where deleted_at is null;
create index idx_cleaning_tasks_recurrence on foodie.cleaning_tasks (recurrence_rule_id);

create table foodie.cleaning_completions (
  id                 uuid primary key default gen_random_uuid(),
  household_id       uuid not null references foodie.households (id) on delete cascade,
  task_id            uuid not null references foodie.cleaning_tasks (id) on delete cascade,
  completed_at       timestamptz not null default now(),
  completed_by       uuid references foodie.profiles (id) on delete set null,
  -- Snapshot of the checklist as completed (checked states included), so the
  -- history stays true even if the task's template changes later.
  checklist_snapshot jsonb,
  notes              text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create index idx_cleaning_completions_task
  on foodie.cleaning_completions (task_id, completed_at desc);

create trigger trg_cleaning_tasks_updated_at       before update on foodie.cleaning_tasks       for each row execute function foodie.set_updated_at();
create trigger trg_cleaning_completions_updated_at before update on foodie.cleaning_completions for each row execute function foodie.set_updated_at();

alter table foodie.cleaning_tasks       enable row level security;
alter table foodie.cleaning_completions enable row level security;

create policy cleaning_tasks_member_all on foodie.cleaning_tasks
  for all using (foodie.is_household_member(household_id)) with check (foodie.is_household_member(household_id));
create policy cleaning_completions_member_all on foodie.cleaning_completions
  for all using (foodie.is_household_member(household_id)) with check (foodie.is_household_member(household_id));
