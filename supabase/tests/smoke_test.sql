-- Stream 1 smoke test — run after auth_stub.sql + all migrations.
-- Asserts membership bootstrap, RLS member/outsider behavior, append-only
-- audit enforcement, audit diff content, reminder constraints, and
-- notification dedupe. Every check raises on failure (ON_ERROR_STOP-friendly).

\set ON_ERROR_STOP on

-- Simulate Supabase's "authenticated" role: full table grants, RLS enforced.
create role authenticated nologin;
grant usage on schema public, auth to authenticated;
grant all on all tables in schema public to authenticated;
grant all on all sequences in schema public to authenticated;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'alice@example.com'),
  ('00000000-0000-0000-0000-00000000000b', 'bob@example.com'),
  ('00000000-0000-0000-0000-00000000000c', 'carol@example.com');

do $$ begin
  if (select count(*) from public.profiles) <> 3 then
    raise exception 'profiles were not auto-created';
  end if;
end $$;

-- Alice creates a household; trigger must make her admin.
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';

insert into public.households (id, name, created_by)
  values ('10000000-0000-0000-0000-000000000001', 'Home', '00000000-0000-0000-0000-00000000000a');

do $$ begin
  if not exists (select 1 from public.household_members
                 where household_id = '10000000-0000-0000-0000-000000000001'
                   and user_id = '00000000-0000-0000-0000-00000000000a'
                   and role = 'admin') then
    raise exception 'household creator was not auto-added as admin';
  end if;
end $$;

-- Admin adds Bob; Alice writes domain data.
insert into public.household_members (household_id, user_id, role)
  values ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000b', 'member');
insert into public.food_items (id, household_id, name)
  values ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'Yellow onion');
insert into public.inventory_items (household_id, food_item_id, quantity, unit)
  values ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 3, 'piece');
update public.food_items set category = 'produce'
  where id = '20000000-0000-0000-0000-000000000001';

-- Bob (member) sees household data and audit history…
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
do $$ begin
  if (select count(*) from public.inventory_items) <> 1 then
    raise exception 'member cannot read household inventory';
  end if;
  if (select count(*) from public.record_history) < 3 then
    raise exception 'audit rows missing for member';
  end if;
end $$;

-- …but cannot write the audit log.
do $$ begin
  begin
    insert into public.record_history (household_id, table_name, record_id, op, diff)
      values ('10000000-0000-0000-0000-000000000001', 'x', gen_random_uuid(), 'INSERT', '{}');
    raise exception 'member was able to write record_history';
  exception when insufficient_privilege then null;
  end;
end $$;

-- Carol (outsider) sees nothing and cannot write.
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000c';
do $$ begin
  if (select count(*) from public.households) <> 0
     or (select count(*) from public.inventory_items) <> 0
     or (select count(*) from public.record_history) <> 0 then
    raise exception 'outsider can see household data';
  end if;
  begin
    insert into public.food_items (household_id, name)
      values ('10000000-0000-0000-0000-000000000001', 'intruder item');
    raise exception 'outsider was able to insert food_items';
  exception when insufficient_privilege or check_violation then null;
  end;
end $$;

-- Audit diff captured the category change.
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
do $$ begin
  if (select diff -> 'changed' -> 'category' ->> 'new'
        from public.record_history
       where table_name = 'food_items' and op = 'UPDATE'
       order by id desc limit 1) is distinct from 'produce' then
    raise exception 'audit UPDATE diff did not capture the change';
  end if;
end $$;

-- Scheduled reminder without a recurrence rule must be rejected.
do $$ begin
  begin
    insert into public.reminder_rules (household_id, name, category, kind)
      values ('10000000-0000-0000-0000-000000000001', 'bad rule', 'cleaning', 'scheduled');
    raise exception 'scheduled reminder without recurrence was accepted';
  exception when check_violation then null;
  end;
end $$;

-- Valid scheduled + event rules.
insert into public.recurrence_rules (id, household_id, interval_unit, interval_count, weekday, time_of_day)
  values ('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'week', 1, 0, '08:00');
insert into public.reminder_rules (household_id, name, category, kind, recurrence_rule_id)
  values ('10000000-0000-0000-0000-000000000001', 'Sunday morning brief', 'morning_brief', 'scheduled',
          '30000000-0000-0000-0000-000000000001');
insert into public.reminder_rules (household_id, name, category, kind, event_type, config)
  values ('10000000-0000-0000-0000-000000000001', 'Filter due', 'maintenance', 'event',
          'component_replacement_due', '{"days_before_due": 7}');

-- Notification dedupe (service-role context: reset role).
reset role;
insert into public.notifications (household_id, category, title, body, dedupe_key)
  values ('10000000-0000-0000-0000-000000000001', 'morning_brief', 'Brief', '...', 'morning_brief:2026-08-09');
do $$ begin
  begin
    insert into public.notifications (household_id, category, title, body, dedupe_key)
      values ('10000000-0000-0000-0000-000000000001', 'morning_brief', 'Brief', '...', 'morning_brief:2026-08-09');
    raise exception 'duplicate dedupe_key was accepted';
  exception when unique_violation then null;
  end;
end $$;

-- Every public table must have RLS enabled.
do $$ begin
  if exists (select 1 from pg_tables where schemaname = 'public' and not rowsecurity) then
    raise exception 'table(s) without RLS: %',
      (select string_agg(tablename, ', ') from pg_tables where schemaname = 'public' and not rowsecurity);
  end if;
end $$;

select 'SMOKE TEST PASSED' as result;
