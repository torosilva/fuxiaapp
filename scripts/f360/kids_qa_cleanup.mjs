// STAGING ONLY: removes the Fuxia Kids board rows written by tools/qa/kids-juego.mjs — ONLY the QA device's rows
// (fixed QA device id 00000000-0000-4000-8000-0000000000aa → its sha256, same salt as f360_kids_score_submit). Prints how many.
// Run: scripts/s00a/run.sh ../f360/kids_qa_cleanup.mjs
import { loadEnv, psql } from '../s00a/lib.mjs';

loadEnv();
const out = psql(`WITH d AS (DELETE FROM f360.kids_scores
  WHERE device_hash = encode(sha256(convert_to('f360-kids-v1:' || '00000000-0000-4000-8000-0000000000aa', 'UTF8')), 'hex') RETURNING 1)
SELECT 'BORRADAS | ' || count(*) FROM d;`);
for (const l of out.split('\n')) if (l.includes('BORRADAS |')) console.log(l.trim());
