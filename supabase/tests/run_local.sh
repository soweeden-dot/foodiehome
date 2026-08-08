#!/usr/bin/env bash
# Stream 1 local validation: throwaway Postgres cluster → auth stub →
# all migrations in order → smoke test. Requires Postgres server binaries
# (16+) on PATH or in /usr/lib/postgresql/*/bin. Must run as a non-root user.
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

"${PSQL[@]}" -d postgres -c "create database foodie_test"
"${PSQL[@]}" -d foodie_test -f "$REPO_DIR/supabase/tests/auth_stub.sql"

for f in "$REPO_DIR"/supabase/migrations/*.sql; do
  echo "applying $(basename "$f")"
  "${PSQL[@]}" -d foodie_test -f "$f"
done

for t in smoke_test.sql membership_test.sql; do
  echo "running $t"
  "$PG_BIN/psql" -h "$WORK_DIR" -p "$PORT" -U postgres -d foodie_test \
    -v ON_ERROR_STOP=1 -f "$REPO_DIR/supabase/tests/$t"
done
