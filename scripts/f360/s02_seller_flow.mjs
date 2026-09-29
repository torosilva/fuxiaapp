// STAGING ONLY — S0.2 end-to-end through the same calls the mobile app makes (supabase.rpc = PostgREST /rpc).
// Synthetic fixtures (lab seller S1, lab channels "STAGING Tienda X"/"STAGING Bazar Y") are created at the start and
// the EXACT rows created are removed at the end (try/finally). Audit rows stay (append-only, by design).
// Run: scripts/s00a/run.sh ../f360/s02_seller_flow.mjs
import { client, loadEnv, phonePassword, PHONES, psql } from '../s00a/lib.mjs';

const env = loadEnv();
const c = client(env);
const results = [];
const ok = (cond, name, detail = '') => { results.push({ ok: !!cond, name, detail: String(detail).slice(0, 110) }); };
const rpc = (fn, args, token) => c.rest('POST', `rpc/${fn}`, { token, body: args });
const q = (sql) => psql(sql);

const CH_X = '00000000-0000-4000-a000-000000000301';   // lab "STAGING Tienda X"
const CH_Y = '00000000-0000-4000-a000-000000000302';   // lab "STAGING Bazar Y"
const PIN = String(1000 + Math.floor(Math.random() * 9000));
let created = { locA: null, locB: null, s1: null };

try {
  const owner = await c.signIn('carolina.demo@staging.invalid', process.env.STAGING_DEMO_CAROLINA_PASSWORD);
  const s1 = await c.signIn(`${PHONES.S1.replace('+', '')}@fuxia.app`, phonePassword(env, PHONES.S1));
  const cust = await c.signIn(`${PHONES.C2.replace('+', '')}@fuxia.app`, phonePassword(env, PHONES.C2));
  created.s1 = s1.uid;

  // ── fixture (owner RPCs, like the admin would) ──
  const a = await rpc('f360_create_location', { p_name: 'ZZ PRUEBA S0.2 Tienda X (sintética)', p_type: 'store', p_legacy_channel_id: CH_X }, owner.token);
  const b = await rpc('f360_create_location', { p_name: 'ZZ PRUEBA S0.2 Bazar Y (sintética)', p_type: 'bazaar', p_legacy_channel_id: CH_Y }, owner.token);
  if (!a.ok || !b.ok) throw new Error(`fixture locations: ${a.text} ${b.text}`);
  created.locA = a.json.id; created.locB = b.json.id;
  await rpc('f360_set_user_role', { p_auth_user_id: s1.uid, p_role: 'seller', p_display_name: 'S1 (sintética)' }, owner.token);
  await rpc('f360_set_location_assignment', { p_auth_user_id: s1.uid, p_location_id: created.locA, p_active: true }, owner.token);
  const pinSet = await rpc('f360_set_seller_pin', { p_auth_user_id: s1.uid, p_pin: PIN }, owner.token);
  ok(pinSet.ok && !pinSet.text.includes(PIN), 'owner sets PIN; response never contains it');

  // ── anonymous: no seller mode ──
  const anonShift = await rpc('f360_start_seller_shift', { p_location_id: created.locA, p_pin: PIN });
  ok(!anonShift.ok, 'anonymous cannot start a shift', anonShift.status);
  const anonLocs = await rpc('f360_my_locations', {});
  ok(!anonLocs.ok, 'anonymous cannot list shift locations', anonLocs.status);

  // ── authenticated non-staff ──
  const custShift = await rpc('f360_start_seller_shift', { p_location_id: created.locA, p_pin: PIN }, cust.token);
  ok(custShift.ok && custShift.json.ok === false, 'authenticated customer (no f360 role) cannot', JSON.stringify(custShift.json));

  // ── seller: locations come from the server; only assigned ──
  const locs = await rpc('f360_my_locations', {}, s1.token);
  const sellable = (locs.json ?? []).filter((l) => l.sellable).map((l) => l.name);
  ok(locs.ok && sellable.length === 1 && sellable[0].includes('Tienda X'), 'seller sees only her assigned location at shift start', sellable.join(','));
  const wrongLoc = await rpc('f360_start_seller_shift', { p_location_id: created.locB, p_pin: PIN }, s1.token);
  ok(wrongLoc.json?.ok === false && /No tienes asignada/.test(wrongLoc.json.error), 'unassigned location refused', wrongLoc.json?.error);
  const badPin = await rpc('f360_start_seller_shift', { p_location_id: created.locA, p_pin: PIN === '0000' ? '1111' : '0000' }, s1.token);
  ok(badPin.json?.ok === false && /PIN incorrecto/.test(badPin.json.error), 'wrong PIN refused and counted', badPin.json?.error);
  const shift = await rpc('f360_start_seller_shift', { p_location_id: created.locA, p_pin: PIN }, s1.token);
  const token = shift.json?.token;
  ok(shift.json?.ok && token && shift.json.location.legacy_channel_id === CH_X, 'authenticated seller → assigned location → valid shift (legacy channel for today\'s sale screen)', shift.json?.location?.name);

  // ── session: location from the session; client claim ignored/refused ──
  const st = await rpc('f360_seller_session', { p_token: token, p_location_claim: created.locA }, s1.token);
  ok(st.json?.ok && st.json.location.id === created.locA, 'shift check ok');
  const forged = await rpc('f360_seller_session', { p_token: token, p_location_claim: created.locB }, s1.token);
  ok(forged.json?.ok === false, 'a different location sent by the client is refused', forged.json?.error);
  const stolen = await rpc('f360_seller_session', { p_token: token }, cust.token);
  ok(stolen.json?.ok === false, 'another account cannot use the shift token', stolen.json?.error);

  // ── READ other locations, no OPERATE ──
  const read = await rpc('f360_inventory_by_location', { p_location_id: created.locB }, s1.token);
  ok(read.ok, 'seller can READ stock of a location she is not assigned to', read.status);

  // ── immediate revocation ──
  await rpc('f360_set_location_assignment', { p_auth_user_id: s1.uid, p_location_id: created.locA, p_active: false }, owner.token);
  const after = await rpc('f360_seller_session', { p_token: token }, s1.token);
  ok(after.json?.ok === false, 'revoking the assignment invalidates the shift immediately', after.json?.error);

  // ── audit: person + location ──
  const audit = await rpc('f360_seller_audit', { p_limit: 30 }, owner.token);
  const ev = (audit.json ?? []).filter((e) => e.person === 'S1 (sintética)');
  ok(['shift_start', 'bad_pin', 'not_assigned', 'location_mismatch', 'revoked'].every((k) => ev.some((e) => e.event === k))
     && ev.filter((e) => !['revoked', 'pin_set', 'unlock'].includes(e.event)).every((e) => e.location), 'audit: person + location for start, bad PIN, not assigned, mismatch, revocation',
     [...new Set(ev.map((e) => e.event))].join(','));
  const cred = q(`select pin_hash like '$2%' and pin_hash not like '%${PIN}%' from f360.seller_credentials where auth_user_id = '${s1.uid}';`).trim();
  ok(cred === 't', 'PIN stored only as bcrypt hash');
} finally {
  // ── remove EXACTLY the synthetic fixture rows this run created ──
  if (created.s1) {
    q(`BEGIN;
       DELETE FROM f360.seller_sessions WHERE auth_user_id = '${created.s1}';
       DELETE FROM f360.seller_credentials WHERE auth_user_id = '${created.s1}';
       DELETE FROM f360.location_assignments WHERE auth_user_id = '${created.s1}' AND location_id IN (${[created.locA, created.locB].filter(Boolean).map((x) => `'${x}'`).join(',') || 'NULL'});
       DELETE FROM f360.user_roles WHERE auth_user_id = '${created.s1}' AND display_name = 'S1 (sintética)';
       ${[created.locA, created.locB].filter(Boolean).map((x) => `DELETE FROM f360.locations WHERE id = '${x}' AND name LIKE 'ZZ PRUEBA S0.2%';`).join('\n')}
       COMMIT;`);
  }
  const left = q(`select count(*) from f360.locations where name like 'ZZ PRUEBA S0.2%';`).trim();
  results.push({ ok: left === '0', name: 'synthetic fixtures removed (locations/role/assignment/PIN/sessions)', detail: `left=${left}` });
}
for (const r of results) console.log(`${r.ok ? 'PASS' : 'FAIL'} | ${r.name} | ${r.detail}`);
const failed = results.filter((r) => !r.ok).length;
console.log(failed ? `\n${failed} FAILED` : '\nALL PASS');
process.exit(failed ? 1 : 0);
