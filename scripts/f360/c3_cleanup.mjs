// STAGING ONLY — removes the synthetic 'ZZ PRUEBA C3 ' fixtures (see c3_fixtures.mjs for the exact scope).
// Run: scripts/s00a/run.sh ../f360/c3_cleanup.mjs
import { loadEnv } from '../s00a/lib.mjs';
import { cleanupC3Fixtures } from './c3_fixtures.mjs';
loadEnv();
const left = cleanupC3Fixtures();
console.log(left === '0' ? 'synthetic C3 fixtures removed (left=0)' : `WARNING left=${left}`);
process.exit(left === '0' ? 0 : 1);
