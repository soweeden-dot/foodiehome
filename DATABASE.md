# FoodieHome — Database Design (Streams 1–2)

**Status:** Stream 1 core schema + Stream 2 membership/provenance.
**Migrations:** `supabase/migrations/` (12 files, applied in filename order). Schema changes happen **only** through new migration files — never by editing applied migrations, never through the Supabase dashboard.

All 32 tables were validated against a real Postgres 16 instance (migrations apply cleanly; RLS member/outsider behavior, membership RPCs, and audit triggers are exercised by the test suite — see `supabase/tests/`).

---

## 1. Conventions (apply to every table)

| Convention | Rule | Why |
|---|---|---|
| Primary keys | `uuid`, defaulting to `gen_random_uuid()` but **client-generatable** | Offline devices must create rows without asking the server for an id; retried inserts are idempotent |
| Ownership | Every household-owned row carries `household_id` directly — including child rows like `recipe_steps` | RLS and sync never need joins; one policy pattern everywhere |
| Timestamps | `created_at` + trigger-maintained `updated_at` on every table | `updated_at` is the sync delta-pull watermark |
| Soft delete | `deleted_at` on user-editable synced tables | Deletes must be syncable to offline devices; accidental deletes recoverable |
| Append-only | History/log tables get INSERT+SELECT policies only where noted | The database, not app discipline, enforces immutability |
| Enums | Postgres enums for closed vocabularies (roles, statuses, channels); **free text** for open ones (food categories, rooms, units) | Enums where invalid values would break logic; freedom where users invent values |
| jsonb | Used only for shapes that vary by nature (fermentation payloads, notification payloads, checklists, preference values) — never for data we query relationally | Correctness first; structure where structure is needed |
| Naming | `snake_case`, plural table names, `idx_`/`trg_` prefixes | Consistency |

## 2. Ownership model

```
auth.users ──1:1── profiles
                     │
households ──*── household_members ──*── profiles      (role: admin | member)
    │
    └── every domain table below (household_id NOT NULL, ON DELETE CASCADE)
```

- `profiles` extends Supabase's `auth.users` (auto-created by trigger on signup). Contact details live here — including `phone_number` (E.164), which the future SMS channel reads.
- `households` — expect one row in practice; modeled properly anyway. Creating a household auto-inserts the creator as `admin` (SECURITY DEFINER trigger, since the creator isn't yet a member when RLS would be checked). `invite_code` exists now; the redemption flow is Stream 2.
- `household_members` is the join table every RLS policy consults. `role` distinguishes `admin` (manage household + roster) from `member` (everything else) — future guests won't need a migration.
- `devices` — one row per app installation (kitchen iPad, personal iPad, iPhone). Devices are *not* identities; they support layout pinning and sync bookkeeping.
- **Deleting a household cascades everywhere.** There is deliberately **no client-side DELETE policy on `households`** — destroying years of household data requires the service role (a deliberate, out-of-app act).

## 3. Table reference

### Core (`20260808120100_core.sql`)

| Table | Purpose | Key relationships |
|---|---|---|
| `profiles` | App identity for each auth user; display name, avatar, phone | 1:1 `auth.users` |
| `households` | The household; timezone (used to interpret recurrence times), invite code | `created_by` → profiles |
| `household_members` | Membership + role | household ⇄ profile, unique pair |
| `devices` | App installations; `profile` enum (`kitchen_ipad`/`ipad`/`phone`/`other`) | → household, optional owner |

### Recurrence (`20260808120200_recurrence.sql`)

| Table | Purpose |
|---|---|
| `recurrence_rules` | One shared vocabulary for everything that repeats: "every `interval_count` `interval_unit`" (+ optional weekday, month-day, month, local time-of-day, anchor date). Twice-weekly = two rules or two tasks; weekly/biweekly/monthly/quarterly/biannual/annual are all `(unit, count)` pairs. |

**Design decision:** occurrences are always **computed** (last completion/fire + rule), never pre-generated as rows. Used by both `cleaning_tasks` and `reminder_rules`; anything future that repeats reuses it. Times are interpreted in the household's timezone.

### Food (`20260808120300_food.sql`)

| Table | Purpose | Key relationships |
|---|---|---|
| `inventory_locations` | Pantry/fridge/freezer/user-defined places | → household |
| `food_items` | The household's food **catalog** — identity, not stock: canonical name, aliases, category, default unit/shelf-life/location | → default location |
| `inventory_items` | Stock on hand: quantity+unit **or** approximate `supply_level` (both optional — "some rice" is valid data); expiry, opened date, `source` | → food_items, → location |
| `recipes` | Title, servings, times, tags, image path, jsonb nutrition | — |
| `recipe_steps` | **Structured, ordered steps** with optional duration (drives suggested timers) and temperature | → recipe, unique (recipe, position) |
| `recipe_ingredients` | Quantity/unit/preparation, ordered, optional flag | → recipe, → food_items |
| `meal_plans` | Date-ranged container | — |
| `meal_plan_entries` | One row per date × slot: recipe **or** free-text title ("eating out"); per-member servings (jsonb keyed by user id); status | → plan, → recipe |
| `grocery_lists` | Named lists, archivable | — |
| `grocery_items` | Item with quantity, store section, `source` + `source_ref`, checked state (`checked_at`/`checked_by`) | → list, → food_items |

**Design decisions:**
- **`food_items` is the hub.** Recipes, inventory, and grocery items all reference the same catalog row — this single decision is what makes "we used the last onion", intelligent grocery generation, and expiry-aware meal suggestions possible. Free-text `name` fallbacks exist everywhere (with a CHECK that at least one of `food_item_id`/`name` is present) so data entry never fights the user.
- **`source_ref` on grocery items** records what generated an item (a meal-plan entry, a low supply), so recalculation *updates* generated items instead of duplicating them, and never touches manual ones.
- **Steps are structured from day one** because Cooking Mode and voice ("next step", "how much butter") are only cheap later if the data is already shaped for them.
- Units are free text in Stream 1; unit normalization is app-layer domain logic (a lookup table can be added later without migration pain).

### Fermentation (`20260808120400_fermentation.sql`)

| Table | Purpose | Key relationships |
|---|---|---|
| `fermentation_projects` | Live process: type, status, stage, jsonb target params (ratios, flour type, expected temps), `next_check_at`, safety notes | — |
| `fermentation_logs` | **One append-only stream** — `log_type` (observation/feeding/turning/temperature/stage_change/ai_observation) + structured jsonb payload + free-text notes; `author` = user \| foodie | → project |
| `fermentation_photos` | Storage path + metadata; optionally attached to a log | → project, → log |

**Design decisions:** one log stream instead of separate feeding/turning/observation tables — "log that I turned my cocoa at 9:15 and it smells more acidic" is a single row (`log_type='turning'`, notes carry the smell). Payload examples: `{"starter_g":10,"flour_g":50,"water_g":50,"flour_type":"rye"}`, `{"temp_c":31}`. AI observations are ordinary rows with `author='foodie'` — visible, auditable, never silently authoritative. `next_check_at` is what event-driven reminders (`fermentation_check_due`, `starter_feed_due`) will watch.

### Home care (`20260808120500_home_care.sql`)

| Table | Purpose | Key relationships |
|---|---|---|
| `cleaning_tasks` | Non-daily task: area, jsonb checklist template, assignee, active flag | → recurrence_rules, → profile |
| `cleaning_completions` | Append-history: who/when + **checklist snapshot** + notes | → task |

**Next due = last completion + rule** (or rule anchor if never completed) — computed in the app/agent, stored nowhere, so it can never go stale. The snapshot keeps history truthful even if the task template changes later.

### Assets (`20260808120600_assets.sql`)

| Table | Purpose | Key relationships |
|---|---|---|
| `tracked_components` | Generalized "filters": kind, system ("Kitchen fridge"), component, brand/model, installed date, `replace_interval_days`, spares count, product URL | — |
| `component_replacements` | Append-history: replaced on/by, notes | → component |
| `household_supplies` | Consumables: `tracking_mode` = `count` (23 tablets, with `restock_threshold`) or `level` (full/good/low/almost_empty/out) | — |

**Design decisions:** filters are one *kind* of tracked component, so any future replaceable (batteries, vacuum parts) needs zero schema work. Replacing a filter = insert a replacement row + app decrements spares; next replacement is computed from the latest replacement date (falling back to `installed_on`) + interval. `supply_level` is the same enum inventory uses — "low/out" has one meaning app-wide, which is what lets Foodie add low supplies to grocery lists later (`entry_source='low_supply'`, `source_ref` = supply id).

### Preferences (`20260808120700_preferences.sql`)

| Table | Purpose |
|---|---|
| `household_preferences` | Namespaced key/value store (`"food.dislikes"`, `"dashboard.cards"`): household-wide when `user_id` is null, per-member when set (`UNIQUE NULLS NOT DISTINCT (household_id, user_id, key)`) |

Typed preference columns are deliberately avoided — shapes will evolve constantly and none are queried relationally. Foodie's curated memory store is **not** this table; it arrives in Stream 3 with its own confirmation/visibility semantics.

### Notifications (`20260808120800_notifications.sql`) — see §6

`reminder_rules`, `notifications`, `notification_deliveries`, `notification_preferences`.

### Foodie (`20260808120900_foodie.sql`)

| Table | Purpose | Key relationships |
|---|---|---|
| `agent_conversations` | Conversation container; `context_tag` (chat/cooking/voice/scan) | — |
| `agent_messages` | Role (user/assistant/system/tool) + content + jsonb payload for tool blocks | → conversation |
| `agent_actions` | **Intent-level audit**: one row per tool invocation — tool name, input, status (proposed/executed/failed/reverted), result summary, affected records, undo hint, error | → conversation, → message |

Storage only in Stream 1 — no agent code, no tools. `agent_actions` is written exclusively by the Edge Function tool executor (service role); clients can read but never write their audit trail.

### Audit (`20260808121000_audit.sql`) — see §5

`record_history`.

### Membership & provenance (`20260808180000_membership_and_provenance.sql`) — Stream 2

**Provenance.** The `action_source` enum (`user | foodie | atlas | katie | system`) is the shared vocabulary for *what kind of actor* did something — chosen for compatibility with the wider multi-agent ecosystem (Atlas and Katie are separate apps; see `docs/DECISIONS.md`). It appears as:

- `record_history.source` — filled by the audit trigger from the `app.action_source` GUC (default `'user'`). Only server-side code (Edge Functions, workers) can set that GUC; PostgREST clients cannot, so provenance is not client-spoofable through the API.
- `agent_actions.source` — default `'foodie'`; a future interop layer would write `'atlas'`/`'katie'`.
- `fermentation_logs.author` — migrated from the old two-value `log_author` enum (dropped).

**Membership RPCs** (SECURITY DEFINER, `authenticated`-only EXECUTE):

| Function | Behavior |
|---|---|
| `redeem_household_invite(code)` | Case-insensitive; joins as `member`; idempotent for existing members; definer because the caller isn't yet a member. Errors: `P0002` unauthenticated, `P0003` invalid code. |
| `regenerate_invite_code(hh)` | Admin-only (`P0004`); rotates and returns the new code; old code immediately dead. |
| `leave_household(hh)` | Removes own membership (`P0005` if not a member). |

**Last-admin protection:** a `BEFORE UPDATE OR DELETE` trigger on `household_members` rejects removing or demoting a household's only admin (`P0001`). Combined with households being client-undeletable, a household can never be orphaned from the app; actual deletion stays a deliberate service-role act.

## 4. Relationship map (condensed)

```
households ─┬─ household_members ── profiles ── auth.users
            ├─ devices
            ├─ recurrence_rules ◄──┬─ cleaning_tasks ── cleaning_completions
            │                      └─ reminder_rules ── notifications ── notification_deliveries
            ├─ notification_preferences (× profiles × category × channel)
            ├─ inventory_locations ◄─┬─ food_items ◄──┬─ inventory_items
            │                        │                ├─ recipe_ingredients ── recipes ── recipe_steps
            │                        │                └─ grocery_items ── grocery_lists
            ├─ meal_plans ── meal_plan_entries ──► recipes
            ├─ fermentation_projects ── fermentation_logs ◄─ fermentation_photos
            ├─ tracked_components ── component_replacements
            ├─ household_supplies
            ├─ household_preferences
            ├─ agent_conversations ── agent_messages ◄─ agent_actions
            └─ record_history (written by triggers only)
```

## 5. Audit strategy

Two complementary layers, both append-only:

1. **`agent_actions`** — *intent*: what Foodie did and why ("removed Friday dinner at your request, updated 3 grocery items"). Written only by the server-side tool executor.
2. **`record_history`** — *data*: an AFTER trigger (`log_record_history()`, SECURITY DEFINER) on 18 significant mutable tables records every INSERT (full row), UPDATE (per-column old→new diff, `updated_at` churn excluded, pure no-ops skipped), and DELETE (full row), with `changed_by = auth.uid()`. It captures user, agent, and sync writes identically — including sync overwrites that discarded a concurrent value, which is the safety net promised in ARCHITECTURE §10.

Deliberately **not** audited: append-only tables (their inserts *are* their history: completions, replacements, photos), high-volume/low-value traffic (agent messages, notifications, deliveries), and `devices`/`profiles`. Clients have SELECT (household-scoped) and nothing else; there are no INSERT/UPDATE/DELETE policies, so immutability is enforced by the database.

## 6. Notification architecture

**Requirement:** SMS via Twilio eventually, but reminder logic must never couple to Twilio. Delivery channels (push / SMS / email / kitchen-dashboard announcement) must be interchangeable.

**Design — three layers, provider-agnostic by construction:**

```
reminder_rules ── WHY a reminder exists (per household, per category)
   │   kind='scheduled' → recurrence_rules   ("Sunday 08:00 morning brief")
   │   kind='event'     → event_type + config ("filter due", {"days_before_due": 7})
   ▼  (future worker evaluates rules; nothing is pre-generated)
notifications ── ONE channel-neutral message instance
   │   title/body/payload, scheduled_for, status, dedupe_key
   ▼  (future worker fans out by reading notification_preferences)
notification_deliveries ── one row PER CHANNEL attempt
       channel='sms', provider='twilio', provider_message_id, status, error
```

Why this shape:

- **No pre-generated occurrences.** "Every Sunday 8:00" is one `reminder_rules` row pointing at one `recurrence_rules` row. A future scheduler computes what should fire; `dedupe_key` (`"morning_brief:2026-08-09"`, unique per household) makes generation idempotent — a retried or duplicated worker run cannot double-text you.
- **Event-driven reminders are rules too**, watching domain state the schema already exposes: `tracked_components` next-due, `fermentation_projects.next_check_at`, `inventory_items.expires_on`, `household_supplies` low/out. Thresholds live in the rule's `config` jsonb.
- **Twilio is a cell value, not an architecture.** A notification knows nothing about transport. Adding email or dashboard announcements later = new `delivery_channel` usage + a new provider adapter in the worker — zero schema change to rules or notifications. Provider message ids and errors are recorded per attempt for debugging ("did the SMS actually send?").
- **Per-person choice:** `notification_preferences` is member × category × channel opt-in; the fan-out consults it. SMS numbers live on `profiles.phone_number`.
- **RLS split:** members manage rules and their own preferences; generated `notifications`/`notification_deliveries` are member-readable (and notifications member-updatable, for dismissing) but **created only by the service-role worker** — clients cannot forge deliveries.

Explicitly out of Stream 1 scope (schema exists, code does not): the scheduler/worker, channel adapters, Twilio integration, brief content generation.

## 7. Row Level Security

**One pattern everywhere:** `is_household_member(household_id)` — a `SECURITY DEFINER` SQL function checking `household_members` for `auth.uid()` (definer so policies on `household_members` itself don't recurse). Every one of the 32 tables has RLS enabled; standard domain tables get a single `FOR ALL USING/WITH CHECK` member policy.

Exceptions to the standard policy:

| Table | Policy | Reason |
|---|---|---|
| `profiles` | read self + household co-members; write self | Identity |
| `households` | member read; authenticated self-create; admin update; **no delete** | Household destruction is service-role-only |
| `household_members` | member read; admin manage; self-delete (leave); creator bootstrap via definer trigger | Roster control |
| `agent_actions` | member SELECT only | Written solely by server-side tool executor |
| `record_history` | member SELECT only | Written solely by the definer audit trigger |
| `notifications` | member SELECT/UPDATE | Created by service-role worker |
| `notification_deliveries` | member SELECT only | Created by service-role worker |
| `notification_preferences` | own-row manage; member read | Personal settings |
| `agent_messages` | member SELECT/INSERT (no update/delete) | Conversation records immutable from clients |

**Stated assumptions:**

1. **`authenticated` is the only client-facing role.** The `anon` key can hit the API but every policy requires `auth.uid()` to resolve to a household member, so anonymous access yields empty sets/denials. No policies target `anon`.
2. **All members are peers on domain data.** Roles gate only household/roster management. Assignment columns (`assigned_user_id`, `recipient_user_id`) are informational, not access control — appropriate for a two-person household and revisitable via policy changes alone.
3. **Edge Functions run with the caller's JWT by default** (RLS applies); the service role is used only for the narrow writer paths named above and always derives household scope server-side.
4. **Supabase's default grants** (`authenticated` gets table privileges; RLS restricts rows) are assumed; the local validation harness replicates this.
   4a. **Invite codes are the join secret.** Anyone with a valid code and an account can join the household as `member`. Acceptable for a two-person household because codes are shared out-of-band, rotatable by admins (`regenerate_invite_code`), and every join is visible in the roster. Expiring codes can be added later without schema changes beyond a column.
5. Cross-table integrity of denormalized `household_id` (e.g., a step's `household_id` matching its recipe's) is the app layer's job in Stream 1; hardening triggers can be added later without breaking anything. RLS is not weakened by this: writing a mismatched row requires membership in the *claimed* household, which the attacker doesn't have, and reads scope by the row's own `household_id`.

## 8. Sync-relevant schema features (engine arrives later in Stream 1's app side / Stream 19 verification)

- Client-generatable UUID PKs → offline creates, idempotent retries.
- Trigger-maintained `updated_at` → per-table delta-pull watermark (indexes on `(household_id, updated_at)` can be added when the engine lands; deliberately not speculating now).
- `deleted_at` soft deletes → deletions propagate like any other update.
- Append-only streams (logs, completions, replacements) → conflict-free by construction.
- `record_history` captures overwrites → LWW conflict losers are never silently unrecoverable.

## 9. Validation

`supabase/tests/` contains the local validation harness used for Stream 1 (no Docker needed):

- `auth_stub.sql` — minimal `auth` schema mimic (users table + `auth.uid()` reading the request GUC) so migrations run on vanilla Postgres.
- `smoke_test.sql` — applies after the migrations and asserts: profile auto-creation, creator-becomes-admin, member read/write access, outsider denial (households/inventory/audit all empty for non-members), append-only enforcement on `record_history`, audit diff correctness, scheduled-reminder CHECK constraint, and notification dedupe uniqueness.
- `run_local.sh` — spins a throwaway cluster, runs stub → migrations → smoke test.

Against the real Supabase project, the same migrations apply via `supabase db push` / `supabase migration up`; the stub is never deployed.
