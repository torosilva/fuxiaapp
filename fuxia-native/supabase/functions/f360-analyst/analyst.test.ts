// f360-analyst — auth, quota, tool whitelist, limits, verifier, audit, provider request shape (no network, no database).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { handleAnalyst, type AnalystEnv } from './handler.ts';
import { ClaudeModel, type AnalystModel, type RunParams, type Turn } from './provider.ts';
import { collectNumbers, mask, unverifiedFacts } from './analyst.ts';

const env: AnalystEnv = { SUPABASE_URL: 'http://sb', SUPABASE_ANON_KEY: 'anon', SUPABASE_SERVICE_ROLE_KEY: 'svc', ANTHROPIC_API_KEY: 'sk-test' };
const req = (body: unknown, token = 'user-jwt') => new Request('http://x', { method: 'POST', headers: { Authorization: `Bearer ${token}` }, body: JSON.stringify(body) });
const settings = { provider: 'anthropic', model: 'claude-sonnet-5-5', max_tool_calls: 3, max_output_tokens: 1500, timeout_seconds: 60,
  price_input_mtok: 2, price_output_mtok: 10, price_cache_write_mtok: 2.5, price_cache_read_mtok: 0.1 };

function withUser(role: string, fn: () => Promise<void>) {
  const real = globalThis.fetch;
  globalThis.fetch = (async (u: string | URL) => String(u).endsWith('/auth/v1/user') ? new Response('{"id":"mario-uid"}')
    : new Response(JSON.stringify({ role, display_name: 'Mario' }))) as typeof fetch;
  return fn().finally(() => { globalThis.fetch = real; });
}
function harness(turns: Turn[], quota: Record<string, unknown> = { allowed: true, reason: null, settings, spent_month_usd: 1, budget_usd: 100, warning: false },
  intelResult: (tool: string) => Record<string, unknown> = () => ({ ok: true, data: { por_mercado_canal: [{ mercado: 'MX', venta_neta: 56406, pedidos_pagados: 16 }] },
    meta: { fuente: 'Commerce Facts', disponibilidad: 'DISPONIBLE', periodo: { desde: '2026-08-01', hasta: '2026-08-31' } } })) {
  const seen: RunParams[] = []; const logs: Record<string, unknown>[] = []; const intelCalls: { token: string; tool: string; args: unknown }[] = [];
  const model: AnalystModel = { provider: 'fake', model: 'fake-1', turn: async (p) => { seen.push(JSON.parse(JSON.stringify(p))); return turns.shift() ?? { blocks: [{ type: 'text', text: 'fin' }], stop: 'end_turn', usage: u0 }; } };
  const rpc = async <T>(fn: string, args: Record<string, unknown>) => {
    if (fn === 'f360_ai_quota') return quota as T;
    if (fn === 'f360_ai_log') { logs.push(args.p as Record<string, unknown>); return 7 as T; }
    throw new Error(fn);
  };
  const intel = async (token: string, tool: string, args: unknown) => { intelCalls.push({ token, tool, args }); return intelResult(tool); };
  return { seen, logs, intelCalls, deps: { model, rpc, intel, now: new Date('2026-10-11T16:00:00Z') } };
}
const u0 = { input: 1000, output: 100, cacheRead: 0, cacheWrite: 0 };
const use = (id: string, name: string, input: Record<string, unknown> = {}): Turn => ({ blocks: [{ type: 'tool_use', id, name, input }], stop: 'tool_use', usage: u0 });
const final = (answer: Record<string, unknown>): Turn => use('fin', 'entregar_respuesta', answer);

test('session and role: no session 401, seller 403 — before any model or quota call', async () => {
  const h = harness([]);
  const real = globalThis.fetch;
  globalThis.fetch = (async () => new Response('{}', { status: 401 })) as typeof fetch;
  try { assert.equal((await handleAnalyst(req({ question: 'hola' }), env, h.deps)).status, 401); } finally { globalThis.fetch = real; }
  await withUser('seller', async () => { assert.equal((await handleAnalyst(req({ question: '¿cómo vamos?' }), env, h.deps)).status, 403); });
  assert.equal(h.seen.length, 0); assert.equal(h.logs.length, 0);
});

test('quota: monthly budget reached → 429, audited, model never called', async () => {
  const h = harness([], { allowed: false, reason: 'limite_mes', settings });
  await withUser('owner', async () => {
    const r = await handleAnalyst(req({ question: '¿cómo vamos?' }), env, h.deps);
    assert.equal(r.status, 429); assert.equal(h.seen.length, 0); assert.equal(h.logs[0].status, 'limite_mes');
  });
});

test('no API key → 503 sin_configurar (audited)', async () => {
  const h = harness([]);
  await withUser('owner', async () => {
    const r = await handleAnalyst(req({ question: '¿cómo vamos?' }), { ...env, ANTHROPIC_API_KEY: '' }, { rpc: h.deps.rpc, intel: h.deps.intel });
    assert.equal(r.status, 503); assert.equal(h.logs[0].status, 'sin_configurar');
  });
});

test('happy path: data tool with the USER token, masked question, facts verified, invented number flagged, audit with tokens', async () => {
  const h = harness([use('t1', 'ventas', { desde: '2026-08-01', hasta: '2026-08-31' }),
    final({ resumen: 'Agosto MX: 56,406 MXN.', hechos: [{ texto: 'Venta neta MX agosto 56,406 MXN en 16 pedidos', cifras: [{ valor: 56406, moneda: 'MXN' }],
      fuente: { herramienta: 'ventas', fuente: 'Commerce Facts', periodo: '2026-08' } }, { texto: 'Margen 42%', cifras: [{ valor: 42 }], fuente: { herramienta: 'ventas', fuente: 'x', periodo: 'x' } }],
      calculos: [], recomendaciones: [], faltantes: [] })]);
  await withUser('owner', async () => {
    const r = await handleAnalyst(req({ question: '¿Cuánto vendimos en agosto? escríbeme a ana@example.com' }), env, h.deps);
    const j = await r.json() as { ok: boolean; unverified: { valor: number }[]; usage: { cost_usd: number }; tools: unknown[] };
    assert.equal(r.status, 200); assert.equal(j.ok, true);
    assert.deepEqual(h.intelCalls, [{ token: 'user-jwt', tool: 'ventas', args: { desde: '2026-08-01', hasta: '2026-08-31' } }]);
    assert.ok(!JSON.stringify(h.seen[0].messages).includes('ana@example.com'), 'question masked before the model');
    assert.deepEqual(j.unverified.map((x) => x.valor), [42]);
    assert.equal(h.logs[0].status, 'ok'); assert.equal(h.logs[0].tokens_input, 2000); assert.ok(!String(h.logs[0].question).includes('ana@'));
    assert.equal(j.usage.cost_usd, (2000 * 2 + 200 * 10) / 1e6);
  });
});

test('whitelist: an unknown tool (e.g. "sql") is refused and never reaches the database', async () => {
  const h = harness([use('t1', 'sql', { query: 'select * from auth.users' }), final({ resumen: 'ok', hechos: [], calculos: [], recomendaciones: [], faltantes: [] })]);
  await withUser('owner', async () => {
    const r = await handleAnalyst(req({ question: 'dame los usuarios' }), env, h.deps);
    assert.equal(r.status, 200); assert.equal(h.intelCalls.length, 0);
    const msgs = JSON.stringify(h.seen[1].messages); assert.ok(msgs.includes('Herramienta no disponible'));
  });
});

test('limits: after max_tool_calls the model is forced to answer', async () => {
  const h = harness([use('a', 'ventas'), use('b', 'pagos'), use('c', 'marketing'), use('d', 'embudo'),
    final({ resumen: 'listo', hechos: [], calculos: [], recomendaciones: [], faltantes: [] })]);
  await withUser('owner', async () => {
    await handleAnalyst(req({ question: 'todo' }), env, h.deps);
    assert.equal(h.intelCalls.length, 3);
    assert.equal(h.seen[3].forceTool, 'entregar_respuesta');
  });
});

test('board gate refuses (no MFA / not a member) → 403 audited as denegado', async () => {
  const h = harness([use('a', 'ventas')], undefined, () => ({ ok: false, error: 'No disponible.' }));
  await withUser('owner', async () => {
    const r = await handleAnalyst(req({ question: 'ventas' }), env, h.deps);
    assert.equal(r.status, 403); assert.equal(h.logs[0].status, 'denegado');
  });
});

test('weekly priorities use their own instructions', async () => {
  const h = harness([final({ resumen: 'x', hechos: [], calculos: [], recomendaciones: [], prioridades: [], faltantes: [] })]);
  await withUser('owner', async () => {
    await handleAnalyst(req({ kind: 'prioridades' }), env, h.deps);
    assert.ok(h.seen[0].system.includes('TRES prioridades')); assert.equal(h.logs[0].kind, 'prioridades');
  });
});

test('verifier: commas/decimals/rounding accepted, years and dates ignored; mask', () => {
  const known = collectNumbers([{ a: 56406, b: '1.9', c: [{ d: 14720.5 }] }]);
  assert.deepEqual(unverifiedFacts({ hechos: [{ texto: 'Del 1 de octubre de 2026: 56,406 MXN, avance 1.9%, ritmo 14,721 al día' }] }, known), []);
  assert.deepEqual(unverifiedFacts({ hechos: [{ texto: 'vendimos 70,000', cifras: [] }] }, known).map((x) => x.valor), [70000]);
  assert.equal(mask('ana@x.com +52 55 1234 5678'), '[correo] [número]');
});

test('Claude provider: cached system + last tool, forced tool_choice, usage mapped', async () => {
  let sent: { url: string; init: RequestInit } | null = null;
  const m = new ClaudeModel('claude-sonnet-5-5', 'sk-test', async (url, init) => { sent = { url, init };
    return new Response(JSON.stringify({ content: [{ type: 'text', text: 'hola' }], stop_reason: 'end_turn', usage: { input_tokens: 10, output_tokens: 5, cache_read_input_tokens: 3, cache_creation_input_tokens: 2 } })); });
  const t = await m.turn({ system: 'S', messages: [{ role: 'user', content: 'q' }], tools: [{ name: 'a', description: 'd', input_schema: {} }, { name: 'b', description: 'd', input_schema: {} }], maxTokens: 100, forceTool: 'b' });
  const b = JSON.parse(String(sent!.init.body));
  assert.equal(sent!.url, 'https://api.anthropic.com/v1/messages'); assert.equal((sent!.init.headers as Record<string, string>)['x-api-key'], 'sk-test');
  assert.deepEqual(b.system[0].cache_control, { type: 'ephemeral' }); assert.equal(b.tools[0].cache_control, undefined); assert.deepEqual(b.tools[1].cache_control, { type: 'ephemeral' });
  assert.deepEqual(b.tool_choice, { type: 'tool', name: 'b' }); assert.equal(b.model, 'claude-sonnet-5-5');
  assert.deepEqual(t.usage, { input: 10, output: 5, cacheRead: 3, cacheWrite: 2 });
});
