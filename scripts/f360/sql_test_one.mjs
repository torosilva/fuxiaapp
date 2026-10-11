// STAGING ONLY: runs ONE rolled-back database test file and prints its PASS/FAIL lines (+ a summary).
// A line `-- @include <path>` is replaced by that file's contents (e.g. a migration not yet applied to staging, rehearsed
// inside the test's own transaction). The test file must end with ROLLBACK.
// Run: scripts/s00a/run.sh ../f360/sql_test_one.mjs supabase/staging/<file>.sql      (lib refuses any production target)
import { readFileSync } from 'node:fs';
import { loadEnv, psql } from '../s00a/lib.mjs';

loadEnv();
const file = process.argv[2];
if (!file) throw new Error('uso: sql_test_one.mjs <archivo.sql>');
const sql = readFileSync(file, 'utf8').replace(/^-- @include (\S+)\s*$/gm, (_, p) => readFileSync(p, 'utf8'));
if (!/ROLLBACK;\s*$/.test(sql)) throw new Error('ABORT: the test file must end with ROLLBACK;');
const out = psql(sql).split('\n');
const lines = out.filter((l) => /^(PASS|FAIL) \|/.test(l));
for (const l of out) if (/^(PASS|FAIL|INFO) \|/.test(l)) console.log(l);
const fail = lines.filter((l) => l.startsWith('FAIL')).length;
console.log(`\n${lines.length - fail} PASS / ${fail} FAIL`);
process.exit(fail ? 1 : 0);
