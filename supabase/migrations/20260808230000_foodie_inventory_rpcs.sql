-- Stream "Household Inventory" · Migration 14 — inventory agent-write RPCs
--
-- Same pattern as migration 13's foodie_save_memory / foodie_add_grocery_item:
-- SECURITY INVOKER (run as the calling user, RLS applies in full), argument-
-- validated, app.action_source='foodie' stamped for provenance. These are
-- the ONLY write paths the agent tool executor uses for inventory — see
-- docs/FOODIE.md.
--
-- Uses foodie.inventory_locations / foodie.inventory_items exactly as
-- designed in migration 04; no schema changes.
--
-- Error codes continuing the P000x sequence from migrations 12/13:
--   P0006 not a household member   P0007 invalid argument   P0008 not found

-- Resolve (or create) a location by name within a household. Mirrors
-- foodie_add_grocery_item's "find or create the default list" pattern —
-- households aren't expected to pre-provision Pantry/Fridge/Freezer rows
-- before Foodie or the app can use them.
create or replace function foodie.resolve_inventory_location(
  p_household uuid,
  p_location_name text
)
returns uuid
language plpgsql
as $$
declare
  loc_id uuid;
begin
  if p_location_name is null or length(trim(p_location_name)) = 0 then
    return null;
  end if;

  select id into loc_id
  from foodie.inventory_locations
  where household_id = p_household
    and deleted_at is null
    and lower(name) = lower(trim(p_location_name))
  limit 1;

  if loc_id is null then
    insert into foodie.inventory_locations (household_id, name, kind)
    values (p_household, trim(p_location_name), 'other')
    returning id into loc_id;
  end if;

  return loc_id;
end;
$$;

create or replace function foodie.foodie_add_inventory_item(
  p_household     uuid,
  p_name          text,
  p_location_name text default null,
  p_quantity      numeric default null,
  p_unit          text default null,
  p_level         foodie.supply_level default null,
  p_expires_on    date default null,
  p_notes         text default null
)
returns foodie.inventory_items
language plpgsql
as $$
declare
  loc_id uuid;
  result foodie.inventory_items;
begin
  if not foodie.is_household_member(p_household) then
    raise exception 'not a household member' using errcode = 'P0006';
  end if;
  if p_name is null or length(trim(p_name)) = 0 or length(p_name) > 200 then
    raise exception 'invalid item name' using errcode = 'P0007';
  end if;
  if p_quantity is not null and (p_quantity < 0 or p_quantity > 100000) then
    raise exception 'invalid quantity' using errcode = 'P0007';
  end if;

  perform set_config('app.action_source', 'foodie', true);

  loc_id := foodie.resolve_inventory_location(p_household, p_location_name);

  insert into foodie.inventory_items
    (household_id, name, location_id, quantity, unit, level, expires_on, notes, source)
  values
    (p_household, trim(p_name), loc_id, p_quantity,
     nullif(trim(coalesce(p_unit, '')), ''), p_level, p_expires_on,
     nullif(trim(coalesce(p_notes, '')), ''), 'agent')
  returning * into result;

  return result;
end;
$$;

-- Partial update: an omitted (null) parameter leaves that field unchanged —
-- see docs/FOODIE.md for why (a documented scope limit, not an oversight:
-- this call can't explicitly clear a previously-set field back to null).
create or replace function foodie.foodie_update_inventory_item(
  p_household   uuid,
  p_item_id     uuid,
  p_quantity    numeric default null,
  p_unit        text default null,
  p_level       foodie.supply_level default null,
  p_expires_on  date default null,
  p_opened_on   date default null,
  p_notes       text default null
)
returns foodie.inventory_items
language plpgsql
as $$
declare
  result foodie.inventory_items;
begin
  if not foodie.is_household_member(p_household) then
    raise exception 'not a household member' using errcode = 'P0006';
  end if;
  if p_quantity is not null and (p_quantity < 0 or p_quantity > 100000) then
    raise exception 'invalid quantity' using errcode = 'P0007';
  end if;

  perform set_config('app.action_source', 'foodie', true);

  update foodie.inventory_items set
    quantity   = coalesce(p_quantity, quantity),
    unit       = coalesce(nullif(trim(p_unit), ''), unit),
    level      = coalesce(p_level, level),
    expires_on = coalesce(p_expires_on, expires_on),
    opened_on  = coalesce(p_opened_on, opened_on),
    notes      = coalesce(nullif(trim(p_notes), ''), notes)
  where id = p_item_id
    and household_id = p_household
    and deleted_at is null
  returning * into result;

  if result is null then
    raise exception 'inventory item not found' using errcode = 'P0008';
  end if;

  return result;
end;
$$;

create or replace function foodie.foodie_remove_inventory_item(
  p_household uuid,
  p_item_id   uuid
)
returns foodie.inventory_items
language plpgsql
as $$
declare
  result foodie.inventory_items;
begin
  if not foodie.is_household_member(p_household) then
    raise exception 'not a household member' using errcode = 'P0006';
  end if;

  perform set_config('app.action_source', 'foodie', true);

  update foodie.inventory_items set
    deleted_at = now()
  where id = p_item_id
    and household_id = p_household
    and deleted_at is null
  returning * into result;

  if result is null then
    raise exception 'inventory item not found' using errcode = 'P0008';
  end if;

  return result;
end;
$$;

revoke execute on function foodie.foodie_add_inventory_item(uuid, text, text, numeric, text, foodie.supply_level, date, text) from public;
revoke execute on function foodie.foodie_update_inventory_item(uuid, uuid, numeric, text, foodie.supply_level, date, date, text) from public;
revoke execute on function foodie.foodie_remove_inventory_item(uuid, uuid) from public;
grant execute on function foodie.foodie_add_inventory_item(uuid, text, text, numeric, text, foodie.supply_level, date, text) to authenticated;
grant execute on function foodie.foodie_update_inventory_item(uuid, uuid, numeric, text, foodie.supply_level, date, date, text) to authenticated;
grant execute on function foodie.foodie_remove_inventory_item(uuid, uuid) to authenticated;

-- resolve_inventory_location is a helper called only from the two functions
-- above (both invoker-mode, same caller), not a standalone agent entry point.
revoke execute on function foodie.resolve_inventory_location(uuid, text) from public;
grant execute on function foodie.resolve_inventory_location(uuid, text) to authenticated;
