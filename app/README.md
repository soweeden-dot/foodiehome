# FoodieHome app

Flutter client for the FoodieHome household system. Architecture:
`../ARCHITECTURE.md` · Database: `../DATABASE.md` · Foodie agent: `../docs/FOODIE.md` · Decisions: `../docs/DECISIONS.md`.

## Running

Requires a Supabase project with the migrations from `../supabase/migrations`
applied and the `foodie-agent` Edge Function deployed. All Foodie tables live
in a dedicated `foodie` schema (this project is shared with Keep Track,
which owns `public` — see `../DATABASE.md` §0), so **`foodie` must be added
to the project's Exposed Schemas** (Project Settings → API in the Supabase
dashboard) before the app can reach any Foodie data — PostgREST serves
nothing outside that list. This client already defaults every query to
`foodie` (`postgrestOptions` in `main.dart`); no per-call schema handling is
needed elsewhere. Configuration is injected at build time:

```
flutter run \
  --dart-define=SUPABASE_URL=https://<project>.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
```

(`SUPABASE_ANON_KEY` is accepted as a fallback for legacy-format keys.) The
Anthropic API key is never a client build flag — it is a Supabase Edge
Function secret only (`supabase secrets set ANTHROPIC_API_KEY=...`).

## Tests

```
flutter analyze
flutter test
flutter build web --release --dart-define=... # structural build check
```

Tests run fully offline — Supabase, device storage, and Foodie sit behind
gateway seams (`AuthGateway`, `HouseholdGateway`, `FoodieGateway`,
`DeviceKeyValueStore`) and tests use in-memory fakes (`test/fakes.dart`).

## Layout

```
lib/
  core/       env/config, router, responsive layout resolver, device-local
              Kitchen Mode preference
  domain/     plain Dart models + pure rules
  data/       gateway interfaces + Supabase implementations
  features/
    auth/     sign-in/sign-up, household create/join (Stream 2)
    foodie/   chat controller + provisional chat screen (Stream 3)
    inventory/  household inventory: list/search/filter, add/edit/remove,
                approximate-level + quantity+unit + expiry tracking
    home_care/  cleaning tasks (complete/skip, due-date + rollover display)
                and apartment maintenance issues (report/resolve) at
                "/home-care"; tracked filters/components (log replacement)
                at "/supplies"
    shell/    production nav shell: phone bottom bar / tablet rail /
              Kitchen Mode chrome, destination list, route placeholders
    dashboard/  Home route boundary (Stream 5 builds the real cards)
    settings/   device + household settings, incl. Kitchen Mode toggle
                and the household member list
```

Kitchen Device Mode is a **device-local** UI preference (SharedPreferences,
key `device.kitchen_mode`) — never synced, never a household setting.
Enabling it on one device cannot affect another. See ARCHITECTURE.md §4 for
the full navigation/responsive/Kitchen Mode design.

`domain/recurrence.dart` computes cleaning/filter due dates and rollover at
read time (never stored) — the Dart half of the same algorithm as
`supabase/functions/_shared/recurrence.ts` on the Foodie agent side.

Feature screens beyond auth/shell/settings/inventory/home_care are
PROVISIONAL placeholders until their own stream lands (Recipes, Meal Plan,
Fermentation).
