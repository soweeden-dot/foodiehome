# Foodie Agent Architecture (Stream 3)

Foodie is a real agent: it acts through explicit, typed tools with validation
and auditing — never through free database access. This document is the
contract for how the agent pipeline works and how later streams extend it.

## Pipeline

```
Flutter chat surface
  │  POST /functions/v1/foodie-agent  { message, conversation_id? }  (user JWT)
  ▼
Edge Function handler (supabase/functions/_shared/handler.ts)
  │  1. authenticate JWT → user            (401 if not signed in)
  │  2. validate request shape             (400, structured errors)
  ▼
Orchestrator (orchestrator.ts)
  │  3. resolve household membership       (403 if none — before ANY data access)
  │  4. load/create conversation, append user message
  │  5. assemble context (see below)
  │  6. agent loop (≤5 iterations):
  │       model → tool calls → validate → execute → audit → tool results → model
  ▼
Reply { conversationId, text, actions[] }
```

`actions[]` reflects **actual tool executions** recorded in the audit path.
The client renders those (✓/✗ chips) as the record of what happened; the
model's prose is never the evidence that a mutation occurred.

## Security boundaries

| Boundary | Enforcement |
|---|---|
| Model ↔ data | The model can only request tools in the server-side registry (`tools.ts`). Unknown tools are refused and audited. There is no "run SQL" path of any kind. |
| Agent ↔ database | All domain access goes through the narrow `FoodieDb` interface, implemented over Supabase **with the caller's JWT** — RLS applies in full, so Foodie can never touch data its user couldn't. |
| Mutations | Only via the `foodie_*` SQL functions (migration 13): SECURITY INVOKER, argument-validated, membership-checked, provenance-stamped. |
| Audit writes | `agent_actions` rows are written with the service role — clients have no INSERT policy, so the audit trail cannot be forged or skipped. If the audit write fails, the request fails. |
| Secrets | `ANTHROPIC_API_KEY` exists only as an Edge Function secret. The Flutter client ships no AI credentials and never talks to Anthropic. |
| Errors | Postgres/provider errors are mapped to structured codes (`invalid_argument`, `not_authorized`, `internal`, …) in `supabase_db.ts` / `handler.ts`; raw driver errors and provider details never reach the model or the client. |

## Provider boundary

`ModelProvider` (`types.ts`) is the entire model contract: provider-neutral
messages in, `{text, toolCalls}` out. `anthropic_provider.ts` is the only file
that knows the Anthropic wire format (model from `FOODIE_MODEL`, default
`claude-sonnet-5`). Swapping or adding providers = one new implementation;
the orchestrator, tools, context builder, and domain layer are untouched.
Tests run the full pipeline against a scripted `FakeProvider`.

## Context assembly

The model receives ONLY (`context.ts`):

1. Identity: household name, member names, timezone, today's date.
2. Durable **preferences** (active `memories` rows, category `preference`) as a compact bullet list.
3. The current conversation slice (last 20 messages of this conversation).
4. Tool definitions.
5. Behavioral rules (never claim unconfirmed actions; decline non-household domains; save only clearly durable preferences).

Domain data (grocery list, household facts) is **pulled through read tools
when needed** — tables are never dumped into the prompt. Context assembly is
modular (a pure function of `PromptContext`), so later categories (household
facts, historical summaries) extend it without restructuring.

## Memory vs conversation history

| | `memories` (durable) | `agent_messages` (conversation) |
|---|---|---|
| Written by | Explicit tool call (`save_household_preference`) or, later, user UI | Every chat turn |
| Enters the prompt | Selected by category each turn | Only the current conversation's slice |
| Lifetime | Until edited/deactivated | Storage/history; a new conversation starts clean |

Categories exist for `household_fact`, `preference`, `historical_context`;
Stream 3 wires **preference** end-to-end. Nothing is memorized implicitly:
saying "we shop on Sundays" without Foodie choosing (and confirming) a save
leaves no durable trace — tested explicitly. `(household, category, key)` is
unique, so re-saving a key updates rather than accumulates.

## Tool execution model

Each tool = spec (JSON Schema shown to the model) + `mutating` flag +
`validate()` (hand-rolled, structured messages) + `execute()` against
`FoodieDb`. Per tool call, the orchestrator:

1. Rejects unknown tools (audited as `failed`).
2. Validates input — failures return `{error: {code: "invalid_argument", …}}` to the model and audit as `failed`.
3. Executes; success and failure both write an `agent_actions` row: household, `requested_by` (the human), `conversation_id`, tool, validated input, status, safe summary or error, `source='foodie'`, timestamp. Raw model payloads and secrets are not stored.
4. Data-level changes ALSO land in `record_history` with `source='foodie'` via the GUC set inside the `foodie_*` functions — two independent audit layers.

Mutating tool outcomes surface to the client in `actions[]`; read tools are
audited but not shown as user-visible actions.

## Stream 3 tool set (complete list)

| Tool | Kind | Backing |
|---|---|---|
| `get_basic_household_context` | read | households + members (RLS) |
| `get_household_preferences` | read | memories (RLS) |
| `save_household_preference` | mutate | `foodie_save_memory` RPC |
| `get_grocery_list` | read | grocery lists/items (RLS) |
| `add_grocery_item` | mutate | `foodie_add_grocery_item` RPC (creates the default list on first use) |

Grocery writes were judged safe to include: the Stream 1 schema is complete
for lists/items, the write path is a single validated insert through an RPC,
and the failure modes are benign.

## Multi-agent compatibility (not implemented)

Provenance uses the shared `action_source` vocabulary; context assembly is a
pure module reusable by a future coordinator; Foodie's system prompt
explicitly declines school/calendar/routine requests (Atlas/Katie territory);
Foodie owns no scheduling and no cross-agent channel exists.

## Deferred (later streams)

Domain tools (meal planning, cleaning, fermentation, filters, recipes,
camera), proposed-action confirmation flow (`agent_actions.status='proposed'`
exists but Stream 3 records post-hoc `executed`/`failed` only), undo,
memory-management UI, household-fact/historical memory population, response
streaming, chat history loading in the client (the screen shows the live
session; persistence already works server-side), rate limiting, voice, the
unified morning brief.

## Testing

- `supabase/functions/tests/` (Deno, no network): orchestrator loop, handler auth/validation, tool validation — 22 tests including the "model cannot invent success" and "history ≠ memory" properties.
- `supabase/tests/foodie_test.sql`: RPC validation codes, foodie provenance in `record_history`, membership rejection, audit append-only, conversation/memory separation.
- `app/test/chat_controller_test.dart`: reply/action rendering from server truth, structured error surfacing, conversation continuity.
