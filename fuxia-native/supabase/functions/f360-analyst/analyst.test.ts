// f360-analyst — auth, quota, tool whitelist, limits, verifier, audit, provider request shape (no network, no database).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { handleAnalyst, type AnalystEnv } from './handler.ts';
import { ClaudeModel, type AnalystModel, type RunParams, type Turn } from './provider.ts';
import { collectNumbers, mask, unverifiedFacts, validateAnswer } from './analyst.ts';

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
  const seen: RunParams[] = []; const logs: Record<string, unknown>[] = []; const reserves: Record<string, unknown>[] = []; const intelCalls: { token: string; tool: string; args: unknown }[] = [];
  const model: AnalystModel = { provider: 'fake', model: 'fake-1', turn: async (p) => { seen.push(JSON.parse(JSON.stringify(p))); return turns.shift() ?? { blocks: [{ type: 'text', text: 'fin' }], stop: 'end_turn', usage: u0 }; } };
  const rpc = async <T>(fn: string, args: Record<string, unknown>) => {
    if (fn === 'f360_ai_quota') return quota as T;
    if (fn === 'f360_ai_reserve') { reserves.push(args); return { ...quota, reservation_id: (quota as { allowed?: boolean }).allowed ? 41 : undefined } as T; }
    if (fn === 'f360_ai_log') { logs.push(args.p as Record<string, unknown>); return 7 as T; }
    throw new Error(fn);
  };
  const intel = async (token: string, tool: string, args: unknown) => { intelCalls.push({ token, tool, args }); return intelResult(tool); };
  return { seen, logs, intelCalls, reserves, deps: { model, rpc, intel, now: new Date('2026-10-11T16:00:00Z') } };
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

test('F1 limits: after max_tool_calls the next turn only OFFERS entregar_respuesta (never a forced tool_choice)', async () => {
  const h = harness([use('a', 'ventas'), use('b', 'pagos'), use('c', 'marketing'), use('d', 'embudo'),
    final({ resumen: 'listo', hechos: [], calculos: [], recomendaciones: [], faltantes: [] })]);
  await withUser('owner', async () => {
    const r = await handleAnalyst(req({ question: 'todo' }), env, h.deps);
    assert.equal(r.status, 200); assert.equal(h.intelCalls.length, 3);
    assert.ok(h.seen.every((p) => p.forceTool === undefined), 'no forced tool_choice');
    assert.deepEqual(h.seen[3].tools.map((t) => t.name), ['entregar_respuesta']);
    assert.ok(JSON.stringify(h.seen[3].messages.at(-1)).includes('Ya no puedes consultar más datos'));
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

test('verifier: commas/decimals/rounding accepted, years and dates ignored', () => {
  const known = collectNumbers([{ a: 56406, b: '1.9', c: [{ d: 14720.5 }] }]);
  assert.deepEqual(unverifiedFacts({ hechos: [{ texto: 'Del 1 de octubre de 2026: 56,406 MXN, avance 1.9%, ritmo 14,721 al día' }] }, known), []);
  assert.deepEqual(unverifiedFacts({ hechos: [{ texto: 'vendimos 70,000', cifras: [] }] }, known).map((x) => x.valor), [70000]);
});

test('F3 no false alarms from names, identifiers, dates, "12 meses", "90 días", GA4, or numbers written inside tool texts', () => {
  const known = collectNumbers([{ por_ubicacion: [{ ubicacion: 'Amsterdam 264', pares: 92 }], faltantes: [{ por_que: '179 pares en la app anterior' }], total: 643 }]);
  const hechos = [
    { texto: 'Pares por ubicación: Amsterdam 264 92, total 643 pares', cifras: [{ valor: 92 }, { valor: 643 }] },
    { texto: 'México, 1–11 oct 2026: 4 pedidos; últimos 12 meses; compromisos a 90 días; falta GA4' },
    { texto: '179 pares de la app anterior nunca pasaron', cifras: [{ valor: 179 }] },
  ];
  assert.deepEqual(unverifiedFacts({ hechos, resumen: 'Hay 643 pares en el sistema nuevo.' }, known), []);
});

test('F3 still catches invented economic figures (money, %, currency) in facts and in the summary', () => {
  const known = collectNumbers([{ venta_neta: 5600, avance_pct: 1.9 }]);
  const bad = unverifiedFacts({ hechos: [{ texto: 'Venta $5,600 MXN, margen 48%', cifras: [{ valor: 5600 }] }], resumen: 'Ganamos $70,000 MXN este mes.' }, known);
  assert.deepEqual(bad.map((b) => [b.donde, b.valor]), [['hechos', 48], ['resumen', 70000]]);
});

test('H1 mask: phones and emails masked, dates kept', () => {
  assert.equal(mask('ana@x.com +52 55 1234 5678'), '[correo] [número]');
  assert.equal(mask('ventas del 2026-08-01 al 2026-08-31 y del 01/09/2026'), 'ventas del 2026-08-01 al 2026-08-31 y del 01/09/2026');
});

test('F2 validation: traceable facts kept; facts citing a tool not called or without period go to sin_fuente; string hechos rejected', () => {
  const v = validateAnswer({ resumen: 'ok', hechos: [
    { texto: 'a', cifras: [{ valor: '5' }], fuente: { herramienta: 'ventas', fuente: 'x', periodo: 'oct' } },
    { texto: 'b', cifras: [], fuente: { herramienta: 'margen', fuente: 'x', periodo: 'oct' } },
    { texto: 'c', cifras: [], fuente: { herramienta: 'ventas', fuente: 'x', periodo: '' } }] }, ['ventas'], 'pregunta');
  assert.equal(v.ok, false); assert.equal((v.answer.hechos as unknown[]).length, 1); assert.equal((v.answer.sin_fuente as unknown[]).length, 2);
  assert.equal(((v.answer.hechos as { cifras: { valor: number }[] }[])[0].cifras[0].valor), 5);
  const s = validateAnswer({ resumen: 'x', hechos: '<parameter name="hechos">[]' }, ['pagos'], 'pregunta');
  assert.equal(s.ok, false); assert.ok(s.problems.some((p) => p.includes('"hechos" debe ser una lista')));
  const r = validateAnswer({ resumen: 'Llevamos $45,200 MXN' }, ['ventas'], 'pregunta');
  assert.ok(r.problems.some((p) => p.includes('cifras del resumen')));
  const p = validateAnswer({ resumen: 'x', prioridades: [{ texto: 'a', evidencia: 'b', impacto: 'c', responsable: 'd', medicion: 'e' }] }, [], 'prioridades');
  assert.ok(p.problems.some((x) => x.includes('exactamente 3 prioridades')));
});

test('F2 repair: an answer with figures but no traceable facts gets ONE correction round (answer tool only); then it is accepted', async () => {
  const good = { resumen: 'México lleva $5,600 MXN.', hechos: [{ texto: 'Venta MX $56,406 MXN', cifras: [{ valor: 56406 }], fuente: { herramienta: 'ventas', fuente: 'Commerce Facts', periodo: '2026-08' } }],
    calculos: [], recomendaciones: [], faltantes: [] };
  const h = harness([use('a', 'ventas'), final({ resumen: 'Llevamos $56,406 MXN' }), final(good)]);
  await withUser('owner', async () => {
    const r = await handleAnalyst(req({ question: 'ventas' }), env, h.deps);
    const j = await r.json() as { answer: { validacion: { estado: string }; hechos: unknown[] } };
    assert.equal(r.status, 200); assert.equal(j.answer.validacion.estado, 'completa'); assert.equal(j.answer.hechos.length, 1);
    assert.deepEqual(h.seen[2].tools.map((t) => t.name), ['entregar_respuesta']);
    assert.ok(JSON.stringify(h.seen[2].messages.at(-1)).includes('Respuesta incompleta'));
  });
});

test('F2 after the repair round an untraceable answer is returned marked "incompleta", facts as sin_fuente (never verified)', async () => {
  const bad = { resumen: 'x', hechos: [{ texto: 'Venta $1', cifras: [{ valor: 1 }], fuente: { herramienta: 'margen', fuente: 'x', periodo: 'oct' } }] };
  const h = harness([use('a', 'ventas'), final(bad), final(bad)]);
  await withUser('owner', async () => {
    const j = await (await handleAnalyst(req({ question: 'ventas' }), env, h.deps)).json() as { answer: { validacion: { estado: string }; hechos: unknown[]; sin_fuente: unknown[] } };
    assert.equal(j.answer.validacion.estado, 'incompleta'); assert.equal(j.answer.hechos.length, 0); assert.equal(j.answer.sin_fuente.length, 1);
    assert.equal(h.logs[0].status, 'ok');
  });
});

test('F1 weekly priorities: tools → three complete priorities delivered (no forced tool_choice)', async () => {
  const reco = (n: number) => ({ texto: `p${n}`, evidencia: 'e', impacto: 'i', responsable: 'Mario', medicion: 'm' });
  const h = harness([use('a', 'senales_semana'), final({ resumen: 'tres', hechos: [], calculos: [], recomendaciones: [], prioridades: [reco(1), reco(2), reco(3)], faltantes: [] })]);
  await withUser('owner', async () => {
    const j = await (await handleAnalyst(req({ kind: 'prioridades' }), env, h.deps)).json() as { answer: { prioridades: unknown[]; validacion: { estado: string } } };
    assert.equal(j.answer.prioridades.length, 3); assert.equal(j.answer.validacion.estado, 'completa');
    assert.ok(h.seen.every((p) => p.forceTool === undefined));
  });
});

test('H3 budget margin: a question does not start when the remaining budget cannot cover a whole question', async () => {
  const h = harness([], { allowed: true, reason: null, settings, spent_month_usd: 99.95, budget_usd: 100, warning: true });
  await withUser('owner', async () => {
    const r = await handleAnalyst(req({ question: '¿cómo vamos?' }), env, h.deps);
    assert.equal(r.status, 429); assert.equal(h.seen.length, 0); assert.equal(h.logs[0].status, 'limite_mes');
  });
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

test('H2 every question reserves its estimated cost atomically and releases it in the audit row (reservation_id)', async () => {
  const h = harness([use('a', 'ventas'), final({ resumen: 'ok', hechos: [], calculos: [], recomendaciones: [], faltantes: [] })]);
  await withUser('owner', async () => {
    await handleAnalyst(req({ question: 'ventas' }), env, h.deps);
    assert.equal(h.reserves.length, 1); assert.ok(Number(h.reserves[0].p_est_cost) > 0);
    assert.equal(h.logs[0].reservation_id, 41);
  });
});
