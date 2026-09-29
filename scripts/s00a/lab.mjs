// S0.0A staging lab — setup | reset | verify | teardown   (run: scripts/s00a/run.sh lab.mjs <cmd>)
import { readFileSync, readdirSync } from 'node:fs';
import { loadEnv, client, psql, PHONES, phoneEmail, phonePassword, E1_EMAIL, e1Password, isLabEmail } from './lib.mjs';

const env = loadEnv();                // throws on any production ref
const c = client(env);
const SEED = readFileSync('supabase/staging/lab_seed.sql', 'utf8');
const RESET = readFileSync('supabase/staging/lab_reset.sql', 'utf8');

const PHONE_USERS = { m1: PHONES.M1, s1: PHONES.S1, c1: PHONES.C1, c2: PHONES.C2, c3: PHONES.C3 };

async function deleteLabAuthUsers() {
  const r = await c.admin.list();
  if (!r.ok) throw new Error(`admin list failed: ${r.status}`);
  const users = r.json.users || [];
  let n = 0;
  for (const u of users) {
    if (!isLabEmail(u.email)) continue;           // guard: never touch a non-lab identity
    const d = await c.admin.del(u.id);
    if (!d.ok) throw new Error(`delete ${u.email} failed: ${d.status}`);
    n++;
  }
  return { deleted: n, nonLabUsersUntouched: users.filter((u) => !isLabEmail(u.email)).length };
}

async function createLabAuthUsers() {
  const ids = {};
  for (const [k, phone] of Object.entries(PHONE_USERS)) {
    const r = await c.admin.create({ email: phoneEmail(phone), password: phonePassword(env, phone), email_confirm: true, user_metadata: { phone } });
    if (!r.ok) throw new Error(`create ${k} failed: ${r.status} ${r.text}`);
    ids[k] = r.json.id;
  }
  const e = await c.admin.create({ email: E1_EMAIL, password: e1Password(env), email_confirm: true });
  if (!e.ok) throw new Error(`create e1 failed: ${e.status} ${e.text}`);
  ids.e1 = e.json.id;
  return ids;
}

function verify() {
  const out = psql(`
    select json_build_object(
      'tier_config', (select count(*) from tier_config),
      'buckets', (select count(*) from storage.buckets where id in ('avatars','product-images')),
      'channels', (select count(*) from channels where name like 'STAGING%'),
      'customers', (select count(*) from customers where name like 'STAGING%'),
      'customers_linked', (select count(*) from customers where name like 'STAGING%' and auth_user_id is not null),
      'cards', (select count(*) from loyalty_cards where qr_code like 'STG-%'),
      'c1_points', (select total_points from loyalty_cards where qr_code='STG-C1'),
      'staff', (select count(*) from staff where name like 'STAGING%'),
      'inventory', (select count(*) from channel_inventory where product_name like 'STAGING%'),
      'c1_tx', (select count(*) from transactions where wc_order_id=990000001),
      'c1_items', (select count(*) from purchase_items where sku='STG-BAL-24'),
      'sales', (select count(*) from offline_sales where code like 'STG%'),
      'orphans', (select count(*) from unmatched_orders where wc_order_id between 990000000 and 990999999),
      'icr_pending', (select count(*) from inventory_change_requests where status='pending' and requested_by_name like 'STAGING%'),
      'push_tokens', (select count(*) from push_tokens where expo_token like 'StagingFakeToken-%'),
      'non_lab_customers', (select count(*) from customers where phone not like '+1555010%' and name not like 'STAGING%'),
      'migration_versions', (select string_agg(version, ',' order by version) from supabase_migrations.schema_migrations)
    );`, {}, { readOnly: true });
  return JSON.parse(out);
}

const EXPECT = { tier_config: 3, buckets: 2, channels: 2, customers: 5, customers_linked: 5, cards: 4, c1_points: 100, staff: 2,
  inventory: 4, c1_tx: 1, c1_items: 1, sales: 2, orphans: 2, icr_pending: 1, push_tokens: 1, non_lab_customers: 0,
  // exactly the versions present in supabase/migrations (staging must match the repo's canonical history)
  migration_versions: readdirSync('supabase/migrations').filter((f) => /^\d{14}_.*\.sql$/.test(f)).map((f) => f.slice(0, 14)).sort().join(',') };

async function setup() {
  psql(RESET);
  const del = await deleteLabAuthUsers();
  const ids = await createLabAuthUsers();
  psql(SEED, { m1: ids.m1, s1: ids.s1, c1: ids.c1, c2: ids.c2, c3: ids.c3 });
  const v = verify();
  const mismatches = Object.entries(EXPECT).filter(([k, x]) => String(v[k]) !== String(x));
  return { authUsersReplaced: del, authUsersCreated: Object.keys(ids).length, fixtures: v, integrity: mismatches.length ? { FAILED: mismatches } : 'OK' };
}

const cmd = process.argv[2];
try {
  if (cmd === 'setup' || cmd === 'reset') console.log(JSON.stringify(await setup(), null, 2));
  else if (cmd === 'verify') console.log(JSON.stringify(verify(), null, 2));
  else if (cmd === 'teardown') { psql(RESET); console.log(JSON.stringify({ sql: 'lab rows removed', auth: await deleteLabAuthUsers() })); }
  else { console.error('usage: lab.mjs setup|reset|verify|teardown'); process.exit(2); }
} catch (e) { console.error(String(e.message || e)); process.exit(1); }

export { setup };
