// f360-analyst — AI Business Analyst (Centro de Inteligencia, I3). Separate from Hilo (own function, own secret, own tables).
// Caller: the admin (/inteligencia) with the user's session. Flow:
//   1. session → f360 user (owner); 2. quota (f360_ai_quota, service) — per-person daily cap, monthly USD budget;
//   3. model loop: the model may only call DATA_TOOLS, each executed as public.f360_intel_query WITH THE USER'S TOKEN (board gate,
//      MFA, access log with actor ai_analyst) — no SQL, no writes; 4. the answer must come through entregar_respuesta (hechos /
//      cálculos / recomendaciones / faltantes); 5. verifier: numbers stated as facts must exist in tool payloads; 6. audit row
//      (f360_ai_log, cost computed by the database). The question is masked before it is sent or stored.
import { f360User, serviceRpc, type SupabaseEnv } from '../_shared/f360-woo/supabase.ts';
import { ANSWER_TOOL, DATA_TOOLS, collectNumbers, mask, systemPrompt, unverifiedFacts } from './analyst.ts';
import { makeModel, type AnalystModel, type Block, type Message } from './provider.ts';

export type AnalystEnv = SupabaseEnv & { ANTHROPIC_API_KEY?: string; F360_AI_PROVIDER?: string };
type Rpc = <T>(fn: string, args: Record<string, unknown>) => Promise<T>;
type Deps = { model?: AnalystModel; rpc?: Rpc; intel?: (token: string, tool: string, args: unknown) => Promise<Record<string, unknown>>; now?: Date };
type Settings = { provider: string; model: string; max_tool_calls: number; max_output_tokens: number; timeout_seconds: number;
  price_input_mtok: number; price_output_mtok: number; price_cache_write_mtok: number; price_cache_read_mtok: number };

const json = (data: unknown, status = 200) => new Response(JSON.stringify(data), { status, headers: { 'Content-Type': 'application/json' } });
const mxToday = (now = new Date()) => new Date(now.getTime() - 6 * 3600e3).toISOString().slice(0, 10);
const MAX_TOOL_CHARS = 30_000;

function intelCaller(env: AnalystEnv) {
  return async (token: string, tool: string, args: unknown) => {
    const res = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/f360_intel_query`, {
      method: 'POST',
      headers: { apikey: env.SUPABASE_ANON_KEY ?? '', Authorization: `Bearer ${token}`, 'Content-Type': 'application/json', 'x-f360-actor': 'ai_analyst' },
      body: JSON.stringify({ p_tool: tool, p_args: args ?? {} }),
    });
    const body = await res.json().catch(() => null);
    if (!res.ok) return { ok: false, error: (body && body.message) || `HTTP ${res.status}` };
    return body as Record<string, unknown>;
  };
}

export async function handleAnalyst(req: Request, env: AnalystEnv, deps: Deps = {}) {
  if (req.method !== 'POST') return json({ error: 'Método no permitido.' }, 405);
  const started = Date.now();
  const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
  const u = await f360User(env, token);
  if (!u) return json({ error: 'Tu sesión no es válida.' }, 401);
  if (u.role !== 'owner') return json({ error: 'El analista es solo para la dirección.' }, 403);
  const body = (await req.json().catch(() => ({}))) as { question?: unknown; kind?: unknown };
  const kind = body.kind === 'prioridades' ? 'prioridades' : 'pregunta';
  const raw = typeof body.question === 'string' ? body.question.trim() : '';
  const question = kind === 'prioridades' ? (raw || '¿Cuáles son las tres prioridades comerciales de esta semana?') : raw;
  if (question.length < 3 || question.length > 1500) return json({ error: 'Escribe una pregunta (máximo 1,500 caracteres).' }, 400);
  const masked = mask(question);
  const rpc = deps.rpc ?? serviceRpc(env);
  const log = (row: Record<string, unknown>) => rpc<number>('f360_ai_log', { p: { auth_user_id: u.id, kind, question: masked, duration_ms: Date.now() - started, ...row } }).catch(() => null);

  const quota = await rpc<{ allowed: boolean; reason: string | null; settings: Settings; spent_month_usd: number; budget_usd: number; warning: boolean }>('f360_ai_quota', { p_user: u.id });
  if (!quota.allowed) {
    await log({ status: quota.reason ?? 'apagado' });
    const msg = quota.reason === 'limite_mes' ? 'Se alcanzó el presupuesto mensual de IA. Mario puede ajustarlo en Inteligencia → Consumo.'
      : quota.reason === 'limite_usuario' ? 'Llegaste al límite de preguntas de hoy.' : 'El analista está apagado.';
    return json({ error: msg, reason: quota.reason }, 429);
  }
  const s = quota.settings;
  if (!deps.model && !env.ANTHROPIC_API_KEY) {
    await log({ status: 'sin_configurar' });
    return json({ error: 'El analista todavía no tiene la llave de IA configurada.' }, 503);
  }
  const model = deps.model ?? makeModel(env.F360_AI_PROVIDER || s.provider, s.model, env.ANTHROPIC_API_KEY!);
  const intel = deps.intel ?? intelCaller(env);
  const signal = AbortSignal.timeout(s.timeout_seconds * 1000);
  const messages: Message[] = [{ role: 'user', content: masked }];
  const tools = [...DATA_TOOLS, ANSWER_TOOL];
  const usage = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 };
  const calls: { tool: string; args: unknown; disponibilidad: unknown; fuente: unknown }[] = [];
  const payloads: unknown[] = [];
  let answer: Record<string, unknown> | null = null;

  try {
    for (let step = 0; step <= s.max_tool_calls + 1 && !answer; step++) {
      const force = calls.length >= s.max_tool_calls || step === s.max_tool_calls + 1 ? ANSWER_TOOL.name : undefined;
      const t = await model.turn({ system: systemPrompt(mxToday(deps.now), kind), messages, tools, maxTokens: s.max_output_tokens, forceTool: force, signal });
      usage.input += t.usage.input; usage.output += t.usage.output; usage.cacheRead += t.usage.cacheRead; usage.cacheWrite += t.usage.cacheWrite;
      messages.push({ role: 'assistant', content: t.blocks });
      const uses = t.blocks.filter((b): b is Extract<Block, { type: 'tool_use' }> => b.type === 'tool_use');
      if (!uses.length) {   // the model answered in plain text: keep it, but nothing in it counts as a verified fact
        const text = t.blocks.filter((b): b is Extract<Block, { type: 'text' }> => b.type === 'text').map((b) => b.text).join('\n').trim();
        answer = { resumen: text || 'Sin respuesta.', hechos: [], calculos: [], recomendaciones: [], faltantes: [], formato: 'texto_libre' };
        break;
      }
      const results: Block[] = [];
      for (const use of uses) {
        if (use.name === ANSWER_TOOL.name) { answer = use.input; break; }
        if (!DATA_TOOLS.some((d) => d.name === use.name) || calls.length >= s.max_tool_calls) {
          results.push({ type: 'tool_result', tool_use_id: use.id, is_error: true, content: 'Herramienta no disponible o límite alcanzado. Responde con lo que tienes.' });
          continue;
        }
        const r = await intel(token, use.name, use.input);
        if (r.ok === false && r.error === 'No disponible.') {   // the board gate refused this user (not a member, or no second factor)
          await log({ status: 'denegado', tools: calls });
          return json({ error: 'Tu cuenta no tiene acceso a estos datos (o falta la verificación en dos pasos).' }, 403);
        }
        const meta = (r.meta ?? {}) as Record<string, unknown>;
        calls.push({ tool: use.name, args: use.input, disponibilidad: meta.disponibilidad ?? null, fuente: meta.fuente ?? null });
        payloads.push(r.data ?? null, meta);
        results.push({ type: 'tool_result', tool_use_id: use.id, content: JSON.stringify(r).slice(0, MAX_TOOL_CHARS) });
      }
      if (answer) break;
      messages.push({ role: 'user', content: results });
    }
  } catch (e) {
    await log({ status: 'error', provider: model.provider, model: model.model, tools: calls, error: (e as Error).message,
      tokens_input: usage.input, tokens_output: usage.output, tokens_cache_read: usage.cacheRead, tokens_cache_write: usage.cacheWrite });
    return json({ error: 'El analista no pudo terminar. Intenta de nuevo en un momento.' }, 502);
  }
  if (!answer) answer = { resumen: 'No se pudo completar la respuesta dentro de los límites.', hechos: [], calculos: [], recomendaciones: [], faltantes: [] };
  const unverified = unverifiedFacts(answer as never, collectNumbers(payloads));
  const sources = [...new Set(calls.map((c) => c.fuente).filter(Boolean))];
  const cost = (usage.input * s.price_input_mtok + usage.output * s.price_output_mtok + usage.cacheRead * s.price_cache_read_mtok + usage.cacheWrite * s.price_cache_write_mtok) / 1e6;
  const id = await log({ status: 'ok', provider: model.provider, model: model.model, tools: calls, sources, answer, unverified,
    tokens_input: usage.input, tokens_output: usage.output, tokens_cache_read: usage.cacheRead, tokens_cache_write: usage.cacheWrite });
  return json({ ok: true, id, kind, answer, unverified, tools: calls, sources,
    usage: { ...usage, cost_usd: Math.round(cost * 100000) / 100000, model: model.model, spent_month_usd: quota.spent_month_usd, budget_usd: quota.budget_usd, warning: quota.warning } });
}
