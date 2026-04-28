import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';

const WC_URL = Deno.env.get('WC_URL')!;                    // e.g. https://fuxiaballerinas.com/wp-json/wc/v3
const WC_CONSUMER_KEY = Deno.env.get('WC_CONSUMER_KEY')!;
const WC_CONSUMER_SECRET = Deno.env.get('WC_CONSUMER_SECRET')!;

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

// Only allow read-only GET calls to safe paths. Blocks order mutations, customer PII dumps, etc.
const ALLOWED_PATTERNS: RegExp[] = [
  /^products(\/\d+)?$/,                    // products, products/{id}
  /^products\/\d+\/variations(\/\d+)?$/,   // products/{id}/variations[/id]
  /^products\/categories$/,
  /^products\/attributes$/,
];

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  let body: { path: string; params?: Record<string, string | number> };
  try {
    body = await req.json();
  } catch {
    return json({ error: 'Invalid JSON' }, 400);
  }

  const path = (body.path ?? '').replace(/^\/+|\/+$/g, ''); // trim slashes

  if (!ALLOWED_PATTERNS.some((re) => re.test(path))) {
    return json({ error: 'Path not allowed', path }, 403);
  }

  const url = new URL(`${WC_URL}/${path}`);
  url.searchParams.set('consumer_key', WC_CONSUMER_KEY);
  url.searchParams.set('consumer_secret', WC_CONSUMER_SECRET);

  for (const [k, v] of Object.entries(body.params ?? {})) {
    url.searchParams.set(k, String(v));
  }

  const res = await fetch(url.toString(), { method: 'GET' });
  const text = await res.text();
  const headers = { 'Content-Type': 'application/json', ...CORS };

  // WooCommerce returns JSON; pass through status.
  return new Response(text, { status: res.status, headers });
});
