// f360-whatsapp — sends the queued thank-you WhatsApps (f360.whatsapp_outbox) through Twilio with the approved template
// fuxia_gracias_compra (TWILIO_THANKS_CONTENT_SID). Called by the database (pg_net kick when a message is queued + a 1-minute
// pg_cron tick). It takes no input: the database decides WHO gets WHAT (f360_whatsapp_claim, which also guarantees one
// sender per message) and this function only delivers and reports back (f360_whatsapp_result). Without the template SID
// configured it sends nothing. It also asks Twilio whether Meta has APPROVED the template (Content API approval status) and
// sends nothing until it is — messages simply wait (expiring after 3 days), so nobody has to watch for the approval.
// Each kind has a list of template SIDs in order of preference ("HXcard,HXplain"): the FIRST one Meta has approved is used,
// so a nicer template replaces the current one by itself the moment it is approved.
export type WhatsAppEnv = { SUPABASE_URL: string; SUPABASE_SERVICE_ROLE_KEY: string; TWILIO_ACCOUNT_SID: string; TWILIO_AUTH_TOKEN: string;
  TWILIO_WHATSAPP_FROM: string; TWILIO_THANKS_CONTENT_SID: string; TWILIO_THANKS_MEMBER_CONTENT_SID?: string };
type Msg = { id: string; kind: string; phone: string; variables: Record<string, string> };

// Twilio WhatsApp México expects +521 + 10 digits (same rule as whatsapp-otp).
export function waTo(phone: string) {
  const p = phone.startsWith('+52') && !phone.startsWith('+521') && phone.length === 13 ? `+521${phone.slice(3)}` : phone;
  return `whatsapp:${p}`;
}

export async function handleWhatsApp(req: Request, env: WhatsAppEnv, fetchImpl: typeof fetch = fetch): Promise<Response> {
  const json = (data: unknown, status = 200) => new Response(JSON.stringify(data), { status, headers: { 'Content-Type': 'application/json' } });
  if (req.method !== 'POST') return json({ error: 'Método no permitido.' }, 405);
  const lists: Record<string, string[]> = {
    thanks: (env.TWILIO_THANKS_CONTENT_SID ?? '').split(',').map((x) => x.trim()).filter(Boolean),
    thanks_member: (env.TWILIO_THANKS_MEMBER_CONTENT_SID ?? '').split(',').map((x) => x.trim()).filter(Boolean),
  };
  if (!lists.thanks.length && !lists.thanks_member.length) return json({ ok: true, skipped: 'sin plantilla aprobada' });
  if (!env.SUPABASE_URL || !env.SUPABASE_SERVICE_ROLE_KEY || !env.TWILIO_ACCOUNT_SID || !env.TWILIO_AUTH_TOKEN || !env.TWILIO_WHATSAPP_FROM) {
    return json({ error: 'No configurado.' }, 500);
  }
  const rpc = async <T>(fn: string, args: Record<string, unknown>): Promise<T> => {
    const r = await fetchImpl(`${env.SUPABASE_URL}/rest/v1/rpc/${fn}`, { method: 'POST',
      headers: { apikey: env.SUPABASE_SERVICE_ROLE_KEY, Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`, 'Content-Type': 'application/json' }, body: JSON.stringify(args) });
    const text = await r.text(); const data = text ? JSON.parse(text) : null;
    if (!r.ok) throw new Error((data as { message?: string } | null)?.message ?? `${fn} falló`);
    return data as T;
  };
  const auth = `Basic ${btoa(`${env.TWILIO_ACCOUNT_SID}:${env.TWILIO_AUTH_TOKEN}`)}`;
  const chosen: Record<string, string> = {};
  for (const [kind, sids] of Object.entries(lists)) {
    for (const sid of sids) { if ((await templateStatus(sid, auth, fetchImpl)) === 'approved') { chosen[kind] = sid; break; } }
  }
  const kinds = Object.keys(chosen);
  if (!kinds.length) return json({ ok: true, skipped: 'plantilla pendiente de aprobación' });
  const from = env.TWILIO_WHATSAPP_FROM.startsWith('whatsapp:') ? env.TWILIO_WHATSAPP_FROM : `whatsapp:${env.TWILIO_WHATSAPP_FROM}`;
  const msgs = await rpc<Msg[]>('f360_whatsapp_claim', { p_limit: 20, p_kinds: kinds });
  let sent = 0, failed = 0;
  for (const m of msgs) {
    try {
      const res = await fetchImpl(`https://api.twilio.com/2010-04-01/Accounts/${env.TWILIO_ACCOUNT_SID}/Messages.json`, {
        method: 'POST', headers: { Authorization: auth, 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({ From: from, To: waTo(m.phone), ContentSid: chosen[m.kind], ContentVariables: JSON.stringify(m.variables) }).toString(),
      });
      const body = await res.json().catch(() => ({})) as { sid?: string; code?: number; message?: string };
      if (res.ok && body.sid) { sent++; await rpc('f360_whatsapp_result', { p_id: m.id, p_ok: true, p_provider_id: body.sid, p_result: 'enviado' }); }
      else { failed++; await rpc('f360_whatsapp_result', { p_id: m.id, p_ok: false, p_provider_id: null, p_result: `twilio ${res.status} ${body.code ?? ''} ${body.message ?? ''}`.trim() }); }
    } catch (e) {
      failed++;
      try { await rpc('f360_whatsapp_result', { p_id: m.id, p_ok: false, p_provider_id: null, p_result: (e as Error).message }); } catch { /* retried after 2 min */ }
    }
  }
  return json({ ok: true, claimed: msgs.length, sent, failed });
}

// WhatsApp approval status of a Content template ('approved', 'pending', 'rejected', 'unsubmitted', … or 'desconocido').
export async function templateStatus(sid: string, auth: string, fetchImpl: typeof fetch = fetch): Promise<string> {
  try {
    const r = await fetchImpl(`https://content.twilio.com/v1/Content/${sid}/ApprovalRequests`, { headers: { Authorization: auth } });
    if (!r.ok) return 'desconocido';
    const b = await r.json() as { whatsapp?: { status?: string } };
    return String(b.whatsapp?.status ?? 'desconocido').toLowerCase();
  } catch { return 'desconocido'; }
}
