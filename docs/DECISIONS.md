# Decision Log

Running record of product/architecture decisions made between streams.
Newest last. These bind future streams unless explicitly revisited.

## 2026-08-08 — Stream 0/1 approval

1. **Stack:** Flutter + Riverpod + go_router + Drift; Supabase (Postgres/Auth/Storage/Realtime/Edge Functions); server-side AI only.
2. **Revised stream order** accepted (sync engine early, camera inventory after the food loop, Foodie read-only debut in Stream 3).
3. **Filters generalized** to `tracked_components`.
4. **Recurrence** is one shared `recurrence_rules` vocabulary; occurrences are always computed, never pre-generated.

## 2026-08-08 — Stream 1 approval / entering Stream 2

1. **Reminder worker:** a dedicated notification/reminder worker stream is inserted before the expanded Foodie agent tool layer (after the domain data it watches exists). The notification system stays channel-neutral; Twilio SMS is one provider, never part of reminder-generation logic.
2. **Authentication:** email/password now. Architecture must stay compatible with adding Sign in with Apple later (kept: gateway seam in the app, Supabase Auth supports Apple provider without schema changes). Not implemented now.
3. **Household deletion:** stays service-role-only. A protected server-side "Delete Household" flow with strong confirmation may be built later; client-side direct deletion remains prohibited.
4. **Kitchen iPad:** signs in with the owner's normal account — no fake kitchen user. A Kitchen Device Mode (restricted navigation, always-on display optimizations) comes later; the `devices` table + `device_profile` already anticipate it.

## 2026-08-08 — Multi-agent context (recorded, not implemented)

FoodieHome is one of three separate personal apps/agents:

- **Atlas** — school/academic agent (exists)
- **Foodie** — household/food agent (this project)
- **Katie** — Keep Track agent: routines, workouts, calendar, personal planning (exists)

Constraints going forward:

- **Separate applications and databases.** No shared-database redesign; no Stream 1 migration changes solely to merge systems. Interop arrives later through a scoped interoperability layer.
- **Provenance:** audit architecture must be compatible with action sources `user | foodie | atlas | katie | system`. Implemented in migration 12 as the `action_source` enum: `record_history.source`, `agent_actions.source`, `fermentation_logs.author` all use it. Server-side writers declare themselves via the `app.action_source` GUC (PostgREST clients cannot set it; default is `user`).
- **Unified Morning Brief (future):** one combined morning SMS. Each agent contributes only a structured briefing payload (source_agent, type, priority, start/end time, summary, metadata) — never direct database access. A coordinator merges/dedupes/orders contributions and sends through the existing channel-neutral notification pipeline (`notifications` → `notification_deliveries`). Not built yet; Stream 2+ must simply not block it — the channel-neutral pipeline and `action_source` vocabulary are the compatibility points, and nothing assumes Foodie is the only brief producer.
