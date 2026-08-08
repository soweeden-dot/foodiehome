-- Stream 1 · Migration 01 — extensions, shared helper functions
--
-- Conventions used across all migrations (see DATABASE.md):
--   * UUID primary keys, client-generatable (offline creates).
--   * Every household-owned row carries household_id (denormalized onto child
--     tables so RLS and sync never need joins).
--   * created_at / updated_at on every table; updated_at is trigger-maintained
--     and is the sync delta-pull watermark.
--   * Soft delete via deleted_at on user-editable synced tables; append-only
--     history tables have neither updated_at churn nor deletes.

create extension if not exists pgcrypto;

-- Trigger: keep updated_at current on every write. Attached per-table in the
-- domain migrations.
create or replace function public.set_updated_at()
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
