#!/bin/sh
# Tests SQL du projet Supabase du SITE.
# Usage : PGHOST=/tmp PGPORT=5499 PGUSER=postgres ./run_tests.sh  (base "solea_site_test" recréée)
set -e
DIR=$(cd "$(dirname "$0")" && pwd)
psql -q -c "drop database if exists solea_site_test" -c "create database solea_site_test"
P="psql -q -v ON_ERROR_STOP=1 -d solea_site_test"
$P -f "$DIR/supabase_auth_stub.sql" 2>/dev/null
for f in "$DIR"/../migrations/*.sql; do $P -f "$f"; done
for f in "$DIR"/../migrations/*.sql; do $P -f "$f"; done # rejouable sans erreur
for t in "$DIR"/test_*.sql; do $P -f "$t" 2>&1 | grep -E "OK:|ÉCHEC|ERROR"; done
