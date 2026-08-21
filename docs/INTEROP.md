# Foodie ↔ Katie ↔ Atlas — future interoperability (documentation only)

**Status: not implemented, not activated, no code exists for any of this.** This
document exists so future work has a contract to build toward, per the
2026-08-08 coordination decision (`docs/DECISIONS.md`) — write down what
*should* eventually be exchanged, without wiring anything now. Nothing here
authorizes cross-agent database access, a shared table, or a live
integration; ARCHITECTURE.md's constraints stand: Foodie must not become the
global scheduler, must not own academic/personal-routine data, and no
cross-agent writes activate until explicitly approved in a later stream.

## Identity, first

Foodie, Katie (Keep Track), and Atlas are three separate applications. Two
different relationships to "the same Sofia":

- **Foodie ↔ Katie:** share one Supabase project, and therefore one
  `auth.users` table. Once Katie's Auth0 → Supabase bridge is live, Sofia's
  `auth.users.id` in that project already *is* the identity Foodie's own
  `foodie.profiles` hangs off of (see `DATABASE.md` §0). No mapping layer is
  needed between these two specifically — it falls out of the schema
  isolation design for free.
- **Foodie/Katie ↔ Atlas:** presumed separate infrastructure entirely. The
  connecting thread is the shared **Auth0 subject** (`sub` claim) — a
  provider-level identity, independent of which app's database it lands in.
  Any future interop message between Foodie and Atlas should carry that
  subject as the household-member identifier, not an app-local UUID, so a
  message can be attributed to "this specific person" regardless of which
  app's user table assigned them which internal id.

Nothing about this requires Foodie's schema to change today. `foodie.profiles.id`
already equals the shared `auth.users.id`; that's the correct foundation.

## Why not build the interop layer now

- Cross-agent writes are explicitly not activated yet (this decision, and
  the original architecture's "do not implement Atlas/Katie integration").
- Katie's own identity foundation isn't fully verified in production yet —
  building against a moving foundation invites rework.
- A concrete contract is more useful once at least one more real agent
  (Katie) has a working morning-brief-style consumer to design against,
  rather than guessing its shape from Foodie's side alone.

## Prospective exchange surfaces

Each item below is a *candidate* payload Foodie might eventually contribute
to or consume from a cross-agent surface (most plausibly the Unified Morning
Brief coordinator described in ARCHITECTURE.md §27/§28, and/or a narrower
point-to-point interop call). None of these tables, functions, or message
formats exist yet.

### Foodie → Katie / Atlas (Foodie is the source)

| Surface | What it would carry | Plausible consumer |
|---|---|---|
| **Meal plans** | Today's/this week's planned meals (date, slot, title) — not full recipes | Katie's calendar (so a planned dinner shows as a household event); Atlas is unlikely to care |
| **Grocery needs** | Items currently on the household grocery list, especially anything time-sensitive ("need to shop today") | Katie, if it ever schedules "run errands" style reminders |
| **Household tasks (cleaning/maintenance) due** | Task name, area, due date, assigned member | Katie's task/reminder surface, if it becomes the household's single task inbox |
| **Reminders due** | Any Foodie-owned reminder (filter replacement, fermentation check, low supply) in the structured `{source_agent, type, priority, start_time, end_time, summary, metadata}` shape already anticipated by the notification architecture | The Unified Morning Brief coordinator specifically |
| **Fermentation schedules** | Next-check times for active fermentation projects ("check the starter at 9am") | Katie's calendar, if fermentation check-ins are worth a calendar slot |
| **Household events** | Meal-prep sessions, cooking-mode sessions in progress, anything worth a shared household calendar entry | Katie's calendar |

### Katie / Atlas → Foodie (Foodie is the consumer)

Not yet scoped in either direction with the same care as the above, since
Foodie's agent explicitly declines school/calendar/routine requests today
(see `docs/FOODIE.md`'s system prompt rules) and has no reason to read
Katie/Atlas data yet. Worth naming as a placeholder for the eventual
conversation: Katie's household calendar (so Foodie can avoid suggesting a
big cook night when the household has evening plans) and Atlas's school
schedule (so meal-prep timing can account for it). Neither is committed to;
recorded here only so this doesn't get forgotten when the coordinator is
eventually designed.

## Shape, when it's built (not now)

Consistent with ARCHITECTURE.md §28's existing compatibility points:

- Structured contribution payloads only — `{source_agent, type, priority,
  start_time, end_time, summary, metadata}` — never direct database access
  between agents.
- Foodie is one contributor among several, never the coordinator or the
  global scheduler.
- The channel-neutral notification pipeline (`foodie.notifications` →
  `foodie.notification_deliveries`) is the plausible delivery mechanism on
  Foodie's side; it was designed provider-agnostic specifically so it could
  carry a cross-agent-assembled brief without schema change.
- Any eventual interop layer is a new, explicitly-scoped stream — not an
  extension folded into an unrelated one.
