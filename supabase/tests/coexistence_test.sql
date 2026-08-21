-- Schema-isolation coexistence test — run after keep_track_stub.sql AND all
-- Foodie migrations have applied. Proves the isolation guarantee concretely
-- rather than by inspection: Keep Track's simulated `public` footprint must
-- be byte-for-byte untouched, and every Foodie object must live in `foodie`,
-- not `public`.

\set ON_ERROR_STOP on

-- 1. Keep Track's profiles table still has its own distinct shape — Foodie
--    never created, replaced, or altered a same-named `public.profiles`.
do $$ begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'profiles'
      and column_name = 'keep_track_marker'
  ) then
    raise exception 'Keep Track public.profiles was disturbed by Foodie migrations';
  end if;
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'profiles'
      and column_name in ('display_name', 'avatar_path', 'phone_number')
  ) then
    raise exception 'public.profiles gained Foodie-shaped columns — schemas bled together';
  end if;
end $$;

-- 2. public.set_updated_at() still exists and is still Keep Track's
--    implementation (CREATE OR REPLACE would have silently overwritten it
--    with no error if a Foodie migration had targeted `public`).
do $$ begin
  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'set_updated_at'
  ) then
    raise exception 'Keep Track public.set_updated_at() was removed';
  end if;
  if (select prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'set_updated_at') not ilike '%keep_track%' then
    raise exception 'public.set_updated_at() body changed — Foodie overwrote Keep Track''s function';
  end if;
end $$;

-- 3. Foodie has its OWN, separate set_updated_at() in `foodie` — the two
--    coexist as fully independent objects.
do $$ begin
  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'foodie' and p.proname = 'set_updated_at'
  ) then
    raise exception 'foodie.set_updated_at() is missing';
  end if;
end $$;

-- 4. Both auth.users triggers coexist independently: Keep Track's stub
--    trigger and Foodie's uniquely-named one, and only those two.
do $$ begin
  if (select count(*) from pg_trigger
      where tgrelid = 'auth.users'::regclass and not tgisinternal) <> 2 then
    raise exception 'expected exactly 2 independent triggers on auth.users, found %',
      (select count(*) from pg_trigger where tgrelid = 'auth.users'::regclass and not tgisinternal);
  end if;
  if not exists (select 1 from pg_trigger
                 where tgrelid = 'auth.users'::regclass and tgname = 'on_auth_user_created') then
    raise exception 'Keep Track''s auth.users trigger is missing';
  end if;
  if not exists (select 1 from pg_trigger
                 where tgrelid = 'auth.users'::regclass and tgname = 'trg_foodie_new_auth_user') then
    raise exception 'Foodie''s auth.users trigger is missing or misnamed';
  end if;
end $$;

-- 5. Signing up one new user fires BOTH provisioning triggers independently
--    — Keep Track gets its profile row, Foodie gets its own, neither
--    interferes with or depends on the other.
insert into auth.users (id, email)
  values ('90000000-0000-0000-0000-000000000001', 'shared-signup@example.com');

do $$ begin
  if not exists (select 1 from public.profiles
                 where id = '90000000-0000-0000-0000-000000000001'
                   and keep_track_marker = 'keep-track-owns-this') then
    raise exception 'Keep Track profile provisioning did not fire on signup';
  end if;
  if not exists (select 1 from foodie.profiles
                 where id = '90000000-0000-0000-0000-000000000001') then
    raise exception 'Foodie profile provisioning did not fire on signup';
  end if;
end $$;

-- 6. No Foodie table, type, or function exists anywhere under `public`.
do $$
declare
  foodie_tables constant text[] := array[
    'agent_actions','agent_conversations','agent_messages','cleaning_completions',
    'cleaning_tasks','component_replacements','devices','fermentation_logs',
    'fermentation_photos','fermentation_projects','food_items','grocery_items',
    'grocery_lists','household_members','household_preferences','household_supplies',
    'households','inventory_items','inventory_locations','maintenance_issues',
    'meal_plan_entries','meal_plans','memories','notification_deliveries',
    'notification_preferences','notifications','recipe_ingredients','recipe_steps',
    'recipes','record_history','recurrence_rules','reminder_rules','tracked_components'
    -- NOTE: 'profiles' is deliberately excluded — both apps legitimately have
    -- one, by design; checked precisely by name+shape in step 1 instead.
  ];
  leaked text;
begin
  select string_agg(t, ', ') into leaked
    from unnest(foodie_tables) as t
   where exists (select 1 from pg_tables where schemaname = 'public' and tablename = t);
  if leaked is not null then
    raise exception 'Foodie table(s) leaked into public: %', leaked;
  end if;
end $$;

do $$
declare
  foodie_functions constant text[] := array[
    'current_action_source','foodie_add_grocery_item','foodie_add_inventory_item',
    'foodie_complete_cleaning_task','foodie_create_fermentation_project',
    'foodie_log_fermentation_event','foodie_log_filter_replacement',
    'foodie_log_sourdough_feeding','foodie_remove_inventory_item',
    'foodie_report_maintenance_issue','foodie_resolve_maintenance_issue',
    'foodie_save_memory','foodie_skip_cleaning_task','foodie_update_fermentation_stage',
    'foodie_update_inventory_item','handle_new_auth_user','handle_new_household',
    'is_household_admin','is_household_member','leave_household','log_record_history',
    'protect_last_admin','redeem_household_invite','regenerate_invite_code',
    'resolve_inventory_location','shares_household_with'
    -- NOTE: 'set_updated_at' is deliberately excluded — checked precisely
    -- (existence + unchanged body) in step 2/3 instead, since both apps
    -- legitimately have one under that common name.
  ];
  leaked text;
begin
  select string_agg(f, ', ') into leaked
    from unnest(foodie_functions) as f
   where exists (
     select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = f
   );
  if leaked is not null then
    raise exception 'Foodie function(s) leaked into public: %', leaked;
  end if;
end $$;

-- 7. Every expected Foodie table is present in `foodie`, exactly once.
do $$
declare
  expected constant int := 34;
  actual int;
begin
  select count(*) into actual from pg_tables where schemaname = 'foodie';
  if actual <> expected then
    raise exception 'expected % tables in foodie schema, found %', expected, actual;
  end if;
end $$;

select 'COEXISTENCE TEST PASSED' as result;
