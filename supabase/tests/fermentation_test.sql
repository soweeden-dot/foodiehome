-- Fermentation Tracking phase test — project/log RPCs, sourdough feeding,
-- stage-change history, provenance, household scope. Runs after
-- home_care_test.sql; alice is admin of household 1000...01, bob is a
-- member, carol left the household earlier.

\set ON_ERROR_STOP on

set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';

-- Create a sourdough project: type/state/cadence live in target_params
-- jsonb, no dedicated columns.
select foodie.foodie_create_fermentation_project(
  '10000000-0000-0000-0000-000000000001', 'sourdough_starter', 'Rustic Rye',
  '{"state": "active", "feed_interval_hours": 24, "default_flour_type": "rye"}'::jsonb,
  null, 'kept on the counter');
do $$ begin
  if not exists (select 1 from foodie.fermentation_projects
                 where household_id = '10000000-0000-0000-0000-000000000001'
                   and name = 'Rustic Rye' and project_type = 'sourdough_starter'
                   and status = 'active') then
    raise exception 'sourdough project was not created';
  end if;
  if (select source from foodie.record_history
       where table_name = 'fermentation_projects' and op = 'INSERT'
       order by id desc limit 1)::text <> 'foodie' then
    raise exception 'project insert not attributed to foodie';
  end if;
end $$;

-- Invalid project type/name rejected.
do $$ begin
  begin
    perform foodie.foodie_create_fermentation_project(
      '10000000-0000-0000-0000-000000000001', '', 'Something', null, null, null);
    raise exception 'empty project type was accepted';
  exception when sqlstate 'P0007' then null;
  end;
  begin
    perform foodie.foodie_create_fermentation_project(
      '10000000-0000-0000-0000-000000000001', 'sourdough_starter', '   ', null, null, null);
    raise exception 'empty project name was accepted';
  exception when sqlstate 'P0007' then null;
  end;
end $$;

-- Log a sourdough feeding: raw measurements stored, no hydration/ratio
-- pre-computed into the payload.
do $$
declare
  proj_id uuid;
begin
  select id into proj_id from foodie.fermentation_projects where name = 'Rustic Rye';
  perform foodie.foodie_log_sourdough_feeding(
    '10000000-0000-0000-0000-000000000001', proj_id, 10, 50, 50, 'rye', 5, 'good rise yesterday');

  if not exists (
    select 1 from foodie.fermentation_logs
    where project_id = proj_id and log_type = 'feeding'
      and payload = '{"starter_g": 10, "flour_g": 50, "water_g": 50, "discard_g": 5, "flour_type": "rye"}'::jsonb
      and notes = 'good rise yesterday'
  ) then
    raise exception 'feeding log was not recorded with the expected payload';
  end if;
  if (select author from foodie.fermentation_logs
       where project_id = proj_id and log_type = 'feeding'
       order by created_at desc limit 1)::text <> 'foodie' then
    raise exception 'feeding not attributed to foodie';
  end if;
end $$;

-- Invalid feeding amounts rejected.
do $$
declare
  proj_id uuid;
begin
  select id into proj_id from foodie.fermentation_projects where name = 'Rustic Rye';
  begin
    perform foodie.foodie_log_sourdough_feeding(
      '10000000-0000-0000-0000-000000000001', proj_id, 0, 50, 50, null, null, null);
    raise exception 'zero starter amount was accepted';
  exception when sqlstate 'P0007' then null;
  end;
  begin
    perform foodie.foodie_log_sourdough_feeding(
      '10000000-0000-0000-0000-000000000001', proj_id, 10, -5, 50, null, null, null);
    raise exception 'negative flour amount was accepted';
  exception when sqlstate 'P0007' then null;
  end;
end $$;

-- Feeding a nonexistent project raises P0008.
do $$ begin
  begin
    perform foodie.foodie_log_sourdough_feeding(
      '10000000-0000-0000-0000-000000000001', gen_random_uuid(), 10, 50, 50, null, null, null);
    raise exception 'feeding a missing project was accepted';
  exception when sqlstate 'P0008' then null;
  end;
end $$;

-- Create a cacao project and log generic events (turning/observation) —
-- proves the same log stream serves a non-sourdough type with zero
-- cacao-specific schema.
select foodie.foodie_create_fermentation_project(
  '10000000-0000-0000-0000-000000000001', 'cacao', 'Backyard Cacao Batch 1',
  '{"target_days": 6}'::jsonb, null, null);
do $$
declare
  proj_id uuid;
begin
  select id into proj_id from foodie.fermentation_projects where name = 'Backyard Cacao Batch 1';

  perform foodie.foodie_log_fermentation_event(
    '10000000-0000-0000-0000-000000000001', proj_id, 'turning',
    '{"turn_number": 1}'::jsonb, 'stirred well');
  perform foodie.foodie_log_fermentation_event(
    '10000000-0000-0000-0000-000000000001', proj_id, 'observation',
    '{"smell": "fruity", "liquid_drainage": "moderate"}'::jsonb, 'looking good');

  if (select count(*) from foodie.fermentation_logs where project_id = proj_id) <> 2 then
    raise exception 'cacao events were not both recorded';
  end if;
end $$;

-- Logging an event against a nonexistent project raises P0008.
do $$ begin
  begin
    perform foodie.foodie_log_fermentation_event(
      '10000000-0000-0000-0000-000000000001', gen_random_uuid(), 'observation', null, null);
    raise exception 'logging against a missing project was accepted';
  exception when sqlstate 'P0008' then null;
  end;
end $$;

-- Update stage/status: current_stage changes, and a stage_change log row is
-- recorded automatically capturing from/to — "stage history" for free.
do $$
declare
  proj_id uuid;
  log_count_before int;
begin
  select id into proj_id from foodie.fermentation_projects where name = 'Backyard Cacao Batch 1';
  select count(*) into log_count_before from foodie.fermentation_logs where project_id = proj_id;

  perform foodie.foodie_update_fermentation_stage(
    '10000000-0000-0000-0000-000000000001', proj_id, 'drying', null, null, 'moved to drying racks');

  if (select current_stage from foodie.fermentation_projects where id = proj_id) <> 'drying' then
    raise exception 'current_stage was not updated';
  end if;
  if not exists (
    select 1 from foodie.fermentation_logs
    where project_id = proj_id and log_type = 'stage_change'
      and payload ->> 'to_stage' = 'drying'
  ) then
    raise exception 'stage_change log was not recorded';
  end if;
  if (select count(*) from foodie.fermentation_logs where project_id = proj_id) <> log_count_before + 1 then
    raise exception 'exactly one stage_change log should have been added';
  end if;
end $$;

-- Completing a project (status change) sets ended_at.
do $$
declare
  proj_id uuid;
begin
  select id into proj_id from foodie.fermentation_projects where name = 'Backyard Cacao Batch 1';
  perform foodie.foodie_update_fermentation_stage(
    '10000000-0000-0000-0000-000000000001', proj_id, 'complete', 'completed', null, 'done, roasting next');

  if (select status from foodie.fermentation_projects where id = proj_id) <> 'completed' then
    raise exception 'status was not updated to completed';
  end if;
  if (select ended_at from foodie.fermentation_projects where id = proj_id) is null then
    raise exception 'ended_at was not set on completion';
  end if;
end $$;

-- Updating a nonexistent project raises P0008; providing nothing raises P0007.
do $$
declare
  proj_id uuid;
begin
  select id into proj_id from foodie.fermentation_projects where name = 'Rustic Rye';
  begin
    perform foodie.foodie_update_fermentation_stage(
      '10000000-0000-0000-0000-000000000001', gen_random_uuid(), 'day 2', null, null, null);
    raise exception 'updating a missing project was accepted';
  exception when sqlstate 'P0008' then null;
  end;
  begin
    perform foodie.foodie_update_fermentation_stage(
      '10000000-0000-0000-0000-000000000001', proj_id, null, null, null, null);
    raise exception 'no-field update was accepted';
  exception when sqlstate 'P0007' then null;
  end;
end $$;

-- Household scope: carol (not a member) is rejected and sees nothing.
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000c';
do $$ begin
  begin
    perform foodie.foodie_create_fermentation_project(
      '10000000-0000-0000-0000-000000000001', 'cacao', 'intruder batch', null, null, null);
    raise exception 'non-member was able to create a fermentation project';
  exception when sqlstate 'P0006' then null;
  end;
  if (select count(*) from foodie.fermentation_projects) <> 0 then
    raise exception 'non-member can read fermentation projects';
  end if;
  if (select count(*) from foodie.fermentation_logs) <> 0 then
    raise exception 'non-member can read fermentation logs';
  end if;
end $$;

reset role;
select 'FERMENTATION TEST PASSED' as result;
