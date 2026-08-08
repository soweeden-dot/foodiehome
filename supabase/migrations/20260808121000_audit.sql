-- Stream 1 · Migration 11 — data-level audit log (record_history)
--
-- Trigger-based row diffs on the important mutable domain tables, capturing
-- user, agent, and sync writes alike. Append-only: clients can read their
-- household's history but never insert/update/delete it — the trigger
-- function is SECURITY DEFINER and is the only writer.
--
-- Intent-level auditing ("Foodie removed Friday dinner because you said...")
-- is agent_actions; this table answers "why does the data look like this".

create table foodie.record_history (
  id            bigint generated always as identity primary key,
  household_id  uuid,                            -- null only for non-household tables
  table_name    text not null,
  record_id     uuid not null,
  op            text not null check (op in ('INSERT', 'UPDATE', 'DELETE')),
  changed_by    uuid,                            -- auth.uid() when available; null for service jobs
  -- INSERT: {"new": {...}}   DELETE: {"old": {...}}
  -- UPDATE: {"changed": {"col": {"old": ..., "new": ...}, ...}}
  diff          jsonb not null,
  created_at    timestamptz not null default now()
);

create index idx_record_history_record
  on foodie.record_history (table_name, record_id, created_at desc);
create index idx_record_history_household
  on foodie.record_history (household_id, created_at desc);

create or replace function foodie.log_record_history()
returns trigger
language plpgsql
security definer
set search_path = foodie, pg_temp
as $$
declare
  hh      uuid;
  rec_id  uuid;
  d       jsonb;
begin
  if tg_op = 'INSERT' then
    hh     := (to_jsonb(new) ->> 'household_id')::uuid;
    rec_id := new.id;
    d      := jsonb_build_object('new', to_jsonb(new));
  elsif tg_op = 'UPDATE' then
    hh     := (to_jsonb(new) ->> 'household_id')::uuid;
    rec_id := new.id;
    select jsonb_build_object(
             'changed',
             coalesce(jsonb_object_agg(o.k, jsonb_build_object('old', o.v, 'new', n.v)), '{}'::jsonb))
      into d
      from jsonb_each(to_jsonb(old)) as o(k, v)
      join jsonb_each(to_jsonb(new)) as n(k, v) on n.k = o.k
     where o.v is distinct from n.v
       and o.k <> 'updated_at';
    -- Skip no-op updates (only updated_at churned).
    if d -> 'changed' = '{}'::jsonb then
      return new;
    end if;
  else
    hh     := (to_jsonb(old) ->> 'household_id')::uuid;
    rec_id := old.id;
    d      := jsonb_build_object('old', to_jsonb(old));
  end if;

  insert into foodie.record_history (household_id, table_name, record_id, op, changed_by, diff)
  values (hh, tg_table_name, rec_id, tg_op, auth.uid(), d);

  return coalesce(new, old);
end;
$$;

-- Attach to the significant mutable domain tables. Deliberately NOT attached
-- to: append-only tables (their inserts are their own history), agent
-- message/notification traffic (volume without value), devices/profiles.
create trigger trg_audit_inventory_locations   after insert or update or delete on foodie.inventory_locations   for each row execute function foodie.log_record_history();
create trigger trg_audit_food_items            after insert or update or delete on foodie.food_items            for each row execute function foodie.log_record_history();
create trigger trg_audit_inventory_items       after insert or update or delete on foodie.inventory_items       for each row execute function foodie.log_record_history();
create trigger trg_audit_recipes               after insert or update or delete on foodie.recipes               for each row execute function foodie.log_record_history();
create trigger trg_audit_recipe_steps          after insert or update or delete on foodie.recipe_steps          for each row execute function foodie.log_record_history();
create trigger trg_audit_recipe_ingredients    after insert or update or delete on foodie.recipe_ingredients    for each row execute function foodie.log_record_history();
create trigger trg_audit_meal_plans            after insert or update or delete on foodie.meal_plans            for each row execute function foodie.log_record_history();
create trigger trg_audit_meal_plan_entries     after insert or update or delete on foodie.meal_plan_entries     for each row execute function foodie.log_record_history();
create trigger trg_audit_grocery_lists         after insert or update or delete on foodie.grocery_lists         for each row execute function foodie.log_record_history();
create trigger trg_audit_grocery_items         after insert or update or delete on foodie.grocery_items         for each row execute function foodie.log_record_history();
create trigger trg_audit_cleaning_tasks        after insert or update or delete on foodie.cleaning_tasks        for each row execute function foodie.log_record_history();
create trigger trg_audit_tracked_components    after insert or update or delete on foodie.tracked_components    for each row execute function foodie.log_record_history();
create trigger trg_audit_household_supplies    after insert or update or delete on foodie.household_supplies    for each row execute function foodie.log_record_history();
create trigger trg_audit_fermentation_projects after insert or update or delete on foodie.fermentation_projects for each row execute function foodie.log_record_history();
create trigger trg_audit_fermentation_logs     after insert or update or delete on foodie.fermentation_logs     for each row execute function foodie.log_record_history();
create trigger trg_audit_recurrence_rules      after insert or update or delete on foodie.recurrence_rules      for each row execute function foodie.log_record_history();
create trigger trg_audit_reminder_rules        after insert or update or delete on foodie.reminder_rules        for each row execute function foodie.log_record_history();
create trigger trg_audit_household_preferences after insert or update or delete on foodie.household_preferences for each row execute function foodie.log_record_history();

alter table foodie.record_history enable row level security;

create policy record_history_member_select on foodie.record_history
  for select using (household_id is not null and foodie.is_household_member(household_id));
-- No insert/update/delete policies: append-only, written only by the
-- SECURITY DEFINER trigger (and service role).
