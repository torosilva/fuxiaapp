// STAGING ONLY: runs the Fuxia 360 rolled-back database test files and prints PASS/FAIL per check.
// Run: scripts/s00a/run.sh ../f360/db_tests.mjs      (lib refuses any production target)
import { readFileSync } from 'node:fs';
import { loadEnv, psql } from '../s00a/lib.mjs';

loadEnv();
let failed = 0;
for (const f of ['f360_tests', 'f360_p21_tests', 'f360_p22_tests', 'f360_p23a_tests', 'f360_b4_tests', 'f360_c1c2_tests', 'f360_s02_tests', 'f360_s05_s03_tests', 'f360_transfers_tests', 'f360_c3_tests', 'f360_currency_tests', 'f360_n2_tests', 'f360_d2_tests', 'f360_archive_tests', 'f360_adjust_tests', 'f360_d3_tests', 'f360_catalog_tests', 'f360_d4_tests', 'f360_reservations_tests', 'f360_reservations_app_tests', 'f360_make_to_order_tests', 'f360_custom_requests_tests', 'f360_consolidation_tests']) {
  const out = psql(readFileSync(`supabase/staging/${f}.sql`, 'utf8')).split('\n').filter((l) => /^(PASS|FAIL) \|/.test(l));
  failed += out.filter((l) => l.startsWith('FAIL')).length;
  console.log(`== ${f} (${out.length} checks)\n${out.join('\n')}`);
}
console.log(failed ? `\n${failed} FAILED` : '\nALL PASS');
process.exit(failed ? 1 : 0);
