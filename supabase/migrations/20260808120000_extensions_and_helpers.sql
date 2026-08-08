-- Stream 1 · Migration 01 — schema foundation, extensions, shared helpers
--
-- SHARED-PROJECT NOTE: this project also hosts Keep Track ("Katie"), which
-- owns the `public` schema and must not be touched. Every Foodie-owned
-- object lives in the dedicated `foodie` schema created below — this is the
-- entire isolation boundary. See docs/DECISIONS.md and DATABASE.md §"Schema
-- isolation" for the full rationale.
--
-- Conventions used across all migrations (see DATABASE.md):
--   * UUID primary keys, client-generatable (offline creates).
--   * Every household-owned row carries household_id (denormalized onto child
--     tables so RLS and sync never need joins).
--   * created_at / updated_at on every table; updated_at is trigger-maintained
--     and is the sync delta-pull watermark.
--   * Soft delete via deleted_at on user-editable synced tables; append-only
--     history tables have neither updated_at churn nor deletes.

create schema if not exists foodie;

-- pgcrypto is project-wide infrastructure, not app-owned data — left
-- unscheduled (default extension schema) and guarded with IF NOT EXISTS so
-- this is a safe no-op if Keep Track (or Supabase itself) already enabled
-- it. NOTE: because Foodie's SECURITY DEFINER functions pin
-- search_path = foodie (never public/extensions — see migration 02), they
-- cannot rely on pgcrypto's gen_random_bytes() being unqualified-reachable
-- regardless of which schema it landed in. Foodie's own code therefore
-- avoids gen_random_bytes() entirely and derives random hex from
-- gen_random_uuid() instead, which has been a core Postgres builtin
-- (pg_catalog, always implicitly searched) since PG13 — see the invite-code
-- generation in migrations 02 and 12. This extension is still enabled here
-- because id columns' gen_random_uuid() defaults are schema-agnostic by the
-- same reasoning, and leaving pgcrypto available costs nothing and may
-- already be relied on by Keep Track.
create extension if not exists pgcrypto;

-- Trigger: keep updated_at current on every write. Attached per-table in the
-- domain migrations. Not SECURITY DEFINER — it only touches NEW/OLD row
-- fields, so it carries no elevated privilege and needs no search_path
-- hardening; still schema-qualified for consistency and to keep it firmly
-- out of public.
create or replace function foodie.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- Membership helper functions (is_household_member etc.) are defined in the
-- core migration, after the tables they reference exist.
