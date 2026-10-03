// f360-push — sends the queued Fuxia 360 notices (f360.push_outbox) through the Expo push API.
// Called by the database (pg_net after a reservation, and a pg_cron retry tick) with Bearer F360_PUSH_SECRET. Not public.
// The database decides WHO gets WHAT (f360_push_claim); this function only delivers and reports back (f360_push_result).
// A notice whose person has no phone registered is closed as 'sin dispositivo'; a failed send is retried (max 5 attempts).
export type PushEnv = { SUPABASE_URL: string; SUPABASE_SERVICE_ROLE_KEY: string; F360_PUSH_SECRET: string };
type Notice = { id: string; title: string; body: string; data: Record<string, unknown>; tokens: string[] };

function safeEqual(a: string, b: string) {
  if (!a || a.length !== b.length) return false;
  let x = 0; for (let i = 0; i < a.length; i++) x |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return x === 0;
}

export async function handlePush(req: Request, env: PushEnv, fetchImpl: typeof fetch = fetch): Promise<Response> {
  const json = (data: unknown, status = 200) => new Response(JSON.stringify(data), { status, headers: { 'Content-Type': 'application/json' } });
  if (req.method !== 'POST') return json({ error: 'Método no permitido.' }, 405);
  const auth = req.headers.get('Authorization') ?? '';
  if (!env.F360_PUSH_SECRET || !safeEqual(auth, `Bearer ${env.F360_PUSH_SECRET}`)) return json({ error: 'No autorizado.' }, 401);

  const rpc = async <T>(fn: string, args: Record<string, unknown>): Promise<T> => {
    const r = await fetchImpl(`${env.SUPABASE_URL}/rest/v1/rpc/${fn}`, { method: 'POST',
      headers: { apikey: env.SUPABASE_SERVICE_ROLE_KEY, Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`, 'Content-Type': 'application/json' }, body: JSON.stringify(args) });
    const data = await r.json().catch(() => null);
    if (!r.ok) throw new Error((data as { message?: string } | null)?.message ?? `${fn} falló`);
    return data as T;
  };

  const notices = await rpc<Notice[]>('f360_push_claim', { p_limit: 100 });
  const results: { id: string; done: boolean; result: string }[] = [];
  for (const n of notices) {
    const tokens = (n.tokens ?? []).filter((t) => /^Expo(nent)?PushToken\[/.test(t));
    if (!tokens.length) { results.push({ id: n.id, done: true, result: 'sin dispositivo' }); continue; }
    try {
      const r = await fetchImpl('https://exp.host/--/api/v2/push/send', { method: 'POST',
        headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
        body: JSON.stringify(tokens.map((to) => ({ to, title: n.title, body: n.body, data: n.data, sound: 'default', priority: 'high', channelId: 'apartados' }))) });
      const body = await r.json().catch(() => null) as { data?: { status?: string }[] } | null;
      const okCount = (body?.data ?? []).filter((d) => d.status === 'ok').length;
      results.push(r.ok && okCount > 0 ? { id: n.id, done: true, result: `ok ${okCount}/${tokens.length}` } : { id: n.id, done: false, result: `expo ${r.status}` });
    } catch (e) {
      results.push({ id: n.id, done: false, result: String((e as Error).message).slice(0, 120) });
    }
  }
  if (results.length) await rpc('f360_push_result', { p_results: results });
  return json({ claimed: notices.length, sent: results.filter((r) => r.result.startsWith('ok')).length, results: results.map((r) => r.result) });
}
