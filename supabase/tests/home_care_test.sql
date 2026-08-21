-- Cleaning + Home Care phase test — cleaning completion/skip, filter
-- replacement, maintenance issues, provenance, household scope. Runs after
-- inventory_test.sql; alice is admin of household 1000...01, bob is a
-- member, carol left the household earlier.

\set ON_ERROR_STOP on

set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';

-- Set up a recurrence rule + cleaning task (Sunday-anchored weekly).
insert into foodie.recurrence_rules (id, household_id, interval_unit, interval_count, weekday)
  values ('60000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'week', 1, 0);
insert into foodie.cleaning_tasks (id, household_id, name, area, recurrence_rule_id, assigned_user_id, supplies_needed)
  values ('61000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001',
          'Clean bathroom', 'Bathroom', '60000000-0000-0000-0000-000000000001',
          '00000000-0000-0000-0000-00000000000a', array['glass cleaner', 'sponge']);

-- Complete it: audited, provenance foodie, checklist snapshot copied (null here).
select foodie.foodie_complete_cleaning_task(
  '10000000-0000-0000-0000-000000000001', '61000000-0000-0000-0000-000000000001', 'done, sparkling');
do $$ begin
  if not exists (select 1 from foodie.cleaning_completions
                 where task_id = '61000000-0000-0000-0000-000000000001'
                   and outcome = 'completed' and notes = 'done, sparkling') then
    raise exception 'completion was not recorded correctly';
  end if;
  if (select source from foodie.record_history
       where table_name = 'cleaning_completions' order by id desc limit 1)::text <> 'foodie' then
    raise exception 'cleaning completion not attributed to foodie';
  end if;
end $$;

-- Skip a (second) task: separate outcome, separate history entry.
insert into foodie.cleaning_tasks (id, household_id, name, area, recurrence_rule_id)
  values ('61000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001',
          'Vacuum living room', 'Living room', '60000000-0000-0000-0000-000000000001');
select foodie.foodie_skip_cleaning_task(
  '10000000-0000-0000-0000-000000000001', '61000000-0000-0000-0000-000000000002', 'too tired');
do $$ begin
  if not exists (select 1 from foodie.cleaning_completions
                 where task_id = '61000000-0000-0000-0000-000000000002'
                   and outcome = 'skipped' and notes = 'too tired') then
    raise exception 'skip was not recorded correctly';
  end if;
  -- Skipping does not create a "completed" row for this task.
  if exists (select 1 from foodie.cleaning_completions
             where task_id = '61000000-0000-0000-0000-000000000002' and outcome = 'completed') then
    raise exception 'skip incorrectly also recorded a completion';
  end if;
end $$;

-- Completing/skipping a nonexistent task raises P0008.
do $$ begin
  begin
    perform foodie.foodie_complete_cleaning_task(
      '10000000-0000-0000-0000-000000000001', gen_random_uuid(), null);
    raise exception 'completing a missing task was accepted';
  exception when sqlstate 'P0008' then null;
  end;
end $$;

-- Filter replacement: history row + spares decremented, floored at 0.
insert into foodie.tracked_components (id, household_id, system_name, component_name, spares_count)
  values ('62000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001',
          'Kitchen fridge', 'Water filter', 1);
select foodie.foodie_log_filter_replacement(
  '10000000-0000-0000-0000-000000000001', '62000000-0000-0000-0000-000000000001', 'new cartridge');
do $$ begin
  if not exists (select 1 from foodie.component_replacements
                 where component_id = '62000000-0000-0000-0000-000000000001' and notes = 'new cartridge') then
    raise exception 'replacement was not recorded';
  end if;
  if (select spares_count from foodie.tracked_components
      where id = '62000000-0000-0000-0000-000000000001') <> 0 then
    raise exception 'spares_count was not decremented';
  end if;
  if (select source from foodie.record_history
       where table_name = 'component_replacements' order by id desc limit 1)::text <> 'foodie' then
    raise exception 'filter replacement not attributed to foodie';
  end if;
end $$;

-- Second replacement: spares floors at 0, does not go negative.
select foodie.foodie_log_filter_replacement(
  '10000000-0000-0000-0000-000000000001', '62000000-0000-0000-0000-000000000001', null);
do $$ begin
  if (select spares_count from foodie.tracked_components
      where id = '62000000-0000-0000-0000-000000000001') <> 0 then
    raise exception 'spares_count went negative';
  end if;
end $$;

-- Maintenance issues: report, then resolve.
select foodie.foodie_report_maintenance_issue(
  '10000000-0000-0000-0000-000000000001', 'Leaky faucet', 'Kitchen', 'drips constantly');
do $$ begin
  if not exists (select 1 from foodie.maintenance_issues
                 where title = 'Leaky faucet' and status = 'open') then
    raise exception 'maintenance issue was not reported';
  end if;
  if (select source from foodie.record_history
       where table_name = 'maintenance_issues' and op = 'INSERT'
       order by id desc limit 1)::text <> 'foodie' then
    raise exception 'maintenance issue insert not attributed to foodie';
  end if;
end $$;

do $$
declare
  issue_id uuid;
begin
  select id into issue_id from foodie.maintenance_issues where title = 'Leaky faucet';
  perform foodie.foodie_resolve_maintenance_issue(
    '10000000-0000-0000-0000-000000000001', issue_id, 'plumber fixed it');
  if (select status from foodie.maintenance_issues where id = issue_id) <> 'resolved' then
    raise exception 'issue was not marked resolved';
  end if;
  if (select resolved_at from foodie.maintenance_issues where id = issue_id) is null then
    raise exception 'resolved_at was not set';
  end if;
end $$;

-- Resolving a nonexistent issue raises P0008.
do $$ begin
  begin
    perform foodie.foodie_resolve_maintenance_issue(
      '10000000-0000-0000-0000-000000000001', gen_random_uuid(), null);
    raise exception 'resolving a missing issue was accepted';
  exception when sqlstate 'P0008' then null;
  end;
end $$;

-- Empty title rejected.
do $$ begin
  begin
    perform foodie.foodie_report_maintenance_issue(
      '10000000-0000-0000-0000-000000000001', '   ', null, null);
    raise exception 'empty issue title was accepted';
  exception when sqlstate 'P0007' then null;
  end;
end $$;

-- Household scope: carol (not a member) is rejected and sees nothing.
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000c';
do $$ begin
  begin
    perform foodie.foodie_report_maintenance_issue(
      '10000000-0000-0000-0000-000000000001', 'intruder issue', null, null);
    raise exception 'non-member was able to report a maintenance issue';
  exception when sqlstate 'P0006' then null;
  end;
  if (select count(*) from foodie.cleaning_tasks) <> 0 then
    raise exception 'non-member can read cleaning tasks';
  end if;
  if (select count(*) from foodie.maintenance_issues) <> 0 then
    raise exception 'non-member can read maintenance issues';
  end if;
end $$;

reset role;
select 'HOME CARE TEST PASSED' as result;
