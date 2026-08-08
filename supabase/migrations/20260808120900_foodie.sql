-- Stream 1 · Migration 10 — Foodie agent: conversations, messages, actions
--
-- Only the storage foundation — no agent code, no tools (Stream 3+).
-- agent_actions is the intent-level audit trail: one row per tool
-- invocation, enough recorded input/output to explain and (where feasible)
-- revert the change. Data-level auditing is record_history (next migration).

create type foodie.agent_message_role as enum ('user', 'assistant', 'system', 'tool');

create type foodie.agent_action_status as enum ('proposed', 'executed', 'failed', 'reverted');

create table foodie.agent_conversations (
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references foodie.households (id) on delete cascade,
  created_by    uuid references foodie.profiles (id) on delete set null,
  title         text,
  -- Where/why the conversation happened: 'chat', 'cooking', 'voice', 'scan'...
  context_tag   text not null default 'chat',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);

create index idx_agent_conversations_household
  on foodie.agent_conversations (household_id, updated_at desc);

create table foodie.agent_messages (
  id              uuid primary key default gen_random_uuid(),
  household_id    uuid not null references foodie.households (id) on delete cascade,
  conversation_id uuid not null references foodie.agent_conversations (id) on delete cascade,
  role            foodie.agent_message_role not null,
  content         text not null default '',
  -- Tool-use blocks / structured content when role warrants it.
  payload         jsonb,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index idx_agent_messages_conversation
  on foodie.agent_messages (conversation_id, created_at);

create table foodie.agent_actions (
  id              uuid primary key default gen_random_uuid(),
  household_id    uuid not null references foodie.households (id) on delete cascade,
  conversation_id uuid references foodie.agent_conversations (id) on delete set null,
  message_id      uuid references foodie.agent_messages (id) on delete set null,
  tool_name       text not null,
  input           jsonb not null default '{}',
  status          foodie.agent_action_status not null default 'proposed',
  result_summary  text,
  -- Records touched: [{"table": "meal_plan_entries", "id": "..."}, ...]
  affected_records jsonb,
  -- What "undo" would re-apply, when the action is reversible.
  undo_hint       jsonb,
  error           text,
  executed_at     timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index idx_agent_actions_household
  on foodie.agent_actions (household_id, created_at desc);
create index idx_agent_actions_conversation
  on foodie.agent_actions (conversation_id);

create trigger trg_agent_conversations_updated_at before update on foodie.agent_conversations for each row execute function foodie.set_updated_at();
create trigger trg_agent_messages_updated_at      before update on foodie.agent_messages      for each row execute function foodie.set_updated_at();
create trigger trg_agent_actions_updated_at       before update on foodie.agent_actions       for each row execute function foodie.set_updated_at();

-- ---------------------------------------------------------------------------
-- Row Level Security. Conversations/messages: normal member access (insert +
-- read; messages are immutable from the client — no update/delete policies,
-- deleting a conversation cascades server-side). agent_actions: members can
-- READ their audit trail but never write it — rows are created and updated
-- exclusively by the Edge Function tool executor via the service role.
-- ---------------------------------------------------------------------------
alter table foodie.agent_conversations enable row level security;
alter table foodie.agent_messages      enable row level security;
alter table foodie.agent_actions       enable row level security;

create policy agent_conversations_member_select on foodie.agent_conversations
  for select using (foodie.is_household_member(household_id));
create policy agent_conversations_member_insert on foodie.agent_conversations
  for insert with check (foodie.is_household_member(household_id));
create policy agent_conversations_member_update on foodie.agent_conversations
  for update using (foodie.is_household_member(household_id))
  with check (foodie.is_household_member(household_id));

create policy agent_messages_member_select on foodie.agent_messages
  for select using (foodie.is_household_member(household_id));
create policy agent_messages_member_insert on foodie.agent_messages
  for insert with check (foodie.is_household_member(household_id));

create policy agent_actions_member_select on foodie.agent_actions
  for select using (foodie.is_household_member(household_id));
