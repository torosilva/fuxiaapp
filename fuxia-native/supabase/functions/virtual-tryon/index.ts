/**
 * Virtual try-on proxy → FASHN AI (api.fashn.ai).
 *
 * The mobile app POSTs { human_image, garment_image, category? } here.
 * We call FASHN's /v1/run, which is async — it returns an `id` we then poll
 * via the sibling `virtual-tryon-status` function.
 *
 * Requires FASHN_API_KEY in Supabase secrets (Project → Settings → Edge
 * Functions → Secrets). Get a key at https://app.fashn.ai/api.
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
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  const FASHN_API_KEY = Deno.env.get('FASHN_API_KEY');
  if (!FASHN_API_KEY) {
    console.error('[tryon] FASHN_API_KEY not set in Supabase secrets');
    return json({ error: 'Servicio no configurado. Contacta al administrador.' }, 503);
  }

  let body: { human_image: string; garment_image: string; category?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: 'Invalid JSON' }, 400);
  }

  const { human_image, garment_image } = body;
  if (!human_image || !garment_image) {
    return json({ error: 'human_image and garment_image son requeridos' }, 400);
  }

  // FASHN's categories are 'tops' | 'bottoms' | 'one-pieces' | 'auto'.
  // There is no 'shoes' category — 'auto' lets the model infer the garment type.
  const category = 'auto';

  let startRes: Response;
  let prediction: Record<string, unknown>;
  try {
    startRes = await fetch('https://api.fashn.ai/v1/run', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${FASHN_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model_name: 'tryon-v1.6',
        inputs: {
          model_image: human_image,
          garment_image,
          category,
          mode: 'balanced',
          garment_photo_type: 'auto',
          moderation_level: 'permissive',
          num_samples: 1,
          output_format: 'jpeg',
        },
      }),
    });
    prediction = await startRes.json();
  } catch (err) {
    console.error('[tryon] fetch error:', err);
    return json({ error: 'No se pudo conectar con el servicio de IA. Intenta de nuevo.' }, 502);
  }

  if (!startRes.ok) {
    const detail = (prediction as any)?.error?.message
      ?? (prediction as any)?.message
      ?? JSON.stringify(prediction);
    console.error('[tryon] fashn error:', startRes.status, detail);
    if (startRes.status === 401 || startRes.status === 403) {
      return json({ error: 'API key de FASHN inválida. Contacta al administrador.' }, 503);
    }
    if (startRes.status === 422 || startRes.status === 400) {
      return json({ error: `La imagen no pudo ser procesada: ${detail}` }, 422);
    }
    return json({ error: `Error del servicio de IA (${startRes.status}): ${detail}` }, 500);
  }

  // FASHN's /run returns { id } and processing happens async — caller polls /status.
  const id = (prediction as any)?.id;
  if (!id) {
    console.error('[tryon] no id in response:', prediction);
    return json({ error: 'Respuesta inesperada del servicio', detail: prediction }, 500);
  }
  return json({ id, status: 'starting' });
});
