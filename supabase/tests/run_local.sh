#!/usr/bin/env bash
# Local validation: throwaway Postgres cluster → two independent databases:
#
#   foodie_test              auth stub → migrations → Foodie's own
#                             functional test chain (smoke/membership/foodie).
#   foodie_coexistence_test  auth stub → simulated Keep Track `public`
#                             footprint → migrations → coexistence_test.sql,
#                             proving schema isolation concretely.
#
# Kept in separate databases deliberately: coexistence_test.sql signs up an
# extra auth user to exercise both apps' provisioning triggers, which would
# throw off the exact user/profile counts the functional tests assert.
#
# Requires Postgres server binaries (16+) on PATH or in
# /usr/lib/postgresql/*/bin. Must run as a non-root user.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WORK_DIR="$(mktemp -d)"
PORT="${PGPORT_TEST:-54999}"

PG_BIN="$(dirname "$(command -v initdb 2>/dev/null || ls -1 /usr/lib/postgresql/*/bin/initdb | sort -V | tail -1)")"

cleanup() {
  "$PG_BIN/pg_ctl" -D "$WORK_DIR/data" stop -m immediate >/dev/null 2>&1 || true
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

"$PG_BIN/initdb" -D "$WORK_DIR/data" -U postgres --auth=trust -E UTF8 >/dev/null
"$PG_BIN/pg_ctl" -D "$WORK_DIR/data" -o "-p $PORT -k $WORK_DIR" -l "$WORK_DIR/pg.log" start >/dev/null

PSQL=("$PG_BIN/psql" -h "$WORK_DIR" -p "$PORT" -U postgres -v ON_ERROR_STOP=1 -q)
run_sql() { "$PG_BIN/psql" -h "$WORK_DIR" -p "$PORT" -U postgres -d "$1" -v ON_ERROR_STOP=1 -f "$2"; }

# --- foodie_test: Foodie's own functional correctness -----------------------
"${PSQL[@]}" -d postgres -c "create database foodie_test"
run_sql foodie_test "$REPO_DIR/supabase/tests/auth_stub.sql"

for f in "$REPO_DIR"/supabase/migrations/*.sql; do
  echo "applying $(basename "$f") [foodie_test]"
  run_sql foodie_test "$f"
done

for t in smoke_test.sql membership_test.sql foodie_test.sql inventory_test.sql home_care_test.sql; do
  echo "running $t"
  run_sql foodie_test "$REPO_DIR/supabase/tests/$t"
done

# --- foodie_coexistence_test: schema isolation from a simulated Keep Track --
"${PSQL[@]}" -d postgres -c "create database foodie_coexistence_test"
run_sql foodie_coexistence_test "$REPO_DIR/supabase/tests/auth_stub.sql"
run_sql foodie_coexistence_test "$REPO_DIR/supabase/tests/keep_track_stub.sql"

for f in "$REPO_DIR"/supabase/migrations/*.sql; do
  echo "applying $(basename "$f") [foodie_coexistence_test]"
  run_sql foodie_coexistence_test "$f"
done

echo "running coexistence_test.sql"
run_sql foodie_coexistence_test "$REPO_DIR/supabase/tests/coexistence_test.sql"
