// STAGING ONLY: clears Fuxia 360 demo products + inventory history (keeps locations and roles).
// Run: scripts/s00a/run.sh ../f360/demo_reset.mjs      (lib refuses any production target)
import { readFileSync } from 'node:fs';
import { loadEnv, psql } from '../s00a/lib.mjs';

loadEnv();
psql(readFileSync('supabase/staging/f360_demo_reset.sql', 'utf8'));
console.log(psql(`select json_build_object('products', (select count(*) from f360.products), 'events', (select count(*) from f360.inventory_events),
  'locations', (select string_agg(name, ', ') from f360.locations), 'owners', (select string_agg(display_name, ', ') from f360.user_roles where role = 'owner'));`, {}, { readOnly: true }));
