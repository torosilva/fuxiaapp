// STAGING ONLY — removes the C3 demo ("Demo · …" store, channel, roles, customer, its cutover, ledger events and sales).
// Exact scope and safety checks: c3_fixtures.mjs. Run: scripts/s00a/run.sh ../f360/demo_c3_cleanup.mjs
import { loadEnv } from '../s00a/lib.mjs';
import { cleanupC3Fixtures } from './c3_fixtures.mjs';
loadEnv();
const left = cleanupC3Fixtures('Demo · ');
console.log(left === '0' ? 'Demo eliminada (left=0)' : `WARNING left=${left}`);
process.exit(left === '0' ? 0 : 1);
