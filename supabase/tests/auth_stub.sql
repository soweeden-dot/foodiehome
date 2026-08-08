-- Minimal mimic of Supabase's auth schema so migrations run on vanilla
-- Postgres for local validation. NEVER deployed to the real project.
create schema auth;

-- Supabase's client-facing role; migrations reference it in GRANTs.
-- Roles are cluster-global (not per-database) in Postgres, and this stub
-- runs once per test database within the same cluster — guard against
-- "role already exists" on the second and subsequent runs.
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
end
$$;

create table auth.users (
  id                 uuid primary key default gen_random_uuid(),
  email              text,
  raw_user_meta_data jsonb default '{}'::jsonb
);

-- Supabase resolves auth.uid() from the request JWT; locally we read the same
-- GUC PostgREST would set, so tests can impersonate users with:
--   set request.jwt.claim.sub = '<uuid>';
create function auth.uid() returns uuid
language sql stable as
$$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
