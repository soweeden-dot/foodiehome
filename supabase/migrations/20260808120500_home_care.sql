-- Stream 1 · Migration 06 — home care: non-daily cleaning & maintenance
--
-- Tasks are rule + completion-history. Next-due is COMPUTED from the last
-- completion and the recurrence rule — occurrence rows are never
-- pre-generated.

create table public.cleaning_tasks (
  id                 uuid primary key default gen_random_uuid(),
  household_id       uuid not null references public.households (id) on delete cascade,
  name               text not null,
  area               text,                       -- room / zone, free text
  -- Ordered checklist template: [{"text": "wipe shelves"}, ...]
  checklist          jsonb,
  recurrence_rule_id uuid references public.recurrence_rules (id) on delete set null,
  assigned_user_id   uuid references public.profiles (id) on delete set null,
  is_active          boolean not null default true,
  notes              text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  deleted_at         timestamptz
);

create index idx_cleaning_tasks_household
  on public.cleaning_tasks (household_id) where deleted_at is null;
create index idx_cleaning_tasks_recurrence on public.cleaning_tasks (recurrence_rule_id);

create table public.cleaning_completions (
  id                 uuid primary key default gen_random_uuid(),
  household_id       uuid not null references public.households (id) on delete cascade,
  task_id            uuid not null references public.cleaning_tasks (id) on delete cascade,
  completed_at       timestamptz not null default now(),
  completed_by       uuid references public.profiles (id) on delete set null,
  -- Snapshot of the checklist as completed (checked states included), so the
  -- history stays true even if the task's template changes later.
  checklist_snapshot jsonb,
  notes              text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create index idx_cleaning_completions_task
  on public.cleaning_completions (task_id, completed_at desc);

create trigger trg_cleaning_tasks_updated_at       before update on public.cleaning_tasks       for each row execute function public.set_updated_at();
create trigger trg_cleaning_completions_updated_at before update on public.cleaning_completions for each row execute function public.set_updated_at();

alter table public.cleaning_tasks       enable row level security;
alter table public.cleaning_completions enable row level security;

create policy cleaning_tasks_member_all on public.cleaning_tasks
  for all using (public.is_household_member(household_id)) with check (public.is_household_member(household_id));
create policy cleaning_completions_member_all on public.cleaning_completions
  for all using (public.is_household_member(household_id)) with check (public.is_household_member(household_id));
