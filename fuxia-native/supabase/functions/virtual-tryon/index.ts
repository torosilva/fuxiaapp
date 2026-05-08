import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';

const REPLICATE_API_TOKEN = Deno.env.get('REPLICATE_API_TOKEN')!;

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

  let body: { human_image: string; garment_image: string; category?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: 'Invalid JSON' }, 400);
  }

  const { human_image, garment_image, category = 'shoes' } = body;
  if (!human_image || !garment_image) {
    return json({ error: 'human_image and garment_image are required' }, 400);
  }

  // Start prediction on Replicate using fashn/tryon model
  const startRes = await fetch('https://api.replicate.com/v1/models/fashn/tryon/predictions', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${REPLICATE_API_TOKEN}`,
      'Content-Type': 'application/json',
      'Prefer': 'wait=30', // wait up to 30s for result
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

  const prediction = await startRes.json();

  if (!startRes.ok) {
    console.error('[tryon] replicate error:', JSON.stringify(prediction));
    return json({ error: 'Replicate error', detail: prediction }, 500);
  }

  // If still processing, return prediction ID for polling
  if (prediction.status === 'starting' || prediction.status === 'processing') {
    return json({ id: prediction.id, status: prediction.status });
  }

  // Completed synchronously
  if (prediction.status === 'succeeded') {
    const output = Array.isArray(prediction.output) ? prediction.output[0] : prediction.output;
    return json({ status: 'succeeded', output });
  }

  return json({ error: 'Prediction failed', detail: prediction }, 500);
});
