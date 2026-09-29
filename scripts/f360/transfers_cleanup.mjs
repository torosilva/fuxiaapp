// STAGING ONLY — removes the synthetic 'ZZ PRUEBA T ' transfer fixtures (see transfer_fixtures.mjs for the exact scope).
// Run: scripts/s00a/run.sh ../f360/transfers_cleanup.mjs
import { loadEnv } from '../s00a/lib.mjs';
import { cleanupTransferFixtures } from './transfer_fixtures.mjs';
loadEnv();
const left = cleanupTransferFixtures();
console.log(left === '0' ? 'synthetic transfer fixtures removed (left=0)' : `WARNING left=${left}`);
process.exit(left === '0' ? 0 : 1);
