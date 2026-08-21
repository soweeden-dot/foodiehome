-- Household Inventory's sibling phase · Migration 15 — Cleaning + Home Care
--
-- Uses foodie.cleaning_tasks / cleaning_completions / tracked_components /
-- component_replacements exactly as designed in migrations 04/06/07. Three
-- small additive changes, no redesign of anything existing:
--   1. cleaning_completions.outcome — one append-only stream now covers both
--      completions AND explicit skips (same pattern as fermentation_logs).
--   2. cleaning_tasks.supplies_needed — optional free-text supply hints.
--   3. foodie.maintenance_issues — new table for one-off, non-recurring
--      "apartment needs/issues" that don't fit a recurrence rule (cleaning)
--      or a replace interval (tracked_components).
-- Plus one forward-compatible enum addition (unused this phase, no worker
-- built) so a future reminder_rules row can watch cleaning due-dates the
-- same way component_replacement_due already works.
--
-- "Twice weekly: Wednesday + Sunday" needs NO schema change — it's modeled
-- as two independent recurrence_rules + cleaning_tasks (one per weekday),
-- each with its own completion/skip history. See docs/DECISIONS.md.
--
-- Error codes continue the P000x sequence: P0006 not a household member,
-- P0007 invalid argument, P0008 not found.

create type foodie.cleaning_outcome as enum ('completed', 'skipped');

alter table foodie.cleaning_completions
  add column outcome foodie.cleaning_outcome not null default 'completed';

alter table foodie.cleaning_tasks
  add column supplies_needed text[] not null default '{}';

-- Forward-compatible only: no reminder_rules row references this yet, and no
-- worker consumes it. Structuring for the future combined morning message
-- without building delivery (per explicit instruction).
alter type foodie.reminder_event_type add value if not exists 'cleaning_task_due';

-- ---------------------------------------------------------------------------
-- maintenance_issues — one-off apartment needs/issues. Not recurring (unlike
-- cleaning_tasks) and not interval-based (unlike tracked_components); a
-- reported issue that gets resolved once, not on a schedule.
-- ---------------------------------------------------------------------------
create type foodie.maintenance_issue_status as enum ('open', 'in_progress', 'resolved');

create table foodie.maintenance_issues (
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references foodie.households (id) on delete cascade,
  title         text not null,
  area          text,
  description   text,
  status        foodie.maintenance_issue_status not null default 'open',
  reported_by   uuid references foodie.profiles (id) on delete set null,
  reported_at   timestamptz not null default now(),
  resolved_at   timestamptz,
  notes         text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);

create index idx_maintenance_issues_household
  on foodie.maintenance_issues (household_id, status) where deleted_at is null;

create trigger trg_maintenance_issues_updated_at
  before update on foodie.maintenance_issues
  for each row execute function foodie.set_updated_at();

create trigger trg_audit_maintenance_issues
  after insert or update or delete on foodie.maintenance_issues
  for each row execute function foodie.log_record_history();

alter table foodie.maintenance_issues enable row level security;

create policy maintenance_issues_member_all on foodie.maintenance_issues
  for all using (foodie.is_household_member(household_id))
  with check (foodie.is_household_member(household_id));

-- ---------------------------------------------------------------------------
-- Agent write RPCs — the ONLY write paths the agent tool executor uses for
-- cleaning/filters/maintenance (see docs/FOODIE.md). Same SECURITY INVOKER +
-- validated + app.action_source='foodie' pattern as migrations 13/14.
-- ---------------------------------------------------------------------------

create or replace function foodie.foodie_complete_cleaning_task(
  p_household uuid,
  p_task_id   uuid,
  p_notes     text default null
)
returns foodie.cleaning_completions
language plpgsql
as $$
declare
  task   foodie.cleaning_tasks;
  result foodie.cleaning_completions;
begin
  if not foodie.is_household_member(p_household) then
    raise exception 'not a household member' using errcode = 'P0006';
  end if;

  select * into task
  from foodie.cleaning_tasks
  where id = p_task_id and household_id = p_household and deleted_at is null;
  if task.id is null then
    raise exception 'cleaning task not found' using errcode = 'P0008';
  end if;

  perform set_config('app.action_source', 'foodie', true);

  insert into foodie.cleaning_completions
    (household_id, task_id, completed_by, outcome, checklist_snapshot, notes)
  values
    (p_household, p_task_id, auth.uid(), 'completed', task.checklist,
     nullif(trim(coalesce(p_notes, '')), ''))
  returning * into result;

  return result;
end;
$$;

create or replace function foodie.foodie_skip_cleaning_task(
  p_household uuid,
  p_task_id   uuid,
  p_reason    text default null
)
returns foodie.cleaning_completions
language plpgsql
as $$
declare
  task   foodie.cleaning_tasks;
  result foodie.cleaning_completions;
begin
  if not foodie.is_household_member(p_household) then
    raise exception 'not a household member' using errcode = 'P0006';
  end if;

  select * into task
  from foodie.cleaning_tasks
  where id = p_task_id and household_id = p_household and deleted_at is null;
  if task.id is null then
    raise exception 'cleaning task not found' using errcode = 'P0008';
  end if;

  perform set_config('app.action_source', 'foodie', true);

  insert into foodie.cleaning_completions
    (household_id, task_id, completed_by, outcome, notes)
  values
    (p_household, p_task_id, auth.uid(), 'skipped',
     nullif(trim(coalesce(p_reason, '')), ''))
  returning * into result;

  return result;
end;
$$;

-- Replacing a filter/component: history row + decrement spares (floor 0).
create or replace function foodie.foodie_log_filter_replacement(
  p_household   uuid,
  p_component_id uuid,
  p_notes       text default null
)
returns foodie.component_replacements
language plpgsql
as $$
declare
  component foodie.tracked_components;
  result    foodie.component_replacements;
begin
  if not foodie.is_household_member(p_household) then
    raise exception 'not a household member' using errcode = 'P0006';
  end if;

  select * into component
  from foodie.tracked_components
  where id = p_component_id and household_id = p_household and deleted_at is null;
  if component.id is null then
    raise exception 'tracked component not found' using errcode = 'P0008';
  end if;

  perform set_config('app.action_source', 'foodie', true);

  insert into foodie.component_replacements
    (household_id, component_id, replaced_by, notes)
  values
    (p_household, p_component_id, auth.uid(), nullif(trim(coalesce(p_notes, '')), ''))
  returning * into result;

  update foodie.tracked_components
     set spares_count = greatest(spares_count - 1, 0)
   where id = p_component_id;

  return result;
end;
$$;

create or replace function foodie.foodie_report_maintenance_issue(
  p_household   uuid,
  p_title       text,
  p_area        text default null,
  p_description text default null
)
returns foodie.maintenance_issues
language plpgsql
as $$
declare
  result foodie.maintenance_issues;
begin
  if not foodie.is_household_member(p_household) then
    raise exception 'not a household member' using errcode = 'P0006';
  end if;
  if p_title is null or length(trim(p_title)) = 0 or length(p_title) > 200 then
    raise exception 'invalid issue title' using errcode = 'P0007';
  end if;

  perform set_config('app.action_source', 'foodie', true);

  insert into foodie.maintenance_issues
    (household_id, title, area, description, reported_by)
  values
    (p_household, trim(p_title), nullif(trim(coalesce(p_area, '')), ''),
     nullif(trim(coalesce(p_description, '')), ''), auth.uid())
  returning * into result;

  return result;
end;
$$;

create or replace function foodie.foodie_resolve_maintenance_issue(
  p_household uuid,
  p_issue_id  uuid,
  p_notes     text default null
)
returns foodie.maintenance_issues
language plpgsql
as $$
declare
  result foodie.maintenance_issues;
begin
  if not foodie.is_household_member(p_household) then
    raise exception 'not a household member' using errcode = 'P0006';
  end if;

  perform set_config('app.action_source', 'foodie', true);

  update foodie.maintenance_issues set
    status      = 'resolved',
    resolved_at = now(),
    notes       = coalesce(nullif(trim(p_notes), ''), notes)
  where id = p_issue_id
    and household_id = p_household
    and deleted_at is null
  returning * into result;

  if result is null then
    raise exception 'maintenance issue not found' using errcode = 'P0008';
  end if;

  return result;
end;
$$;

revoke execute on function foodie.foodie_complete_cleaning_task(uuid, uuid, text) from public;
revoke execute on function foodie.foodie_skip_cleaning_task(uuid, uuid, text) from public;
revoke execute on function foodie.foodie_log_filter_replacement(uuid, uuid, text) from public;
revoke execute on function foodie.foodie_report_maintenance_issue(uuid, text, text, text) from public;
revoke execute on function foodie.foodie_resolve_maintenance_issue(uuid, uuid, text) from public;
grant execute on function foodie.foodie_complete_cleaning_task(uuid, uuid, text) to authenticated;
grant execute on function foodie.foodie_skip_cleaning_task(uuid, uuid, text) to authenticated;
grant execute on function foodie.foodie_log_filter_replacement(uuid, uuid, text) to authenticated;
grant execute on function foodie.foodie_report_maintenance_issue(uuid, text, text, text) to authenticated;
grant execute on function foodie.foodie_resolve_maintenance_issue(uuid, uuid, text) to authenticated;
