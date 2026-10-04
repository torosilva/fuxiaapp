// f360-hilo-intake — HiloLabs (Hilo Backbone) posts its escalations here so they land in Fuxia 360's "Bandeja de
// clientas". Server-to-server: Bearer F360_HILO_SECRET (shared with HiloLabs' F360_INTAKE_SECRET). Not public.
export type IntakeEnv = { SUPABASE_URL: string; SUPABASE_SERVICE_ROLE_KEY: string; F360_HILO_SECRET: string };
const CHANNELS: Record<string, string> = { web: 'hilo_web', mobile: 'hilo_app', whatsapp: 'hilo_whatsapp', voice: 'hilo_voice' };
function safeEqual(a: string, b: string) {
  if (!a || a.length !== b.length) return false;
  let x = 0; for (let i = 0; i < a.length; i++) x |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return x === 0;
}
const s = (v: unknown, max: number) => (typeof v === 'string' || typeof v === 'number') ? String(v).replace(/[<>]/g, '').trim().slice(0, max) : '';

export async function handleIntake(req: Request, env: IntakeEnv, fetchImpl: typeof fetch = fetch): Promise<Response> {
  const json = (d: unknown, status = 200) => new Response(JSON.stringify(d), { status, headers: { 'Content-Type': 'application/json' } });
  if (req.method !== 'POST') return json({ error: 'Método no permitido.' }, 405);
  if (!env.F360_HILO_SECRET || !safeEqual(req.headers.get('Authorization') ?? '', `Bearer ${env.F360_HILO_SECRET}`)) return json({ error: 'No autorizado.' }, 401);
  let b: Record<string, any>;
  try { b = await req.json(); } catch { return json({ error: 'Solicitud no válida.' }, 400); }
  const conv = s(b.conversation_id, 100);
  if (!conv) return json({ error: 'Falta conversation_id.' }, 400);
  const page = (b.metadata && typeof b.metadata === 'object' && b.metadata.page && typeof b.metadata.page === 'object') ? b.metadata.page : {};
  const transcript = Array.isArray(b.last_messages) ? b.last_messages.slice(-12).map((m: any) => ({ role: m?.role === 'user' ? 'user' : 'assistant', content: s(m?.content, 1000) })) : undefined;
  const p = {
    conversation_id: conv, source: CHANNELS[s(b.channel, 20)] ?? 'hilo_web', reason: s(b.reason, 40) || null, summary: s(b.summary, 2000) || null,
    ...(transcript ? { transcript } : {}),
    email: s(b.metadata?.user_email, 120) || null, country: s(page.pais, 8) || null, product: s(page.producto, 200) || null,
    color: s(page.color, 80) || null, size: s(page.talla_mx ? page.talla_mx + ' MX' : page.talla_tienda, 20) || null, page_url: s(page.url, 300) || null,
  };
  const r = await fetchImpl(`${env.SUPABASE_URL}/rest/v1/rpc/f360_case_upsert`, { method: 'POST',
    headers: { apikey: env.SUPABASE_SERVICE_ROLE_KEY, Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ p }) });
  const data = await r.json().catch(() => null);
  return r.ok ? json({ ok: true, ...(data ?? {}) }) : json({ error: (data as any)?.message ?? 'No se pudo registrar.' }, 400);
}
