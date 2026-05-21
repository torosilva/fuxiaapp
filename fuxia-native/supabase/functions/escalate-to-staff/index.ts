/**
 * Escalate a Hilo chat conversation to a human team member.
 *
 * Triggered from the mobile app when Hilo returns `escalate: true`. Does two things:
 *   1. Inserts a row in support_tickets for historical record (admin panel reads this).
 *   2. Sends a WhatsApp message to each number in SUPPORT_STAFF_WHATSAPP env var
 *      (comma-separated, e.g. "+5215512345678,+5215587654321") via Twilio so
 *      whoever is on duty reacts immediately.
 *
 * Required Supabase secrets:
 *   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY  (for the DB insert)
 *   TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_WHATSAPP_FROM  (for the WhatsApp)
 *   SUPPORT_STAFF_WHATSAPP   (comma-separated phone list)
 */
import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const TWILIO_ACCOUNT_SID = Deno.env.get('TWILIO_ACCOUNT_SID') ?? '';
const TWILIO_AUTH_TOKEN = Deno.env.get('TWILIO_AUTH_TOKEN') ?? '';
const TWILIO_WHATSAPP_FROM = Deno.env.get('TWILIO_WHATSAPP_FROM') ?? '';
const SUPPORT_STAFF_WHATSAPP = Deno.env.get('SUPPORT_STAFF_WHATSAPP') ?? '';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json', ...CORS },
  });
}

interface ChatMessage { role: 'user' | 'assistant' | 'system'; content: string; }
interface EscalateBody {
  customer_id?: string | null;
  customer_phone?: string | null;
  customer_name?: string | null;
  last_messages: ChatMessage[];   // last N from the chat for context
  topic?: string | null;          // optional short subject (e.g. last user message truncated)
}

function normalizeWhatsApp(phone: string): string {
  const p = phone.trim();
  if (p.startsWith('whatsapp:')) return p;
  // Mexico needs +521 prefix for WhatsApp (vs +52 for voice)
  if (p.startsWith('+52') && !p.startsWith('+521')) return `whatsapp:+521${p.slice(3)}`;
  return p.startsWith('+') ? `whatsapp:${p}` : `whatsapp:+${p}`;
}

function formatChatForWhatsApp(messages: ChatMessage[]): string {
  return messages.slice(-6).map((m) => {
    const who = m.role === 'user' ? '👤' : m.role === 'assistant' ? '🤖' : '⚙️';
    const text = m.content.length > 240 ? m.content.slice(0, 240) + '…' : m.content;
    return `${who} ${text}`;
  }).join('\n\n');
}

async function sendWhatsAppToStaff(payload: {
  customer_phone: string | null;
  customer_name: string | null;
  ticket_id: string;
  conversation: string;
  topic: string | null;
}): Promise<{ sent: number; failed: number }> {
  if (!TWILIO_ACCOUNT_SID || !TWILIO_AUTH_TOKEN || !TWILIO_WHATSAPP_FROM) {
    console.warn('[escalate] Twilio not configured, skipping WhatsApp notifications');
    return { sent: 0, failed: 0 };
  }
  if (!SUPPORT_STAFF_WHATSAPP) {
    console.warn('[escalate] SUPPORT_STAFF_WHATSAPP env not set, no recipients');
    return { sent: 0, failed: 0 };
  }

  const recipients = SUPPORT_STAFF_WHATSAPP.split(',').map((s) => s.trim()).filter(Boolean);
  const from = TWILIO_WHATSAPP_FROM.startsWith('whatsapp:') ? TWILIO_WHATSAPP_FROM : `whatsapp:${TWILIO_WHATSAPP_FROM}`;
  const auth = btoa(`${TWILIO_ACCOUNT_SID}:${TWILIO_AUTH_TOKEN}`);
  const url = `https://api.twilio.com/2010-04-01/Accounts/${TWILIO_ACCOUNT_SID}/Messages.json`;

  const customerLabel = payload.customer_name
    ? `${payload.customer_name} (${payload.customer_phone ?? 'sin tel'})`
    : (payload.customer_phone ?? 'Cliente anónimo');
  const topicLine = payload.topic ? `\n\n📌 ${payload.topic}` : '';
  const replyHint = payload.customer_phone
    ? `\n\n💬 Responder al cliente: https://wa.me/${payload.customer_phone.replace(/[^\d]/g, '')}`
    : '';
  const body = `🆘 *Hilo escaló un caso*\n\nCliente: ${customerLabel}${topicLine}\n\n----- Conversación -----\n${payload.conversation}${replyHint}\n\nTicket: ${payload.ticket_id.slice(0, 8)}`;

  let sent = 0, failed = 0;
  for (const to of recipients) {
    try {
      const form = new URLSearchParams({ From: from, To: normalizeWhatsApp(to), Body: body });
      const res = await fetch(url, {
        method: 'POST',
        headers: { 'Authorization': `Basic ${auth}`, 'Content-Type': 'application/x-www-form-urlencoded' },
        body: form,
      });
      if (res.ok) {
        sent++;
      } else {
        failed++;
        console.error(`[escalate] Twilio ${res.status} for ${to}: ${await res.text()}`);
      }
    } catch (err) {
      failed++;
      console.error(`[escalate] Twilio threw for ${to}:`, err);
    }
  }
  return { sent, failed };
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  let body: EscalateBody;
  try { body = await req.json(); } catch { return json({ error: 'Invalid JSON' }, 400); }

  if (!Array.isArray(body.last_messages) || body.last_messages.length === 0) {
    return json({ error: 'last_messages requerido' }, 400);
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  // 1. Insert ticket.
  const { data: ticket, error: insertErr } = await supabase
    .from('support_tickets')
    .insert({
      customer_id: body.customer_id ?? null,
      customer_phone: body.customer_phone ?? null,
      customer_name: body.customer_name ?? null,
      last_messages: body.last_messages,
      topic: body.topic ?? null,
      status: 'open',
    })
    .select('id')
    .single();

  if (insertErr || !ticket) {
    console.error('[escalate] insert failed:', insertErr?.message);
    return json({ error: 'No se pudo crear el ticket', detail: insertErr?.message }, 500);
  }

  // 2. Notify staff via WhatsApp (best-effort, doesn't block ticket creation).
  const conversation = formatChatForWhatsApp(body.last_messages);
  const notify = await sendWhatsAppToStaff({
    customer_phone: body.customer_phone ?? null,
    customer_name: body.customer_name ?? null,
    ticket_id: ticket.id,
    conversation,
    topic: body.topic ?? null,
  });

  return json({
    ok: true,
    ticket_id: ticket.id,
    notified_staff: notify.sent,
    failed_notifications: notify.failed,
  });
});
