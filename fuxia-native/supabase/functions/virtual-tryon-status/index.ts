/**
 * Poll status for a FASHN AI try-on prediction.
 * The mobile app sends { id } and we return { status, output? } in a shape
 * the TryOnModal already understands ('succeeded' / 'failed' / 'processing').
 */
import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';

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

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });

  const FASHN_API_KEY = Deno.env.get('FASHN_API_KEY');
  if (!FASHN_API_KEY) {
    return json({ error: 'Servicio no configurado.' }, 503);
  }

  let body: { id: string };
  try { body = await req.json(); } catch { return json({ error: 'Invalid JSON' }, 400); }
  if (!body.id) return json({ error: 'id es requerido' }, 400);

  const res = await fetch(`https://api.fashn.ai/v1/status/${encodeURIComponent(body.id)}`, {
    headers: { 'Authorization': `Bearer ${FASHN_API_KEY}` },
  });
  const prediction = await res.json();

  if (!res.ok) {
    return json({ status: 'failed', error: (prediction as any)?.error?.message ?? 'Error consultando estado' }, 200);
  }

  // FASHN statuses: starting | in_queue | processing | completed | failed | canceled.
  // The app expects: succeeded | failed | processing — map them.
  const rawStatus = (prediction as any)?.status;
  if (rawStatus === 'completed') {
    const output = Array.isArray(prediction.output) ? prediction.output[0] : prediction.output;
    return json({ status: 'succeeded', output });
  }
  if (rawStatus === 'failed' || rawStatus === 'canceled') {
    return json({ status: 'failed', error: (prediction as any)?.error?.message ?? 'El modelo no pudo procesar la imagen' });
  }
  return json({ status: 'processing' });
});
