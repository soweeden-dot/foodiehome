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

- **Separate applications and databases.** No shared-database redesign; no Stream 1 migration changes solely to merge systems. Interop arrives later through a scoped interoperability layer. **(Superseded in part, 2026-08-08 — see the schema-isolation entry below: Foodie and Keep Track now share one Supabase project/Postgres instance for practical reasons — only two free-tier projects available — but remain logically separate via a dedicated `foodie` schema with zero cross-app database access. The "no shared-database *design*" intent stands; the infrastructure constraint changed.)**
- **Provenance:** audit architecture must be compatible with action sources `user | foodie | atlas | katie | system`. Implemented in migration 12 as the `action_source` enum: `record_history.source`, `agent_actions.source`, `fermentation_logs.author` all use it. Server-side writers declare themselves via the `app.action_source` GUC (PostgREST clients cannot set it; default is `user`).
- **Unified Morning Brief (future):** one combined morning SMS. Each agent contributes only a structured briefing payload (source_agent, type, priority, start/end time, summary, metadata) — never direct database access. A coordinator merges/dedupes/orders contributions and sends through the existing channel-neutral notification pipeline (`notifications` → `notification_deliveries`). Not built yet; Stream 2+ must simply not block it — the channel-neutral pipeline and `action_source` vocabulary are the compatibility points, and nothing assumes Foodie is the only brief producer.

## 2026-08-08 — Stream 3 approval / entering Stream 4 (with live smoke test)

1. **Live Stream 3 smoke test requested before Stream 4.** No Supabase CLI, linked project, or `ANTHROPIC_API_KEY`/`SUPABASE_*` credentials exist in this execution environment — verified by absence of a `supabase link` state and of any matching environment variables. The live smoke test (items 1–10 of the request) could not be performed and was not faked; the pipeline was instead re-verified via its existing offline test suites (DB harness: 3/3 passed; Deno: 22/22 passed) plus a static secret-leak check (see Stream 4 completion report for the full breakdown). **Outstanding:** a real end-to-end run against a live Supabase project + Anthropic key remains unverified and should be the first action once those credentials exist.

## 2026-08-08 — Stream 4 in progress

1. **Kitchen Device Mode storage confirmed device-local:** `SharedPreferences`-backed boolean (`device.kitchen_mode`), never written to Supabase, never part of any household table. Enabling it on one installation cannot affect another by construction (each install has its own preference store), not by convention or a household-scoped flag that happens not to be read elsewhere.
2. **840px** adopted as the phone/tablet breakpoint (Material 3 "expanded" class) — Kitchen Mode overrides it regardless of width.
3. Kitchen Mode confirmed presentation-only: it does not participate in the router's auth redirect, RLS, or any data-access path.

## 2026-08-08 — Shared Supabase project: Foodie/Keep Track schema isolation

Only two free Supabase projects are available; Foodie will share the existing "Personal" project with Keep Track ("Katie"), which is live and must not be disturbed.

1. **Isolation strategy: dedicated `foodie` Postgres schema**, not table-name prefixing inside `public`. Rationale, full design, and collision analysis in the design-phase turn preceding this entry; final implementation documented in `DATABASE.md` §0 and `ARCHITECTURE.md` §29.
2. **All 33 Foodie tables, 20 enum types, and 14 functions moved from `public` to `foodie`**, in place, in the (never-yet-applied) migration files — not as a new migration, since nothing has been deployed to any real project. This is a pre-deployment rewrite, explicitly not a live-data migration.
3. **The one shared-table touchpoint** (`auth.users` provisioning trigger) is uniquely named (`trg_foodie_new_auth_user`) and calls only `foodie.handle_new_auth_user()`. Keep Track's own trigger(s) on `auth.users`, whatever they are, are neither modified nor assumed to look any particular way — verified by a test harness that simulates a plausible Keep Track footprint (a `profiles` table, a `set_updated_at()` function, an `auth.users` trigger) and asserts it survives Foodie's migrations byte-for-byte unchanged.
4. **`SECURITY DEFINER` functions pin `search_path = foodie, pg_temp`** (previously `public`). One consequence: the invite-code generator was rewritten to derive from `gen_random_uuid()` (core Postgres since PG13) instead of pgcrypto's `gen_random_bytes()`, since the latter's installed schema can no longer be assumed reachable.
5. **No custom Postgres role system introduced for `service_role`.** The project-wide `service_role` key can technically reach `public` (Keep Track) tables regardless of schema isolation — Postgres's RLS bypass isn't schema-scoped. Accepted as a residual shared-project trust cost; mitigated by discipline (minimal, explicitly-scoped `service_role` use) rather than new infrastructure, per explicit instruction not to build one right now.
6. **Manual step required before deployment:** `foodie` must be added to the Supabase project's Exposed Schemas (Project Settings → API) — PostgREST won't serve it otherwise.
7. Storage buckets (none exist yet) and Realtime (not enabled) both get forward-looking documentation notes (`foodie-photos` naming convention; Realtime publication would need `foodie.*` added explicitly later) but no code changes, per explicit scope limits.
