-- Fermentation Tracking phase · Migration 16 — fermentation agent-write RPCs
--
-- Uses foodie.fermentation_projects / fermentation_logs exactly as designed
-- in migration 05 — NO schema changes. Sourdough and cacao are both just
-- project_type + log_type conventions on the existing generic model:
--   - project_type: free text, e.g. 'sourdough_starter', 'cacao'.
--   - Sourdough feedings: log_type='feeding', payload carries the raw
--     measurements {starter_g, flour_g, water_g, flour_type, discard_g}.
--     Hydration %, feed ratio, and next-feed-due are COMPUTED at read time
--     from those raw numbers (supabase/functions/_shared/sourdough.ts,
--     app/lib/domain/sourdough.dart) — never stored, same principle as
--     cleaning due-dates (migration 15 / recurrence.ts).
--   - Sourdough state (active/refrigerated) and feed cadence live in
--     target_params jsonb ({"state": "...", "feed_interval_hours": N}), not
--     new columns — a project row already has a jsonb column for exactly
--     this kind of type-specific variation.
--   - Cacao: turns are log_type='turning', smell/appearance/drainage notes
--     are log_type='observation', drying/roasting are current_stage values
--     with stage_change log rows for history. No cacao-specific schema at
--     all — this is the proof the generic model doesn't force sourdough
--     shape onto other fermentation types.
--
-- Same SECURITY INVOKER + validated + app.action_source='foodie' pattern as
-- migrations 13/14/15. `author` on fermentation_logs uses the shared
-- action_source vocabulary (migration 12) — set via current_action_source()
-- so it reflects the same 'foodie' stamp as the write's provenance.
--
-- Error codes continuing the P000x sequence: P0006 not a household member,
-- P0007 invalid argument, P0008 not found.

create or replace function foodie.foodie_create_fermentation_project(
  p_household     uuid,
  p_project_type  text,
  p_name          text,
  p_target_params jsonb default null,
  p_next_check_at timestamptz default null,
  p_notes         text default null
)
returns foodie.fermentation_projects
language plpgsql
as $$
declare
  result foodie.fermentation_projects;
begin
  if not foodie.is_household_member(p_household) then
    raise exception 'not a household member' using errcode = 'P0006';
  end if;
  if p_project_type is null or length(trim(p_project_type)) = 0 or length(p_project_type) > 50 then
    raise exception 'invalid project type' using errcode = 'P0007';
  end if;
  if p_name is null or length(trim(p_name)) = 0 or length(p_name) > 200 then
    raise exception 'invalid project name' using errcode = 'P0007';
  end if;

  perform set_config('app.action_source', 'foodie', true);

  insert into foodie.fermentation_projects
    (household_id, project_type, name, target_params, next_check_at, notes)
  values
    (p_household, trim(p_project_type), trim(p_name), p_target_params, p_next_check_at,
     nullif(trim(coalesce(p_notes, '')), ''))
  returning * into result;

  return result;
end;
$$;

-- Generic event/observation log — the agent's "log a fermentation event"
-- tool restricts which log_type values it offers (observation/turning/
-- temperature); this RPC itself stays reusable for any log_type so it can
-- also serve future UI-direct logging without a new write path.
create or replace function foodie.foodie_log_fermentation_event(
  p_household uuid,
  p_project_id uuid,
  p_log_type   foodie.fermentation_log_type,
  p_payload    jsonb default null,
  p_notes      text default null
)
returns foodie.fermentation_logs
language plpgsql
as $$
declare
  project foodie.fermentation_projects;
  result  foodie.fermentation_logs;
begin
  if not foodie.is_household_member(p_household) then
    raise exception 'not a household member' using errcode = 'P0006';
  end if;

  select * into project
  from foodie.fermentation_projects
  where id = p_project_id and household_id = p_household and deleted_at is null;
  if project.id is null then
    raise exception 'fermentation project not found' using errcode = 'P0008';
  end if;

  perform set_config('app.action_source', 'foodie', true);

  insert into foodie.fermentation_logs
    (household_id, project_id, log_type, payload, notes, author, created_by)
  values
    (p_household, p_project_id, p_log_type, p_payload,
     nullif(trim(coalesce(p_notes, '')), ''), foodie.current_action_source(), auth.uid())
  returning * into result;

  return result;
end;
$$;

-- Structured sourdough feeding: validates the raw measurements and stores
-- them as-is. Hydration %, starter:flour:water ratio, and next-feed-due are
-- deliberately NOT computed/stored here — see the module header note.
create or replace function foodie.foodie_log_sourdough_feeding(
  p_household  uuid,
  p_project_id uuid,
  p_starter_g  numeric,
  p_flour_g    numeric,
  p_water_g    numeric,
  p_flour_type text default null,
  p_discard_g  numeric default null,
  p_notes      text default null
)
returns foodie.fermentation_logs
language plpgsql
as $$
declare
  project foodie.fermentation_projects;
  result  foodie.fermentation_logs;
  payload jsonb;
begin
  if not foodie.is_household_member(p_household) then
    raise exception 'not a household member' using errcode = 'P0006';
  end if;

  select * into project
  from foodie.fermentation_projects
  where id = p_project_id and household_id = p_household and deleted_at is null;
  if project.id is null then
    raise exception 'fermentation project not found' using errcode = 'P0008';
  end if;

  if p_starter_g is null or p_starter_g <= 0 or p_starter_g > 100000 then
    raise exception 'invalid starter amount' using errcode = 'P0007';
  end if;
  if p_flour_g is null or p_flour_g <= 0 or p_flour_g > 100000 then
    raise exception 'invalid flour amount' using errcode = 'P0007';
  end if;
  if p_water_g is null or p_water_g <= 0 or p_water_g > 100000 then
    raise exception 'invalid water amount' using errcode = 'P0007';
  end if;
  if p_discard_g is not null and (p_discard_g < 0 or p_discard_g > 100000) then
    raise exception 'invalid discard amount' using errcode = 'P0007';
  end if;

  perform set_config('app.action_source', 'foodie', true);

  payload := jsonb_strip_nulls(jsonb_build_object(
    'starter_g', p_starter_g,
    'flour_g', p_flour_g,
    'water_g', p_water_g,
    'flour_type', nullif(trim(coalesce(p_flour_type, '')), ''),
    'discard_g', p_discard_g
  ));

  insert into foodie.fermentation_logs
    (household_id, project_id, log_type, payload, notes, author, created_by)
  values
    (p_household, p_project_id, 'feeding', payload,
     nullif(trim(coalesce(p_notes, '')), ''), foodie.current_action_source(), auth.uid())
  returning * into result;

  return result;
end;
$$;

-- Updates stage/status/next-check-at and records a stage_change log entry
-- for free, so "stage history" is just the same append-only log stream
-- rather than a separate table.
create or replace function foodie.foodie_update_fermentation_stage(
  p_household     uuid,
  p_project_id    uuid,
  p_current_stage text default null,
  p_status        foodie.fermentation_status default null,
  p_next_check_at timestamptz default null,
  p_notes         text default null
)
returns foodie.fermentation_projects
language plpgsql
as $$
declare
  project foodie.fermentation_projects;
  result  foodie.fermentation_projects;
begin
  if not foodie.is_household_member(p_household) then
    raise exception 'not a household member' using errcode = 'P0006';
  end if;
  if p_current_stage is null and p_status is null and p_next_check_at is null then
    raise exception 'at least one field to update must be provided' using errcode = 'P0007';
  end if;

  select * into project
  from foodie.fermentation_projects
  where id = p_project_id and household_id = p_household and deleted_at is null;
  if project.id is null then
    raise exception 'fermentation project not found' using errcode = 'P0008';
  end if;

  perform set_config('app.action_source', 'foodie', true);

  update foodie.fermentation_projects set
    current_stage = coalesce(p_current_stage, current_stage),
    status         = coalesce(p_status, status),
    next_check_at  = coalesce(p_next_check_at, next_check_at),
    ended_at       = case
                        when coalesce(p_status, status) in ('completed', 'discarded')
                             and ended_at is null
                        then now()
                        else ended_at
                      end
  where id = p_project_id
  returning * into result;

  if p_current_stage is not null or p_status is not null then
    insert into foodie.fermentation_logs
      (household_id, project_id, log_type, payload, notes, author, created_by)
    values
      (p_household, p_project_id, 'stage_change',
       jsonb_strip_nulls(jsonb_build_object(
         'from_stage', project.current_stage,
         'to_stage', result.current_stage,
         'from_status', project.status,
         'to_status', result.status
       )),
       nullif(trim(coalesce(p_notes, '')), ''), foodie.current_action_source(), auth.uid());
  end if;

  return result;
end;
$$;

revoke execute on function foodie.foodie_create_fermentation_project(uuid, text, text, jsonb, timestamptz, text) from public;
revoke execute on function foodie.foodie_log_fermentation_event(uuid, uuid, foodie.fermentation_log_type, jsonb, text) from public;
revoke execute on function foodie.foodie_log_sourdough_feeding(uuid, uuid, numeric, numeric, numeric, text, numeric, text) from public;
revoke execute on function foodie.foodie_update_fermentation_stage(uuid, uuid, text, foodie.fermentation_status, timestamptz, text) from public;
grant execute on function foodie.foodie_create_fermentation_project(uuid, text, text, jsonb, timestamptz, text) to authenticated;
grant execute on function foodie.foodie_log_fermentation_event(uuid, uuid, foodie.fermentation_log_type, jsonb, text) to authenticated;
grant execute on function foodie.foodie_log_sourdough_feeding(uuid, uuid, numeric, numeric, numeric, text, numeric, text) to authenticated;
grant execute on function foodie.foodie_update_fermentation_stage(uuid, uuid, text, foodie.fermentation_status, timestamptz, text) to authenticated;
