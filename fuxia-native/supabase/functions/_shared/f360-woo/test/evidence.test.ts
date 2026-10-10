// Conciliación de Ventas — gateway evidence: classification, minimization, read-only handler wiring (no network, no database).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { classifyNote, maskText, orderEvidence } from '../evidence.ts';
import { handleSync } from '../../../f360-woo-sync/handler.ts';
import type { CommerceWoo } from '../commerce.ts';

const order = (o: Record<string, unknown> = {}) => ({
  id: 5351, status: 'cancelled', total: '2800.00', currency: 'MXN', payment_method: 'woo-mercado-pago-custom', payment_method_title: 'Tarjeta',
  transaction_id: '131234567890', date_paid_gmt: '2026-10-08T14:18:36', refunds: [],
  billing: { first_name: 'Ana', last_name: 'Pérez', email: 'ana@example.com', phone: '5512345678', address_1: 'Calle 1' }, ...o,
});
const note = (n: string, at: string, extra: Record<string, unknown> = {}) => ({ id: 1, note: n, date_created_gmt: at, customer_note: false, added_by_user: false, ...extra });

test('classifies gateway notes; Woo status-change notes and customer notes are not evidence', () => {
  assert.equal(classifyNote('Mercado Pago: Pago aprobado. ID: 131234567890'), 'approved');
  assert.equal(classifyNote('Mercado Pago: Payment rejected (cc_rejected_insufficient_amount)'), 'rejected');
  assert.equal(classifyNote('ePayco: Transacción Pendiente ref_payco 998877'), 'pending');
  assert.equal(classifyNote('Order status changed from Pending payment to Processing.'), null);
  assert.equal(classifyNote('Dejar con el portero'), null);
});

test('latest gateway note decides; stored snapshot has no names, emails, phones or note text', () => {
  const ev = orderEvidence(order(), [
    note('Mercado Pago: Payment rejected', '2026-10-08T14:10:00'), note('Mercado Pago: Pago aprobado. ID: 131234567890', '2026-10-08T14:18:36'),
    note('Llámame al +52 81 1024 0698', '2026-10-08T15:00:00', { customer_note: true }),
  ]);
  assert.equal(ev.stored.gateway_result, 'approved');
  assert.equal(ev.stored.transaction_ref, '131234567890');
  assert.deepEqual(ev.stored.signals.sort(), ['date_paid', 'note_approved', 'note_rejected', 'status_unpaid', 'tx_field', 'tx_present']);
  const stored = JSON.stringify(ev.stored);
  for (const bad of ['Ana', 'ana@example.com', '5512345678', 'Pago aprobado', '1024 0698']) assert.ok(!stored.includes(bad), bad);
  assert.equal(ev.display.customer.name, 'Ana Pérez');
  assert.equal(ev.display.gateway_notes.length, 2);
});

test('card-like transaction ids are never kept; refunds win; no notes and no tx = no_evidence', () => {
  assert.equal(orderEvidence(order({ transaction_id: '4111 1111 1111 1111' }), []).stored.transaction_ref, null);
  assert.ok(orderEvidence(order({ transaction_id: '4111111111111111' }), []).stored.signals.includes('tx_redacted'));
  assert.equal(orderEvidence(order({ refunds: [{ id: 9, total: '-2800' }] }), []).stored.gateway_result, 'refunded');
  assert.equal(orderEvidence(order({ refunds: [{ id: 9, total: '-2800' }] }), []).stored.refund_total, 2800);
  assert.equal(orderEvidence(order({ transaction_id: '' }), []).stored.gateway_result, 'no_evidence');
  assert.equal(orderEvidence(order(), []).stored.gateway_result, 'transaction_only');
});

test('Mercado Pago payment ids come from its whitelisted meta when transaction_id is empty', () => {
  const ev = orderEvidence(order({ transaction_id: '', meta_data: [{ key: '_billing_rfc', value: 'XAXX010101000' }, { key: '_Mercado_Pago_Payment_IDs', value: '131234567890' }] }), []);
  assert.equal(ev.stored.transaction_ref, '131234567890');
  assert.ok(ev.stored.signals.includes('tx_meta_mercadopago'));
  assert.ok(!JSON.stringify(ev.stored).includes('XAXX'));
});

test('display masking: emails, card-like numbers and phones hidden; gateway ids kept', () => {
  const m = maskText('Pago de ana@example.com tarjeta 4111 1111 1111 1111 tel: 81 1024 0698 +52 55 1234 5678 ID 131234567890');
  assert.ok(!m.includes('ana@example.com') && !m.includes('4111') && !m.includes('1024 0698') && !m.includes('1234 5678'), m);
  assert.equal(m, 'Pago de [correo] tarjeta [número oculto] tel [teléfono] [teléfono] ID 131234567890');
  assert.ok(m.includes('131234567890'), m);
});

// handler: who may ask, and that WooCommerce is only read
const env = { SUPABASE_URL: 'http://sb', SUPABASE_ANON_KEY: 'anon', SUPABASE_SERVICE_ROLE_KEY: 'svc', WOO_TARGET_KEY: 'woo_staging4',
  WOO_BASE_URL: 'http://woo', WOO_USER: 'u', WOO_SECRET: 's', F360_SYNC_SECRET: 'cron-secret' };
function harness(viewer: boolean) {
  const calls: string[] = []; const rpcs: { fn: string; args: unknown }[] = [];
  const realFetch = globalThis.fetch;
  globalThis.fetch = (async (url: string | URL, init?: RequestInit) => {
    const u = String(url); calls.push(`${init?.method ?? 'GET'} ${u}`);
    if (u.endsWith('/auth/v1/user')) return new Response(JSON.stringify({ id: 'mario-uid' }));
    if (u.endsWith('/rpc/f360_me')) return new Response(JSON.stringify({ role: 'owner', display_name: 'Mario' }));
    if (u.endsWith('/rpc/f360_rec_can_view')) return new Response(viewer ? 'true' : '{"message":"no"}', { status: viewer ? 200 : 403 });
    if (u.endsWith('/rpc/f360_rec_evidence_record')) { rpcs.push({ fn: 'evidence', args: JSON.parse(String(init?.body)) }); return new Response('{"id":7}'); }
    if (u.endsWith('/rpc/f360_channel_mode')) return new Response('{}');
    return new Response('{}', { status: 500 });
  }) as typeof fetch;
  const woo: CommerceWoo = {
    listOrders: async () => { calls.push('woo listOrders'); return []; }, listRefunds: async () => [],
    getOrder: async (id) => { calls.push(`woo GET order ${id}`); return order(); },
    listOrderNotes: async (id) => { calls.push(`woo GET notes ${id}`); return [note('Mercado Pago: Pago aprobado', '2026-10-08T14:18:36')]; },
  };
  return { calls, rpcs, woo, restore: () => { globalThis.fetch = realFetch; } };
}
const req = (token: string, body: unknown) => new Request('http://x', { method: 'POST', headers: { Authorization: `Bearer ${token}` }, body: JSON.stringify(body) });

test('order_evidence: viewer gets evidence; Woo only read (GET); snapshot stored with the verified actor', async () => {
  const h = harness(true);
  try {
    const res = await handleSync(req('user-jwt', { action: 'order_evidence', woo_order_id: 5351, target_key: 'woo_staging4' }), env, { commerceWoo: h.woo });
    const j = await res.json() as { evidence: { id: number }; display: { customer: { name: string } } };
    assert.equal(res.status, 200); assert.equal(j.evidence.id, 7); assert.equal(j.display.customer.name, 'Ana Pérez');
    assert.deepEqual(h.calls.filter((c) => c.startsWith('woo')), ['woo GET order 5351', 'woo GET notes 5351']);
    const a = h.rpcs[0].args as { p_actor: string; p_ev: Record<string, unknown> };
    assert.equal(a.p_actor, 'mario-uid');
    assert.ok(!JSON.stringify(a.p_ev).includes('Ana'));
  } finally { h.restore(); }
});

test('order_evidence: an order Woo no longer has is recorded as order_missing (still read-only)', async () => {
  const h = harness(true);
  h.woo.getOrder = async (id) => { h.calls.push(`woo GET order ${id}`); throw new Error('Woo HTTP 404'); };
  try {
    const res = await handleSync(req('user-jwt', { action: 'order_evidence', woo_order_id: 5351, target_key: 'woo_staging4' }), env, { commerceWoo: h.woo });
    const j = await res.json() as { missing: boolean };
    assert.equal(res.status, 200); assert.equal(j.missing, true);
    assert.equal((h.rpcs[0].args as { p_ev: { gateway_result: string } }).p_ev.gateway_result, 'order_missing');
    assert.deepEqual(h.calls.filter((c) => c.startsWith('woo')), ['woo GET order 5351']);
  } finally { h.restore(); }
});

test('order_evidence: non-viewer, cron secret, other store and bad id are refused before reading Woo', async () => {
  for (const [viewer, token, body, status] of [
    [false, 'user-jwt', { action: 'order_evidence', woo_order_id: 5351, target_key: 'woo_staging4' }, 403],
    [true, 'cron-secret', { action: 'order_evidence', woo_order_id: 5351, target_key: 'woo_staging4' }, 403],
    [true, 'user-jwt', { action: 'order_evidence', woo_order_id: 5351, target_key: 'woo_production' }, 409],
    [true, 'user-jwt', { action: 'order_evidence', woo_order_id: 'x', target_key: 'woo_staging4' }, 400],
  ] as const) {
    const h = harness(viewer);
    try {
      const res = await handleSync(req(token, body), env, { commerceWoo: h.woo });
      assert.equal(res.status, status, JSON.stringify(body));
      assert.equal(h.calls.filter((c) => c.startsWith('woo')).length, 0);
      assert.equal(h.rpcs.length, 0);
    } finally { h.restore(); }
  }
});
