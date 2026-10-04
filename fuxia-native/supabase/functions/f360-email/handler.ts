// f360-email — sends queued Fuxia 360 e-mails (f360.email_outbox), e.g. "a la medida" requests → info@fuxiaballerinas.com.
// Called by the database (pg_net + cron retry) with Bearer F360_EMAIL_SECRET. Provider: Resend (RESEND_API_KEY +
// EMAIL_FROM, a verified sender). Without a provider nothing is lost: rows stay pending and go out once it is configured.
export type EmailEnv = { SUPABASE_URL: string; SUPABASE_SERVICE_ROLE_KEY: string; F360_EMAIL_SECRET: string; RESEND_API_KEY: string; EMAIL_FROM: string };
type Mail = { id: string; to: string; subject: string; text: string; reply_to: string | null };

function safeEqual(a: string, b: string) {
  if (!a || a.length !== b.length) return false;
  let x = 0; for (let i = 0; i < a.length; i++) x |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return x === 0;
}

export async function handleEmail(req: Request, env: EmailEnv, fetchImpl: typeof fetch = fetch): Promise<Response> {
  const json = (d: unknown, status = 200) => new Response(JSON.stringify(d), { status, headers: { 'Content-Type': 'application/json' } });
  if (req.method !== 'POST') return json({ error: 'Método no permitido.' }, 405);
  if (!env.F360_EMAIL_SECRET || !safeEqual(req.headers.get('Authorization') ?? '', `Bearer ${env.F360_EMAIL_SECRET}`)) return json({ error: 'No autorizado.' }, 401);
  const rpc = async <T>(fn: string, args: Record<string, unknown>): Promise<T> => {
    const r = await fetchImpl(`${env.SUPABASE_URL}/rest/v1/rpc/${fn}`, { method: 'POST',
      headers: { apikey: env.SUPABASE_SERVICE_ROLE_KEY, Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`, 'Content-Type': 'application/json' }, body: JSON.stringify(args) });
    const data = await r.json().catch(() => null);
    if (!r.ok) throw new Error((data as { message?: string } | null)?.message ?? `${fn} falló`);
    return data as T;
  };
  const mails = await rpc<Mail[]>('f360_email_claim', { p_limit: 50 });
  const results: { id: string; done: boolean; retry_free?: boolean; result: string }[] = [];
  for (const m of mails) {
    if (!env.RESEND_API_KEY || !env.EMAIL_FROM) { results.push({ id: m.id, done: false, retry_free: true, result: 'sin proveedor de correo' }); continue; }
    try {
      const r = await fetchImpl('https://api.resend.com/emails', { method: 'POST',
        headers: { Authorization: `Bearer ${env.RESEND_API_KEY}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ from: env.EMAIL_FROM, to: [m.to], subject: m.subject, text: m.text, ...(m.reply_to ? { reply_to: m.reply_to } : {}) }) });
      const b = await r.json().catch(() => ({})) as { id?: string; message?: string };
      results.push(r.ok ? { id: m.id, done: true, result: `ok ${b.id ?? ''}` } : { id: m.id, done: false, result: `resend ${r.status} ${b.message ?? ''}` });
    } catch (e) { results.push({ id: m.id, done: false, result: String((e as Error).message).slice(0, 200) }); }
  }
  if (results.length) await rpc('f360_email_result', { p_results: results });
  return json({ claimed: mails.length, sent: results.filter((r) => r.done).length, results: results.map((r) => r.result) });
}
