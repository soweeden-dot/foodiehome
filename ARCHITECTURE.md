# FoodieHome — Technical Architecture (Stream 0)

**Status:** Proposed — awaiting approval before Stream 1
**Scope:** Private household operating system for one household (two members), running on a kitchen iPad (dashboard/cooking), a personal iPad (planning), and an iPhone (mobile/scanning/voice). "Foodie" is the AI agent that sits on top of the app.

This document is the contract for how the system is built. Later streams should conform to it; deviations should be recorded here first.

---

## 1. High-Level Architecture

```
┌────────────────────────────────────────────────────────────┐
│                     Flutter App (iOS)                      │
│  ┌──────────────┐ ┌──────────────┐ ┌───────────────────┐   │
│  │ Kitchen iPad │ │ Personal iPad│ │ iPhone            │   │
│  │ layout       │ │ layout       │ │ layout            │   │
│  └──────┬───────┘ └──────┬───────┘ └────────┬──────────┘   │
│         └───── shared feature/domain layer ─┘              │
│                        │                                   │
│              Local DB (Drift/SQLite) ◄── source of truth   │
│                        │        offline                    │
│                  Sync Engine (outbox/inbox)                │
└────────────────────────┼───────────────────────────────────┘
                         │ HTTPS / Realtime
┌────────────────────────▼───────────────────────────────────┐
│                       Supabase                             │
│  Postgres (canonical data)   Auth    Storage (photos)      │
│  Realtime (change fan-out)   Edge Functions:               │
│     • /ai/*  → AI provider calls (keys live here only)     │
│     • agent tool execution + audit                         │
└────────────────────────────────────────────────────────────┘
```

Core principles (restating the non-negotiables):

1. **Structured records in Postgres are the source of truth.** The AI reads and writes through the same application logic as the UI — never directly to raw data, never as an authority.
2. **Local-first reads.** Every screen renders from the local SQLite database. The network is for sync, not for rendering.
3. **The agent is a client of the app**, gated behind explicit tools, with every action audited.
4. **AI confirmation gates:** camera inventory changes and any food-safety assessment always require human confirmation; safety answers are conservative by design (enforced in server-side prompts and tool design, not just UI copy).
5. **Private-scale engineering:** one household, two users, a handful of devices. We avoid multi-tenant SaaS machinery (no orgs/teams/billing/feature flags), but we do not skip the things that protect data: migrations, RLS, backups, audit, tested sync.

---

## 2. Flutter Application Architecture

Layered, feature-first:

```
UI (screens/widgets, per-device layouts)
   ↓ watches
Application layer (controllers/notifiers — orchestration, no I/O details)
   ↓ calls
Domain layer (entities, value types, pure business rules)
   ↓ implemented by
Data layer (repositories → Drift DAOs, Supabase API, sync engine)
```

Rules:

- **Repositories are the only door to data.** UI and controllers never touch Drift or Supabase clients directly. Each domain area (inventory, recipes, meal plans, …) gets one repository interface.
- **Domain entities are plain Dart** (freezed-style immutable classes), independent of both the Drift row classes and Supabase JSON. Mappers live in the data layer.
- **Device layouts are presentation-only.** A single `DeviceProfile` (kitchen-ipad / ipad / phone, derived from screen class + a persisted per-device setting so the kitchen iPad can be pinned to dashboard mode) selects layout variants. Features expose the same controllers to all three layouts — layouts differ in composition, not logic.
- **Business logic that must be consistent between the app and the agent lives once**, in domain services (e.g., "recalculate grocery needs from meal plan + inventory") and is invoked by both UI actions and agent tools.

## 3. State Management — Riverpod

**Recommendation: Riverpod (with code generation).**

Why:

- Compile-safe dependency graph; repositories, DAOs, and the sync engine are all providers, which makes the layering above enforceable and testable (override any provider in tests).
- First-class async/stream support: screens watch Drift streams through `StreamProvider`/`AsyncNotifier`, so local writes and incoming sync updates repaint the UI automatically — this is the backbone of "local DB is the source of truth."
- Scales down: simple features stay a few lines; no ceremony like Bloc events/states for CRUD screens.
- No BuildContext coupling, so the same providers back UI, background sync, and the voice layer later.

Rejected: Bloc (too much ceremony for a two-person app), Provider (weaker composition/testing), GetX (magic, poor long-term maintainability).

## 4. Navigation — go_router

**Recommendation: go_router** with a `StatefulShellRoute` for the main scaffold.

- Declarative route table in one place; deep links (needed later for App Intents/Siri: "open cooking mode", "open grocery list") map cleanly to routes.
- Per-device shells: the route tree is shared; the shell widget renders rail/tabs/dashboard chrome based on `DeviceProfile`.
- Guarded redirects for auth state (route guard reads a Riverpod auth provider).
- Cooking Mode and the kitchen dashboard are ordinary routes that can be locked in via kiosk-style behavior (Guided Access on the iPad handles the OS side).

## 5. Local/Offline Database — Drift (SQLite)

**Recommendation: Drift** as a real persistent local database, not a cache.

Why Drift over the alternatives:

- Typed schema + typed queries + **schema migrations with test support** — sync correctness depends on knowing exactly what the local schema is at every version.
- Reactive queries (streams) feed Riverpod directly.
- SQLite is boring, durable, and debuggable (you can open the file); Isar/ObjectBox are faster but have had maintenance instability, and Hive is a key-value store, not a database.
- Supabase's own offline story is immature; owning the local store keeps us independent.

Local schema mirrors the server schema for synced tables, plus sync metadata columns (`updated_at`, `is_deleted`, `pending` flag) and two local-only tables: `outbox` (queued local mutations) and `sync_state` (per-table high-water marks).

## 6. Supabase Architecture

| Component | Use |
|---|---|
| **Postgres** | Canonical data. Schema managed exclusively by versioned SQL migrations in this repo (`supabase/migrations/`), applied via Supabase CLI. No dashboard-edited schema. |
| **Auth** | Email/password (or magic link) for the two of you. No social providers needed. |
| **Storage** | Photos (inventory scans, fermentation photos, recipe images) in private buckets. |
| **Realtime** | Change notifications → clients react by pulling deltas (see §9). Realtime is a *hint*, never the transport of record. |
| **Edge Functions** | (a) All AI calls — chat, vision, agent loop — so API keys never reach the client. (b) Agent tool execution with audit. (c) The few server-authoritative mutations (e.g., "replace filter" record + next-due calculation can be client-side logic, but agent-initiated writes always go through functions). |

Postgres conventions: UUID primary keys (client-generatable — required for offline creates), `household_id` on every domain row, `created_at`/`updated_at` (trigger-maintained), soft delete via `deleted_at` on synced tables, `snake_case`.

## 7. Authentication & Household Model

> **Decided (Stream 2):** email/password sign-in (Supabase Auth); Sign in with Apple can be added later as another Supabase provider without schema or gateway changes. The kitchen iPad signs in with a normal household account — no fake kitchen user; a Kitchen Device Mode restricting navigation comes later and rides on `devices.profile`. Household deletion remains service-role-only.

- `auth.users` (Supabase-managed) → `profiles` (1:1, display name, avatar).
- `households` — expect exactly one row, but model it properly (costs nothing, prevents weird hacks).
- `household_members` — join table (`household_id`, `user_id`, `role`). Both of you are `admin`; the role column exists so future guests/read-only members don't require a migration.
- Joining a household: an invite code created by an existing member (simple, no email infra). This is Stream 2 scope.
- **Devices are not users.** The kitchen iPad signs in as one of you; a `devices` table records each installation (id, name, device profile) for per-device dashboard layout and sync bookkeeping.

## 8. Database Domain Boundaries & Initial Entities

Seven domains, one Postgres schema, boundaries enforced by convention (module folders in app + migration file grouping), not separate databases:

**Core** — `profiles`, `households`, `household_members`, `devices`
**Recurrence** — `recurrence_rules`, one shared vocabulary for everything that repeats (cleaning, reminders)
**Food** — inventory, food catalog, recipes, meal plans, grocery
**Fermentation** — projects, logs, photos
**Home care** — cleaning schedules, completions
**Assets** — tracked components (filters), replacements, household supplies
**Notifications** — reminder rules, notifications, deliveries, preferences (§27)
**Foodie** — conversations, messages, agent actions, memories, preferences
**Audit** — change history

*(As of Stream 1 the authoritative table-by-table reference is `DATABASE.md`; this section stays at concept level.)*

### Entity model (high level — not final SQL)

```
households 1─* household_members *─1 auth.users(profiles)
households 1─* everything below (every table carries household_id)
```

**Food domain**

- `food_items` — the household's catalog of foods ("yellow onion", canonical unit, category, default shelf life, typical storage location, per-household so corrections/aliases personalize it). *Catalog, not stock.*
- `inventory_locations` — pantry / fridge / freezer / other (user-definable).
- `inventory_items` — stock on hand: → `food_item`, → `location`, quantity + unit **or** approximate level, expiration/use-by, opened date, source (`manual` | `scan` | `agent`), notes. Inventory references the catalog so "onion" in a recipe, in stock, and on a grocery list are the same identity.
- `recipes` — title, servings, times, source URL, tags, nutrition per serving (optional), instructions as **structured steps** (ordered `recipe_steps`: text, optional duration, optional temperature) — required for Cooking Mode and step-aware voice.
- `recipe_ingredients` — → `recipe`, → `food_item` (nullable for free-text one-offs), quantity, unit, preparation note, optional per-member portion scaling.
- `meal_plans` — one row per household per week (or simply a date-ranged container).
- `meal_plan_entries` — → `meal_plan`, date, meal slot (breakfast/lunch/dinner/prep), → `recipe` (nullable — "leftovers"/"eating out" are valid entries), servings per member, status.
- `grocery_lists` 1─* `grocery_items` — → `food_item` (nullable), quantity/unit, need source (`manual` | `meal_plan` | `low_supply` | `agent`), checked state, store section. Generated items keep a reference to what generated them so recalculation can update rather than duplicate.

**Fermentation domain**

- `fermentation_projects` — type (cacao, sourdough, …), name, start time, status, current stage, target parameters, next check time, safety notes.
- `fermentation_logs` — → project, timestamp, log type (observation / feeding / turn / temperature / stage change / AI observation), structured payload (temps, ratios: starter/flour/water grams, flour type), free-text notes (smell/appearance/texture), author (`user` | `foodie`). One append-only stream covers feedings, turnings, and observations — type + payload distinguishes them.
- `fermentation_photos` — → project, optional → log, storage path, taken-at.

**Home care domain**

- `cleaning_tasks` — task, area/room, checklist (jsonb), frequency **rule** (RRULE-style: interval + unit + preferred day), assigned member, notes, active flag.
- `cleaning_completions` — → task, completed at/by, checklist snapshot, notes. **Next-due is computed** (last completion + rule) — no pre-generated occurrence rows, per your requirement.

**Assets domain**

- `tracked_components` — generalizes "filters": device/system, component name, brand/model, install date, replacement interval, spares count, product info/links, notes.
- `component_replacements` — → component, replaced at/by, notes; replacing writes a history row and resets the interval clock. Next-due computed, same pattern as cleaning.
- `household_supplies` — name, category, tracking mode (`count` | `level`), count, level enum (full/good/low/almost_empty/out), restock threshold, preferred product, notes. Low/out state is what Foodie later uses to propose grocery items.

**Foodie domain**

- `agent_conversations` 1─* `agent_messages` — role, content, timestamps, device/context tag (chat vs cooking session vs voice).
- `agent_actions` — → conversation/message, tool name, input params (jsonb), result summary, affected records, status (`proposed` | `executed` | `failed` | `reverted`), undo hint. Every tool call writes one row — this is the agent's audit trail (§15).
- `memories` — scoped memory records: category (`household_fact` | `preference` | `historical_summary`), subject key, content, source (`user_stated` | `agent_inferred` | `derived`), confidence, active flag. See §14.
- `cooking_sessions` — → recipe, device, started at, current step, timers state, status. This is what gives voice/agent "what am I cooking right now" context.

**Audit domain**

- `record_history` — table name, record id, operation, changed-by (user / agent / sync), diff (jsonb), timestamp. Populated by Postgres triggers on the important domain tables. Kept separate from `agent_actions` (which is intent-level; this is data-level).

Notable relationship decisions:

- `food_items` is the hub tying recipes ↔ inventory ↔ grocery — this is what makes "we used the last onion" and grocery generation possible. Free-text fallbacks are allowed everywhere so data entry never fights you.
- Recurring things (cleaning, components) are **rule + completion-history**, never occurrence tables.
- Photos rows store metadata + storage path only; bytes live in Storage (§11).

## 9. Sync Architecture

**Pattern: local-first with an outbox, delta pull, server-canonical.**

Writes:
1. UI/agent writes to local Drift DB in a transaction and appends a mutation to the local `outbox` (record id, table, op, changed columns, client timestamp).
2. UI updates instantly from the local DB.
3. The sync engine drains the outbox to Supabase (upserts via PostgREST) when online, with retry/backoff. Outbox entries are removed only after server acknowledgment.

Reads:
1. Pull deltas per table using the server's trigger-maintained `updated_at` high-water mark (`sync_state`), including soft-deleted rows.
2. Supabase Realtime subscription (per household) acts as a "something changed, pull now" doorbell; a periodic pull covers missed events.

Properties: client-generated UUIDs make creates idempotent; soft deletes make deletions syncable; the server DB remains canonical; a device that was offline for a week converges by ordinary delta pull. Sync is per-table sequential, all tables' logic identical — one engine, no per-feature sync code.

**Not synced:** cooking session timer ticks (local, ephemeral — only session state snapshots sync), draft text, device settings.

## 10. Conflict Resolution

Reality check: two users, low write contention. Strategy: simple, safe, and biased toward *not losing data*.

- **Default: field-level last-write-wins** using server receive time. The outbox records which columns changed, so two people editing *different fields* of the same row both win.
- **Additive tables get no conflicts by design:** logs, completions, replacements, photos, messages, actions, history are append-only inserts.
- **Grocery check-off and supply levels:** LWW is correct (latest physical state wins).
- **Deletes vs edits:** edit after delete resurrects the row (un-soft-deletes) — losing an edit is worse than undeleting.
- **Meal plan entries:** per-slot rows (not one blob per week) keep granularity high enough that LWW per row is acceptable.
- Every synced overwrite that discarded a concurrent value is recorded in `record_history`, so nothing is silently unrecoverable.

Explicitly rejected: CRDTs and operational transforms — unjustifiable complexity for this household.

## 11. Image/Photo Storage

- Private Supabase Storage buckets: `photos` (paths: `{household_id}/{domain}/{record_id}/{uuid}.jpg`), RLS-gated by household membership; access from the app via short-lived signed URLs.
- Client compresses/resizes before upload (long edge ~1600px for fermentation/inventory shots; originals not kept — these are working photos, not a photo library).
- DB rows store path + metadata; upload rides the same outbox (a photo row isn't synced until its file is uploaded).
- Local: uploaded photos cached on disk with an LRU cap; photos pending upload are pinned.
- AI vision reads photos server-side (Edge Function passes a signed URL or bytes to the vision model) — images never require a second upload path.

## 12. AI / Agent Architecture

All AI runs server-side in Edge Functions. The Flutter client sends messages/photos and renders results; it never holds AI keys or constructs prompts containing secrets.

```
Client ── message/photo ──► Edge Function (agent loop)
                              │  system prompt + selected memories + context
                              ▼
                        AI model (Anthropic API)
                              │  tool_use requests
                              ▼
                        Tool executor (server-side)
                          • validates tool + params against registry
                          • checks household scope
                          • executes via same DB logic as the app
                          • writes agent_actions row
                              │  tool results
                              ▼
                        model continues → final reply → client
```

- **The agent loop lives in one Edge Function** ("foodie-agent"): receives conversation id + new message, loads recent messages + selected memories + live context (active cooking session, today's plan), runs the tool-use loop, persists messages/actions, returns the reply.
- **Vision (camera inventory) is a separate function** returning a *proposal* (detected items + confidence + unknowns), never a write. The client renders the review screen; only user-confirmed items become inventory writes (source=`scan`).
- **Safety posture is enforced server-side:** the fermentation prompt hard-codes conservative rules ("never clear questionable food from an image; state uncertainty; when in doubt, advise discarding or non-visual checks"). Not left to the client.
- Streaming responses via SSE from the Edge Function for chat UX.

## 13. Agent Tool Architecture

- **A typed tool registry, server-side.** Each tool = name, JSON-schema params, handler, and metadata: `readonly` vs `mutating`, and `requires_confirmation` (mutating tools can demand a user-visible confirm step before execution — used for destructive/bulk changes).
- **Tools call domain logic, not tables.** `update_meal_plan` invokes the same "recalculate grocery needs" service the UI uses — one implementation of every business rule (mirrored server-side in TypeScript where the agent needs it; the boundary rule is that any rule the agent can trigger lives server-side, and the Flutter app calls it or reimplements only trivial display logic).
- **Tools ship per stream.** The registry has an allowlist; a tool is registered only when its underlying feature stream is done and verified. The model never sees unregistered tools.
- Every invocation → `agent_actions` row (before execution: `proposed`; after: `executed`/`failed`), with enough recorded input/output to explain and — where feasible — revert the change.
- Multi-step behaviors (your Friday-dinner example) are just the model chaining registered tools; the chain is reconstructable from `agent_actions` and summarized back to you ("Removed Friday dinner, 3 grocery items no longer needed, removed 2, kept milk — also used by Saturday's recipe").

## 14. Foodie Memory Architecture

Memory is **retrieval from structured data + a small curated memory store** — never "replay the chat history."

| Layer | Backing | Example | How it reaches the prompt |
|---|---|---|---|
| Household facts | Domain tables themselves | filters owned, appliances, pantry stock | Read via readonly tools at answer time — always current, never stale copies |
| Preferences | `memories` (category=`preference`) + explicit `preferences` UI later | "no cilantro", "meal prep Sundays", "B. handles bathrooms" | Compact bullet block injected into system prompt |
| Historical records | Domain history tables (completions, replacements, logs, grocery history, `agent_actions`) | "when did we last replace the shower filter" | Queried via readonly tools on demand |
| Derived summaries | `memories` (category=`historical_summary`), written by explicit summarization jobs | "household typically cooks 4 dinners/week" | Injected or retrieved as relevant |

Rules:

- The agent may *propose* a memory ("Noted that you prefer oat milk — save this?"); user-visible confirmation before an `agent_inferred` memory becomes active, and a memory management screen lists/edits/deletes all memories. No silent belief accumulation.
- Prompt budget: system prompt gets identity + safety rules + active preferences + live context (cooking session, date, device); everything else is pulled through tools. This keeps prompts small and behavior explainable.
- No vector database at the start. Memory volume is tiny; keyword/category retrieval suffices. Revisit only if retrieval demonstrably fails.

## 15. Audit / History

Two layers, both append-only:

1. **`agent_actions`** — intent level: what Foodie did, with what inputs, on whose message, with what result. Powers an "Agent activity" screen and undo.
2. **`record_history`** — data level: trigger-based row diffs on domain tables, capturing user, agent, and sync writes alike. Answers "why does the data look like this."

Reversibility: mutating tools record an undo hint (e.g., the removed meal plan entry's data). "Undo" re-applies via the normal write path and marks the action `reverted`. Not all actions are undoable (physical events like "filter replaced" just get history).

## 16. Voice (future-proofing now, building later)

Voice is a **thin input/output layer over the same agent + tool architecture** — no separate voice brain.

- Speech-to-text: Apple's native `SFSpeechRecognizer` (on-device where available) → text → the same Foodie pipeline. TTS: `AVSpeechSynthesizer`.
- "Hey Foodie" without secret 24/7 listening: an explicit tap/button starts a listening session; in Cooking Mode, an *opt-in, visibly indicated* listening state during active cooking; plus Siri entry ("Hey Siri, tell Foodie …") via App Intents.
- Cooking Mode voice commands ("next step", "how much butter") are handled by lightweight intent matching against the active `cooking_session` **locally first** (works offline, instant), falling back to the full agent for open questions.
- Architecture impact now: `cooking_sessions` as first-class synced state, structured recipe steps/ingredients, and the tool registry — all designed in already. Voice adds no new data model.

## 17. App Intents / Native iOS Integration

- App Intents must be **native Swift** in the iOS Runner target — this is Apple-tooling territory Flutter can't own. Intents are declared in Swift and forwarded to Flutter over a small **platform channel** (`MethodChannel`) as typed commands (`open_route`, `add_grocery_item`, `foodie_query`, …).
- Start with a handful of high-value intents (add grocery item, open cooking mode, ask Foodie); simple ones (add grocery item) can even write via a background channel call without opening UI.
- Keep the Swift layer dumb: parse intent → forward → return result. All logic stays in Dart/server.
- Deep links (universal links/custom scheme) map to go_router routes — this also powers dashboard entertainment shortcuts (Netflix/Spotify/YouTube launched via their URL schemes/universal links; nothing recreated in-app).

## 18. Security Model

- Threat model: protecting a private household's data (location-ish habits, photos of your home, schedules) against leakage — not defending against malicious tenants.
- All access authenticated via Supabase Auth; every domain row scoped by `household_id`; RLS (§19) is the enforcement point — client code is never trusted for scoping.
- Edge Functions verify the caller's JWT and derive the household from membership — never from a client-supplied parameter alone.
- Storage buckets private; signed URLs short-lived.
- Local SQLite protected by iOS Data Protection (files encrypted at rest by the OS when the device is locked); no additional app-layer database encryption (SQLCipher) unless you want it — it complicates debugging for marginal gain on personal, passcoded devices.
- Tokens in Keychain via `flutter_secure_storage`.
- The agent runs with the *user's* authority (tools execute under the caller's household scope) — Foodie can never touch data its user couldn't.

## 19. Row Level Security Strategy

- RLS **enabled on every table from the first migration** — even as a private app, this is the backstop that makes a leaked anon key or a client bug non-catastrophic.
- One pattern everywhere: a `is_household_member(household_id)` SQL function (checks `household_members` for `auth.uid()`), used in `USING`/`WITH CHECK` on all four operations for all domain tables.
- `profiles`: users read household co-members, write self. `households`/`household_members`: members read; admin writes; invite-code redemption via a `SECURITY DEFINER` function (the one place someone writes before being a member).
- Append-only tables (`agent_actions`, `record_history`, logs, completions): INSERT + SELECT for members; no UPDATE/DELETE policies — immutability enforced by the database.
- Edge Functions use the caller's JWT (RLS applies) by default; the `service_role` key is used only inside functions for the narrow steps that need it (e.g., audit writes), never shipped anywhere.

## 20. Secrets Strategy

- **AI API keys exist only as Supabase Edge Function secrets.** Never in the repo, never in the Flutter bundle, never in Postgres.
- Flutter ships only the Supabase URL + anon key (designed to be public; RLS is the security boundary).
- Repo hygiene: `.env` files git-ignored; `--dart-define` for build-time config; no secrets in migration files or seed data.
- Supabase service-role key: CI/local-tooling only, never in the app.

## 21. Backup / Data Loss

This data is years of household history — treat backups as a feature.

- Supabase automated daily backups (plan-dependent) as the baseline.
- **Own your data anyway:** a scheduled export (Supabase scheduled function or a simple script/cron) dumping all household tables to JSON/SQL into a separate storage location (private bucket + periodically pulled to a personal machine/cloud drive). Weekly is plenty at this scale.
- Storage photos included in the export scope (or synced by the same script).
- Soft deletes + append-only history mean most "oops" moments are recoverable without touching backups at all.
- Every device's local DB is itself a warm copy of current state (not history) — a total server loss still leaves the household functional and re-uploadable.
- Restore procedure gets written down and **tested once** before we're deep in real data (part of Stream 1's verification checklist).

## 22. Testing Strategy

Proportionate to a two-person app, concentrated where breakage hurts:

- **Unit tests (highest value):** domain logic — grocery generation from meal plans, next-due calculations (cleaning rules, filter intervals), portion scaling, unit handling, conflict-resolution merge rules.
- **Sync engine tests:** the one component that can silently destroy data. Simulated two-client scenarios against a local harness: offline queues, interleaved edits, delete-vs-edit, resume after long offline. This suite is a gate for Stream 1/19.
- **Drift migration tests** (Drift's built-in schema verification) for every local schema change.
- **Database tests:** RLS policy tests (member vs non-member access per table) run against a local Supabase instance in CI; trigger tests for `updated_at`/history.
- **Edge Function tests:** tool registry validation, parameter checking, audit-row writing (AI model mocked).
- **Widget tests:** selective — Cooking Mode step navigation, inventory review/confirm screen (the safety gate), dashboard card rendering.
- **Integration:** a small smoke suite (sign in, create inventory item, see it on second simulated device). No large E2E farm.
- CI: GitHub Actions — analyze, format, unit + widget tests, migration checks on every PR.

## 23. Repository / Folder Structure

Single repo, app + backend together:

```
foodiehome/
├── ARCHITECTURE.md
├── docs/                     # stream plans, decisions (ADRs), runbooks (backup/restore)
├── app/                      # Flutter project
│   ├── lib/
│   │   ├── core/             # theme, device_profile, router, errors, utils
│   │   ├── data/
│   │   │   ├── local/        # Drift database, tables, DAOs, migrations
│   │   │   ├── remote/       # Supabase client wrappers
│   │   │   └── sync/         # outbox, delta pull, engine
│   │   ├── domain/           # entities, value types, domain services (pure Dart)
│   │   ├── features/         # feature-first modules
│   │   │   ├── dashboard/    #   each: presentation/ (with per-device layouts),
│   │   │   ├── inventory/    #   application/ (controllers), repository
│   │   │   ├── recipes/
│   │   │   ├── meal_plan/  grocery/  cooking/  fermentation/
│   │   │   ├── home_care/  assets/  foodie/  auth/  settings/
│   │   └── main.dart
│   ├── ios/                  # Runner + (later) App Intents Swift
│   └── test/
└── supabase/
    ├── migrations/           # numbered SQL, the only way schema changes
    ├── functions/
    │   ├── foodie-agent/     # agent loop
    │   ├── foodie-vision/    # camera proposals
    │   └── _shared/          # tool registry, db helpers, prompts
    └── seed/                 # dev seed data
```

## 24. Dependency Philosophy

- **Small, boring, replaceable.** Every dependency must be either (a) infrastructure with no reasonable hand-rolled alternative (Drift, Riverpod, go_router, supabase_flutter, freezed) or (b) trivially removable.
- Expected core set is roughly a dozen packages: the above plus image handling (`image_picker`, compression), `flutter_secure_storage`, `speech_to_text`-era packages *later*, and test tooling. No UI mega-kits, no state/network/DI frameworks beyond the chosen ones, no "Supabase offline sync" third-party layers (we own sync).
- Pin versions; upgrade deliberately (a scheduled pass, not automatic); every new dependency is named in the relevant stream plan before it's added.

## 25. Major Technical Risks

1. **Sync engine correctness** — the highest-risk component; a subtle bug silently loses household data. Mitigation: build it early (see §26 reorder), keep it dumb (LWW + append-only), test it as a gate, audit every overwrite.
2. **Old kitchen iPad (9th gen)** — must stay smooth as an always-on dashboard. Mitigation: performance budget from Stream 4/5 (test on that device from the first shell build), modest dashboard refresh rates, restrained animations. Always-on display + burn-in/screen-dimming and Guided Access behavior need real-device validation early.
3. **Voice/App Intents on Flutter** — the platform-channel + Swift intents seam is the fiddliest integration. Mitigation: architecture already isolates it (§16–17); build one trivial intent as a spike before committing Stream 18's scope.
4. **AI vision accuracy for fridge photos** — messy real fridges will yield mediocre detection. Mitigation: product framing is "assisted entry," confirmation screen always; expectation set that it accelerates, not replaces, entry.
5. **Scope creep** — 20 streams is a big product. Mitigation: closed streams (your rule 12–14), this document as the scope anchor, and per-stream verification checklists.
6. **Supabase dependency** — acceptable for a private app, but the weekly export (§21) plus a repo-defined schema means we can rebuild elsewhere (any Postgres + a job runner) if ever needed.
7. **Edge Function limits for long agent loops** — multi-tool chains + streaming can approach function time limits. Mitigation: cap tool iterations per turn; keep tools fast; revisit with a queue if real usage hits limits.

## 26. Recommended Changes to Your Proposal (before Stream 1)

Your plan is fundamentally sound. Changes I recommend, with reasons:

1. **Move sync forward — don't harden it at Stream 19.** Offline/sync is architecture, not polish; retrofitting an outbox onto features built online-first means rewriting every repository. Recommendation: the local DB + outbox + delta-pull engine is built in Stream 1 alongside the core schema, every subsequent feature uses it from day one, and Stream 19 becomes *verification* (chaos-style two-device testing), not construction.
2. **Move Camera Inventory (your Stream 7) after Grocery and Recipes.** It's the most experimental feature, depends on the AI plumbing (first built in Stream 3) and the inventory review UX, and nothing depends on *it*. Sequencing manual inventory → grocery → recipes → meal planning first gets the daily-use loop working sooner and derisks the schedule.
3. **Give Foodie a minimal read-only debut earlier than Stream 16.** Stream 3 builds the pipeline (Edge Function, conversations, tool registry, memory tables) with a couple of read-only tools; each feature stream then registers its tools as it completes. Stream 16 becomes "full chat UX," not "first time the agent works." This matches your "tools only after the feature is reliable" rule while letting the agent architecture be exercised continuously instead of big-banged.
4. **Merge Filters + Supplies (14) conceptually into the assets domain** (already reflected in §8): filters generalize to `tracked_components`, so future replaceables (water pitcher, vacuum parts, smoke-detector batteries) need zero schema work.
5. **Structured recipe steps from the start** (not free-text instructions) — Cooking Mode and voice are cheap later only if Stream 9 stores steps as ordered records with durations/temperatures.
6. Everything else — Flutter + Supabase, server-side AI, streams model, confirmation gates, conservative safety — I endorse as proposed.

### Proposed stream order (revised)

| # | Stream | Notes vs. your order |
|---|---|---|
| 0 | Architecture (this doc) | — |
| 1 | Core schema + household model + **local DB & sync engine** | sync pulled forward |
| 2 | Auth + household membership | — |
| 3 | Foodie core: agent pipeline, tool registry, memory foundation, 1–2 read-only tools | — |
| 4 | Responsive app shell + navigation + device profiles | — |
| 5 | Dashboard foundation | — |
| 6 | Food inventory (manual) | — |
| 7 | Grocery system | was 8 |
| 8 | Recipes (structured steps) | was 9 |
| 9 | Meal planning (+ grocery generation) | was 10 |
| 10 | Cooking Mode | was 11 |
| 11 | Camera inventory | was 7 — moved after the food loop |
| 12 | Fermentation Lab | — |
| 13 | Home Care | — |
| 14 | Assets: filters/components + household supplies | — |
| 15 | **Notification/reminder worker** (scheduler, channel adapters, Twilio SMS provider) | added after Stream 1 — runs once the domain data it watches exists |
| 16 | Expanded agent tool layer (mutating tools, undo) | was 15 |
| 17 | Full Foodie chat UX | was 16 |
| 18 | Voice | was 17 |
| 19 | App Intents / Siri | was 18 |
| 20 | Offline/sync **verification** + hardening | was 19 |
| 21 | UI polish, testing, reliability pass | was 20 |

Each stream ends with a verification checklist and stops for your approval, per your rules.

---

## 27. Notifications & Reminders (added in Stream 1)

Product decision after Stream 0: Foodie will eventually send reminders (morning/evening briefs, meal prep, fermentation, cleaning, maintenance, filters, shopping) over SMS via Twilio — with delivery channels interchangeable (push, SMS, email, kitchen-dashboard announcement).

Architecture (schema shipped in Stream 1; workers/providers are a later stream):

```
reminder_rules ──► notifications ──► notification_deliveries
 (why: schedule      (one channel-       (one row per channel
  or event)           neutral message)     attempt: sms/twilio, push/apns, …)
```

- **Rules, not records:** scheduled reminders reference the shared `recurrence_rules` table; event reminders (`filter due`, `starter feed due`, `food expiring`, `supply low`) watch domain state with thresholds in rule config. A future worker computes what fires; `dedupe_key` uniqueness makes generation idempotent. Thousands of occurrence rows are never pre-created.
- **Provider-agnostic by construction:** reminder logic never mentions Twilio; a delivery row records `channel` + `provider` after the fact. New channels are new worker adapters, zero schema change.
- **Fan-out is preference-driven:** `notification_preferences` (member × category × channel) decides who gets what, where. SMS numbers live on `profiles`.
- **Trust boundary:** clients manage rules/preferences and read results; `notifications`/`notification_deliveries` rows are created only by the service-role worker.

The reminder worker (scheduler + channel adapters + Twilio) is **Stream 15** — after assets, before the expanded agent tool layer, so event reminders have real data to watch (decided at Stream 1 approval).

---

## 28. Multi-agent ecosystem (recorded at Stream 2; not implemented)

Foodie is one of three separate personal agents: **Atlas** (school/academic), **Foodie** (household/food, this project), **Katie** (Keep Track: routines, workouts, calendar, personal planning). They remain **separate applications with separate databases**; a scoped interoperability layer connects them later. FoodieHome must not be redesigned around a shared database.

What this architecture guarantees now:

- **Provenance:** the `action_source` vocabulary (`user | foodie | atlas | katie | system`) is used across `record_history`, `agent_actions`, and `fermentation_logs` (migration 12), so cross-agent actions are attributable the day interop arrives.
- **Unified Morning Brief (future):** one combined morning SMS assembled by a coordinator from *structured briefing contributions* (source_agent, type, priority, start/end time, summary, metadata) — never direct cross-agent database access. Compatibility points already in place: the channel-neutral notification pipeline (`notifications` → `notification_deliveries`) can carry a brief regardless of who assembled it; nothing assumes Foodie is the only producer of a notification; delivery preferences are per category, not per agent. The coordinator itself is deliberately unbuilt and unscheduled.

---

*End of architecture document. Streams delivered so far: 1 (schema — `DATABASE.md`, `supabase/migrations/`), 2 (auth/membership — migration 12, `app/`). Decision log: `docs/DECISIONS.md`.*
