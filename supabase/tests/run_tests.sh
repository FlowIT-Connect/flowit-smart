#!/bin/sh
# Usage : PGHOST=/tmp PGPORT=5499 PGUSER=postgres ./run_tests.sh  (base "flowit_test" recréée)
set -e
DIR=$(cd "$(dirname "$0")" && pwd)
MIG="$DIR/../migrations"
psql -q -c "drop database if exists flowit_test" -c "create database flowit_test"
P="psql -q -v ON_ERROR_STOP=1 -d flowit_test"
$P -f "$DIR/supabase_auth_stub.sql" 2>/dev/null
for f in "$MIG"/*.sql; do $P -f "$f"; done
for t in "$DIR"/test_*.sql; do $P -f "$t" 2>&1 | grep -E "OK:|ÉCHEC|ERROR"; done
