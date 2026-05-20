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

  const REPLICATE_API_TOKEN = Deno.env.get('REPLICATE_API_TOKEN');
  if (!REPLICATE_API_TOKEN) {
    console.error('[tryon] REPLICATE_API_TOKEN not set');
    return json({ error: 'Servicio no configurado. Contacta al administrador.' }, 503);
  }

  let body: { human_image: string; garment_image: string; category?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: 'Invalid JSON' }, 400);
  }

  const { human_image, garment_image } = body;
  // fashn/tryon only accepts upper_body | lower_body | dresses — shoes maps to lower_body
  const category = 'lower_body';
  if (!human_image || !garment_image) {
    return json({ error: 'human_image and garment_image son requeridos' }, 400);
  }

  // Start prediction on Replicate using the public fashn/tryon model.
  // /v1/deployments/ is reserved for user-owned deployments (404 for public models);
  // /v1/models/{owner}/{name}/predictions is the right path for public models.
  let startRes: Response;
  let prediction: Record<string, unknown>;
  try {
    startRes = await fetch('https://api.replicate.com/v1/models/fashn/tryon/predictions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${REPLICATE_API_TOKEN}`,
        'Content-Type': 'application/json',
        'Prefer': 'wait=30',
      },
      body: JSON.stringify({
        input: {
          model_image: human_image,
          garment_image,
          category,
          garment_photo_type: 'auto',
          long_top: false,
        },
      }),
    });
    prediction = await startRes.json();
  } catch (err) {
    console.error('[tryon] fetch error:', err);
    return json({ error: 'No se pudo conectar con el servicio de IA. Intenta de nuevo.' }, 502);
  }

  if (!startRes.ok) {
    const detail = (prediction as any)?.detail ?? JSON.stringify(prediction);
    console.error('[tryon] replicate error:', startRes.status, detail);
    if (startRes.status === 401) {
      return json({ error: 'API key de Replicate inválida. Contacta al administrador.' }, 503);
    }
    if (startRes.status === 422) {
      return json({ error: 'La imagen no pudo ser procesada. Intenta con otra foto.' }, 422);
    }
    return json({ error: `Error del servicio de IA (${startRes.status}): ${detail}` }, 500);
  }

  if (prediction.status === 'starting' || prediction.status === 'processing') {
    return json({ id: prediction.id, status: prediction.status });
  }

  if (prediction.status === 'succeeded') {
    const output = Array.isArray(prediction.output) ? prediction.output[0] : prediction.output;
    return json({ status: 'succeeded', output });
  }

  if (prediction.status === 'failed') {
    const errMsg = (prediction as any)?.error ?? 'El modelo no pudo procesar la imagen.';
    console.error('[tryon] prediction failed:', errMsg);
    return json({ error: errMsg }, 500);
  }

  return json({ error: 'Respuesta inesperada del servicio', detail: prediction }, 500);
});
