-- Household Inventory phase test — inventory RPCs, provenance, household
-- scope. Runs after foodie_test.sql; alice is admin of household
-- 1000...01, bob is a member, carol left the household earlier.

\set ON_ERROR_STOP on

set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';

-- Add via unknown location name: auto-creates the location.
select foodie.foodie_add_inventory_item(
  '10000000-0000-0000-0000-000000000001', 'Milk', 'Fridge', 1, 'l', null, null, null);
do $$ begin
  if not exists (select 1 from foodie.inventory_locations
                 where household_id = '10000000-0000-0000-0000-000000000001'
                   and lower(name) = 'fridge') then
    raise exception 'location was not auto-created';
  end if;
  if not exists (select 1 from foodie.inventory_items
                 where name = 'Milk' and source = 'agent') then
    raise exception 'inventory item missing or wrong source';
  end if;
  if (select source from foodie.record_history
       where table_name = 'inventory_items' and op = 'INSERT'
       order by id desc limit 1)::text <> 'foodie' then
    raise exception 'inventory insert not attributed to foodie';
  end if;
end $$;

-- Second add with the same location name (different case) reuses it, not
-- creating a duplicate.
select foodie.foodie_add_inventory_item(
  '10000000-0000-0000-0000-000000000001', 'Eggs', 'fridge', 12, 'piece', null, null, null);
do $$ begin
  if (select count(*) from foodie.inventory_locations
      where household_id = '10000000-0000-0000-0000-000000000001'
        and lower(name) = 'fridge') <> 1 then
    raise exception 'duplicate location created on case-insensitive match';
  end if;
end $$;

-- Argument validation: empty name rejected.
do $$ begin
  begin
    perform foodie.foodie_add_inventory_item(
      '10000000-0000-0000-0000-000000000001', '   ', null, null, null, null, null, null);
    raise exception 'empty item name was accepted';
  exception when sqlstate 'P0007' then null;
  end;
end $$;

-- Negative quantity rejected.
do $$ begin
  begin
    perform foodie.foodie_add_inventory_item(
      '10000000-0000-0000-0000-000000000001', 'Butter', null, -1, null, null, null, null);
    raise exception 'negative quantity was accepted';
  exception when sqlstate 'P0007' then null;
  end;
end $$;

-- Update: partial update leaves omitted fields unchanged.
do $$
declare
  item_id uuid;
begin
  select id into item_id from foodie.inventory_items where name = 'Milk';
  perform foodie.foodie_update_inventory_item(
    '10000000-0000-0000-0000-000000000001', item_id, 0.5, null, null, null, null, null);
  if (select quantity from foodie.inventory_items where id = item_id) <> 0.5 then
    raise exception 'quantity was not updated';
  end if;
  if (select unit from foodie.inventory_items where id = item_id) <> 'l' then
    raise exception 'omitted field (unit) was clobbered instead of left unchanged';
  end if;
  if (select source from foodie.record_history
       where table_name = 'inventory_items' and op = 'UPDATE'
       order by id desc limit 1)::text <> 'foodie' then
    raise exception 'inventory update not attributed to foodie';
  end if;
end $$;

-- Update on a nonexistent item raises P0008.
do $$ begin
  begin
    perform foodie.foodie_update_inventory_item(
      '10000000-0000-0000-0000-000000000001', gen_random_uuid(), 1, null, null, null, null, null);
    raise exception 'update on missing item was accepted';
  exception when sqlstate 'P0008' then null;
  end;
end $$;

-- Remove: soft-deletes, and a second remove correctly reports not-found.
do $$
declare
  item_id uuid;
begin
  select id into item_id from foodie.inventory_items where name = 'Eggs';
  perform foodie.foodie_remove_inventory_item('10000000-0000-0000-0000-000000000001', item_id);
  if (select deleted_at from foodie.inventory_items where id = item_id) is null then
    raise exception 'item was not soft-deleted';
  end if;
  if (select source from foodie.record_history
       where table_name = 'inventory_items' and op = 'UPDATE'
       order by id desc limit 1)::text <> 'foodie' then
    raise exception 'inventory removal not attributed to foodie';
  end if;
  begin
    perform foodie.foodie_remove_inventory_item('10000000-0000-0000-0000-000000000001', item_id);
    raise exception 'removing an already-removed item was accepted';
  exception when sqlstate 'P0008' then null;
  end;
end $$;

-- Household scope: carol (not a member) is rejected and sees nothing.
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000c';
do $$ begin
  begin
    perform foodie.foodie_add_inventory_item(
      '10000000-0000-0000-0000-000000000001', 'intruder snack', null, null, null, null, null, null);
    raise exception 'non-member was able to add an inventory item';
  exception when sqlstate 'P0006' then null;
  end;
  if (select count(*) from foodie.inventory_items) <> 0 then
    raise exception 'non-member can read inventory';
  end if;
end $$;

reset role;
select 'INVENTORY TEST PASSED' as result;
