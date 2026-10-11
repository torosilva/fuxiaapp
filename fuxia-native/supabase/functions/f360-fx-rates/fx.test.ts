// f360-fx-rates — parsing, cross rate, auth, failure recording (no network, no database).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildPrimary, fetchDof, fetchTrm, fetchReference, SRC_COP, SRC_USD } from './fx.ts';
import { handleFx, type FxEnv } from './handler.ts';

const env: FxEnv = { SUPABASE_URL: 'http://x', SUPABASE_SERVICE_ROLE_KEY: 'k', F360_SYNC_SECRET: 's3cret' };
const req = (body: unknown, auth = 'Bearer s3cret') => new Request('http://x', { method: 'POST', headers: { Authorization: auth }, body: JSON.stringify(body) });
const res = (status: number, j: unknown) => ({ ok: status < 400, status, json: async () => j });
const DOF = { messageCode: 200, ListaIndicadores: [
  { codTipoIndicador: 158, fecha: '08-10-2026', valor: '17.9780' }, { codTipoIndicador: 158, fecha: '09-10-2026', valor: '18.1128' },
  { codTipoIndicador: 159, fecha: '09-10-2026', valor: '8.85' }] };
const TRM = [{ valor: '3238.88', vigenciadesde: '2026-10-08T00:00:00.000', vigenciahasta: '2026-10-08T00:00:00.000' },
  { valor: '3218.75', vigenciadesde: '2026-10-09T00:00:00.000', vigenciahasta: '2026-10-09T00:00:00.000' }];
const fakeFetch = (urls: string[]) => (async (url: string) => {
  urls.push(url);
  if (url.includes('sidof')) return res(200, DOF);
  if (url.includes('datos.gov.co')) return res(200, TRM);
  if (url.includes('er-api')) return res(200, { result: 'success', time_last_update_unix: 1791676800, rates: { USD: 0.0552, COP: 176.4 } });
  return res(404, {});
}) as unknown as typeof fetch;

test('DOF: only indicator 158, dates to ISO, URL in dd-mm-yyyy', async () => {
  const urls: string[] = [];
  const d = await fetchDof(fakeFetch(urls) as never, '2026-10-01', '2026-10-11');
  assert.deepEqual(d.rows, [{ date: '2026-10-08', value: 17.978 }, { date: '2026-10-09', value: 18.1128 }]);
  assert.ok(urls[0].endsWith('/158/01-10-2026/11-10-2026'));
});

test('cross rate COP = FIX ÷ TRM in force that day; USD direct; inputs kept for traceability', async () => {
  const f = fakeFetch([]) as never;
  const rows = buildPrimary(await fetchDof(f, '2026-10-08', '2026-10-09'), await fetchTrm(f, '2026-10-08', '2026-10-09'));
  assert.equal(rows.length, 4);
  const cop = rows.find((r) => r.currency === 'COP' && r.obs_date === '2026-10-09')!;
  assert.equal(cop.rate, (18.1128 / 3218.75).toFixed(10));
  assert.equal(cop.method, 'CROSS_USD'); assert.equal(cop.source, SRC_COP);
  assert.deepEqual(cop.inputs, { dof_fecha: '2026-10-09', usd_mxn: 18.1128, trm_cop_por_usd: 3218.75, trm_vigencia: ['2026-10-09', '2026-10-09'] });
  const usd = rows.find((r) => r.currency === 'USD' && r.obs_date === '2026-10-08')!;
  assert.equal(usd.rate, '17.978000'); assert.equal(usd.source, SRC_USD); assert.equal(usd.role, 'primary');
  assert.ok(Math.abs(Number(cop.rate) - 0.0057) < 0.0002, 'consistent with Mario’s 0.0057');
});

test('a DOF day without TRM gives USD only (never an invented COP)', () => {
  const rows = buildPrimary({ url: 'u', rows: [{ date: '2026-10-12', value: 18 }] }, { url: 't', rows: [] });
  assert.deepEqual(rows.map((r) => r.currency), ['USD']);
});

test('reference rows are inverted and marked reference', async () => {
  const r = await fetchReference(fakeFetch([]) as never);
  assert.deepEqual(r.map((x) => [x.currency, x.role]), [['USD', 'reference'], ['COP', 'reference']]);
  assert.equal(r[1].rate, (1 / 176.4).toFixed(10));
});

test('daily: records primary + reference; non-owner refused; source failure recorded, nothing written', async () => {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const rpc = async <T>(fn: string, args: Record<string, unknown>) => { calls.push({ fn, args }); return { ok: true } as T; };
  const r = await handleFx(req({ action: 'daily' }), env, { fetch: fakeFetch([]), rpc, now: new Date('2026-10-11T15:00:00Z') });
  const j = await r.json() as { ok: boolean; primary: number; reference: number; proposed: unknown };
  assert.equal(r.status, 200); assert.equal(j.ok, true); assert.equal(j.primary, 4); assert.equal(j.reference, 2); assert.equal(j.proposed, null);
  assert.deepEqual(calls.map((c) => c.fn), ['f360_fx_observations_record']);
  assert.equal((calls[0].args.p_rows as unknown[]).length, 6);

  const early: string[] = [];
  const rpc2 = async <T>(fn: string, args: Record<string, unknown>) => { early.push(`${fn}:${args.p_month ?? ''}`); return {} as T; };
  await handleFx(req({ action: 'daily' }), env, { fetch: fakeFetch([]), rpc: rpc2, now: new Date('2026-11-02T15:00:00Z') });
  assert.deepEqual(early, ['f360_fx_observations_record:', 'f360_fx_month_propose:2026-10-01']);

  const real = globalThis.fetch;
  globalThis.fetch = (async (u: string | URL) => String(u).endsWith('/auth/v1/user') ? new Response('{"id":"u"}')
    : new Response(JSON.stringify({ role: 'seller', display_name: 'V' }))) as typeof fetch;
  try {
    const seller = await handleFx(req({ action: 'daily' }, 'Bearer otro'), { ...env, SUPABASE_ANON_KEY: 'a' }, { fetch: fakeFetch([]), rpc });
    assert.equal(seller.status, 403);
  } finally { globalThis.fetch = real; }
  assert.equal(calls.length, 1, 'nothing recorded for the seller');

  const fails: string[] = [];
  const rpc3 = async <T>(fn: string) => { fails.push(fn); return {} as T; };
  const down = await handleFx(req({ action: 'backfill', from: '2026-05-01', to: '2026-10-10' }), env,
    { fetch: (async () => res(503, {})) as unknown as typeof fetch, rpc: rpc3, now: new Date('2026-10-11T15:00:00Z') });
  assert.equal(down.status, 502); assert.deepEqual(fails, ['f360_measurement_run_failed']);
});

test('invalid action / window refused before any read', async () => {
  const rpc = async <T>() => ({}) as T;
  assert.equal((await handleFx(req({ action: 'x' }), env, { rpc })).status, 400);
  assert.equal((await handleFx(req({ action: 'backfill', from: '2020-01-01', to: '2026-10-10' }), env, { rpc, now: new Date('2026-10-11T15:00:00Z') })).status, 400);
  assert.equal((await handleFx(req({ action: 'propose', month: '2026-10-15' }), env, { rpc })).status, 400);
});
