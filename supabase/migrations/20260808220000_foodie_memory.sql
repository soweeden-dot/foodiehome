-- Stream 3 · Migration 13 — Foodie memory foundation + agent-write RPCs
--
-- 1. memories: durable, structured memory — completely separate from
--    conversation history. A memory write is always an explicit tool call,
--    never automatic capture of chat.
-- 2. agent_actions.requested_by: the human on whose behalf Foodie acted.
-- 3. foodie_* RPCs: the ONLY write paths the agent tool executor uses for
--    domain data. SECURITY INVOKER — they run as the calling user, so RLS
--    applies in full; each sets app.action_source='foodie' transaction-
--    locally so record_history attributes the write to the agent acting for
--    that user. The Edge Function calls these with the user's JWT: Foodie
--    can never touch data its user couldn't.

create type foodie.memory_category as enum
  ('household_fact', 'preference', 'historical_context');

create table foodie.memories (
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references foodie.households (id) on delete cascade,
  category      foodie.memory_category not null,
  -- Stable subject key, namespaced: 'grocery.shopping_day', 'reminders.tone'.
  key           text not null,
  content       text not null,
  source        foodie.action_source not null default 'user',
  created_by    uuid references foodie.profiles (id) on delete set null,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz,
  unique (household_id, category, key)
);

create index idx_memories_household
  on foodie.memories (household_id, category)
  where is_active and deleted_at is null;

create trigger trg_memories_updated_at
  before update on foodie.memories
  for each row execute function foodie.set_updated_at();

create trigger trg_audit_memories
  after insert or update or delete on foodie.memories
  for each row execute function foodie.log_record_history();

alter table foodie.memories enable row level security;

create policy memories_member_all on foodie.memories
  for all using (foodie.is_household_member(household_id))
  with check (foodie.is_household_member(household_id));

-- The human whose request the agent was serving.
alter table foodie.agent_actions
  add column requested_by uuid references foodie.profiles (id) on delete set null;

-- ---------------------------------------------------------------------------
-- Agent write RPCs. Validation raises structured error codes the tool layer
-- maps to safe messages (raw database errors never reach the model):
--   P0006 not a household member   P0007 invalid argument
-- ---------------------------------------------------------------------------

-- Upsert a durable memory. Re-saving the same (category, key) replaces the
-- content and reactivates it.
create or replace function foodie.foodie_save_memory(
  p_household uuid,
  p_category  foodie.memory_category,
  p_key       text,
  p_content   text
)
returns foodie.memories
language plpgsql
as $$
declare
  result foodie.memories;
begin
  if not foodie.is_household_member(p_household) then
    raise exception 'not a household member' using errcode = 'P0006';
  end if;
  if p_key is null or length(trim(p_key)) = 0 or length(p_key) > 200 then
    raise exception 'invalid memory key' using errcode = 'P0007';
  end if;
  if p_content is null or length(trim(p_content)) = 0 or length(p_content) > 2000 then
    raise exception 'invalid memory content' using errcode = 'P0007';
  end if;

  perform set_config('app.action_source', 'foodie', true);

  insert into foodie.memories (household_id, category, key, content, source, created_by)
  values (p_household, p_category, trim(p_key), trim(p_content), 'foodie', auth.uid())
  on conflict (household_id, category, key) do update
    set content    = excluded.content,
        source     = 'foodie',
        is_active  = true,
        deleted_at = null
  returning * into result;

  return result;
end;
$$;

-- Add an item to the household's default grocery list (creating the list on
-- first use). Item is marked source='agent'.
create or replace function foodie.foodie_add_grocery_item(
  p_household uuid,
  p_name      text,
  p_quantity  numeric default null,
  p_unit      text default null,
  p_notes     text default null
)
returns foodie.grocery_items
language plpgsql
as $$
declare
  list_id uuid;
  result  foodie.grocery_items;
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

  select id into list_id
  from foodie.grocery_lists
  where household_id = p_household
    and archived_at is null
    and deleted_at is null
  order by created_at
  limit 1;

  if list_id is null then
    insert into foodie.grocery_lists (household_id, name)
    values (p_household, 'Groceries')
    returning id into list_id;
  end if;

  insert into foodie.grocery_items
    (household_id, grocery_list_id, name, quantity, unit, notes, source)
  values
    (p_household, list_id, trim(p_name), p_quantity, nullif(trim(coalesce(p_unit, '')), ''),
     nullif(trim(coalesce(p_notes, '')), ''), 'agent')
  returning * into result;

  return result;
end;
$$;

revoke execute on function foodie.foodie_save_memory(uuid, foodie.memory_category, text, text) from public;
revoke execute on function foodie.foodie_add_grocery_item(uuid, text, numeric, text, text) from public;
grant execute on function foodie.foodie_save_memory(uuid, foodie.memory_category, text, text) to authenticated;
grant execute on function foodie.foodie_add_grocery_item(uuid, text, numeric, text, text) to authenticated;
