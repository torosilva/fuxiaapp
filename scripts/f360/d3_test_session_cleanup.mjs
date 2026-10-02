// STAGING ONLY — removes opening-count sessions created by the D3 screen test (admin-web/e2e/d3-conteo.spec.ts).
// Scope, strictly: f360.opening_counts with status 'cancelado' AND note starting 'Prueba de pantalla', plus their lines,
// "sin ficha" rows and change log. Never touches an open/approved count, inventory, homologation or anything else.
// Run: scripts/s00a/run.sh ../f360/d3_test_session_cleanup.mjs
import { loadEnv, psql } from '../s00a/lib.mjs';

loadEnv();
console.log(psql(`BEGIN;
CREATE TEMP TABLE _c ON COMMIT DROP AS SELECT id FROM f360.opening_counts WHERE status = 'cancelado' AND note LIKE 'Prueba de pantalla%';
ALTER TABLE f360.opening_count_changes DISABLE TRIGGER opening_count_changes_append_only;
WITH d AS (DELETE FROM f360.opening_count_changes WHERE count_id IN (SELECT id FROM _c) RETURNING 1) SELECT 'changes=' || count(*) FROM d;
ALTER TABLE f360.opening_count_changes ENABLE TRIGGER opening_count_changes_append_only;
WITH d AS (DELETE FROM f360.opening_count_unlisted WHERE count_id IN (SELECT id FROM _c) RETURNING 1) SELECT 'unlisted=' || count(*) FROM d;
WITH d AS (DELETE FROM f360.opening_count_lines WHERE count_id IN (SELECT id FROM _c) RETURNING 1) SELECT 'lines=' || count(*) FROM d;
WITH d AS (DELETE FROM f360.opening_counts WHERE id IN (SELECT id FROM _c) RETURNING 1) SELECT 'counts=' || count(*) FROM d;
SELECT 'left counts=' || count(*) FROM f360.opening_counts;
COMMIT;`).split('\n').filter((l) => l.includes('=')).join('  '));
