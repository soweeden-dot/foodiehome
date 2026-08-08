-- Stream 3 test — memories, agent RPCs, foodie provenance.
-- Runs after membership_test.sql; alice is admin of household 1000...01,
-- bob is a member, carol left the household in the previous test.

\set ON_ERROR_STOP on

set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';

-- Save a preference memory via the agent RPC; provenance must be 'foodie'.
select foodie.foodie_save_memory(
  '10000000-0000-0000-0000-000000000001', 'preference',
  'grocery.shopping_day', 'We prefer grocery shopping on Sundays.');

do $$ begin
  if not exists (select 1 from foodie.memories
                 where household_id = '10000000-0000-0000-0000-000000000001'
                   and category = 'preference'
                   and key = 'grocery.shopping_day'
                   and source = 'foodie'
                   and is_active) then
    raise exception 'memory was not saved with foodie source';
  end if;
  if (select source from foodie.record_history
       where table_name = 'memories' order by id desc limit 1)::text <> 'foodie' then
    raise exception 'memory audit row does not carry foodie provenance';
  end if;
end $$;

-- Re-saving the same key updates in place (upsert), no duplicate.
select foodie.foodie_save_memory(
  '10000000-0000-0000-0000-000000000001', 'preference',
  'grocery.shopping_day', 'Shopping day changed to Saturdays.');
do $$ begin
  if (select count(*) from foodie.memories
      where key = 'grocery.shopping_day') <> 1 then
    raise exception 'memory upsert created a duplicate';
  end if;
  if (select content from foodie.memories where key = 'grocery.shopping_day')
       <> 'Shopping day changed to Saturdays.' then
    raise exception 'memory upsert did not replace content';
  end if;
end $$;

-- Direct user edits to memories keep source-of-change = user in the audit.
update foodie.memories set content = 'Sundays after all.'
  where key = 'grocery.shopping_day';
do $$ begin
  if (select source from foodie.record_history
       where table_name = 'memories' and op = 'UPDATE'
       order by id desc limit 1)::text <> 'user' then
    raise exception 'user edit was not attributed to user';
  end if;
end $$;

-- Argument validation: empty content rejected with the structured code.
do $$ begin
  begin
    perform foodie.foodie_save_memory(
      '10000000-0000-0000-0000-000000000001', 'preference', 'x', '   ');
    raise exception 'empty memory content was accepted';
  exception when sqlstate 'P0007' then null;
  end;
end $$;

-- Grocery: first agent add creates the default list; item is source='agent';
-- provenance of the row change is 'foodie'.
select foodie.foodie_add_grocery_item(
  '10000000-0000-0000-0000-000000000001', 'Milk', 1, 'l', null);
do $$ begin
  if (select count(*) from foodie.grocery_lists
      where household_id = '10000000-0000-0000-0000-000000000001') <> 1 then
    raise exception 'default grocery list was not created exactly once';
  end if;
  if not exists (select 1 from foodie.grocery_items
                 where name = 'Milk' and source = 'agent') then
    raise exception 'grocery item missing or wrong source';
  end if;
  if (select source from foodie.record_history
       where table_name = 'grocery_items' and op = 'INSERT'
       order by id desc limit 1)::text <> 'foodie' then
    raise exception 'grocery insert not attributed to foodie';
  end if;
end $$;

-- Second add reuses the same list.
select foodie.foodie_add_grocery_item(
  '10000000-0000-0000-0000-000000000001', 'Greek yogurt');
do $$ begin
  if (select count(*) from foodie.grocery_lists
      where household_id = '10000000-0000-0000-0000-000000000001') <> 1 then
    raise exception 'second add created another list';
  end if;
end $$;

-- Household scope: carol (no longer a member) is rejected with P0006 and RLS
-- hides the household's memories entirely.
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000c';
do $$ begin
  begin
    perform foodie.foodie_add_grocery_item(
      '10000000-0000-0000-0000-000000000001', 'intruder juice');
    raise exception 'non-member was able to add a grocery item';
  exception when sqlstate 'P0006' then null;
  end;
  if (select count(*) from foodie.memories) <> 0 then
    raise exception 'non-member can read memories';
  end if;
end $$;

-- Conversations are storage, not memory: inserting chat rows must not create
-- memories rows (they are unrelated tables; assert counts stay put).
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
insert into foodie.agent_conversations (id, household_id, created_by, context_tag)
  values ('50000000-0000-0000-0000-000000000001',
          '10000000-0000-0000-0000-000000000001',
          '00000000-0000-0000-0000-00000000000a', 'chat');
insert into foodie.agent_messages (household_id, conversation_id, role, content)
  values ('10000000-0000-0000-0000-000000000001',
          '50000000-0000-0000-0000-000000000001', 'user',
          'We prefer grocery shopping on Sundays.');
do $$ begin
  if (select count(*) from foodie.memories
      where household_id = '10000000-0000-0000-0000-000000000001') <> 1 then
    raise exception 'conversation insert leaked into memories';
  end if;
end $$;

-- agent_actions remains service-role-only for writes.
do $$ begin
  begin
    insert into foodie.agent_actions (household_id, tool_name, requested_by)
      values ('10000000-0000-0000-0000-000000000001', 'fake_tool',
              '00000000-0000-0000-0000-00000000000a');
    raise exception 'client wrote agent_actions directly';
  exception when insufficient_privilege then null;
  end;
end $$;

reset role;
select 'FOODIE TEST PASSED' as result;
