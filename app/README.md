# FoodieHome app

Flutter client for the FoodieHome household system. Architecture:
`../ARCHITECTURE.md` · Database: `../DATABASE.md` · Decisions: `../docs/DECISIONS.md`.

## Running

Requires a Supabase project with the migrations from `../supabase/migrations`
applied. Configuration is injected at build time:

```
flutter run \
  --dart-define=SUPABASE_URL=https://<project>.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
```

(`SUPABASE_ANON_KEY` is accepted as a fallback for legacy-format keys.)

## Tests

```
flutter analyze
flutter test
```

Tests run fully offline — the Supabase SDK sits behind the `AuthGateway` /
`HouseholdGateway` seams and tests use in-memory fakes (`test/fakes.dart`).

## Layout

```
lib/
  core/       env/config
  domain/     plain Dart models + pure rules
  data/       gateway interfaces + Supabase implementations
  features/   feature modules (auth today; shell arrives in Stream 4)
```

Screens under `features/` are PROVISIONAL until the Stream 4 app shell.
