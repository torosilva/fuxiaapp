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

  let body: { id: string };
  try { body = await req.json(); } catch { return json({ error: 'Invalid JSON' }, 400); }

  const res = await fetch(`https://api.replicate.com/v1/predictions/${body.id}`, {
    headers: { 'Authorization': `Bearer ${REPLICATE_API_TOKEN}` },
  });

  const prediction = await res.json();
  const output = prediction.status === 'succeeded'
    ? (Array.isArray(prediction.output) ? prediction.output[0] : prediction.output)
    : null;

  return json({ status: prediction.status, output });
});
