import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';

const WC_URL = Deno.env.get('WC_URL')!;
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

const ALLOWED_GET: RegExp[] = [
  /^products(\/\d+)?$/,
  /^products\/\d+\/variations(\/\d+)?$/,
  /^products\/categories$/,
  /^products\/attributes$/,
  /^orders(\/\d+)?$/,
  /^customers$/, // search by email
];

const ALLOWED_POST: RegExp[] = [
  /^customers$/, // create customer
];

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  let body: {
    path: string;
    params?: Record<string, string | number>;
    method?: string;
    body?: Record<string, unknown>;
  };
  try {
    body = await req.json();
  } catch {
    return json({ error: 'Invalid JSON' }, 400);
  }

  const path = (body.path ?? '').replace(/^\/+|\/+$/g, '');
  const wcMethod = (body.method ?? 'GET').toUpperCase();

  const allowed =
    wcMethod === 'POST'
      ? ALLOWED_POST.some((re) => re.test(path))
      : ALLOWED_GET.some((re) => re.test(path));

  if (!allowed) {
    return json({ error: 'Path not allowed', path }, 403);
  }

  const url = new URL(`${WC_URL}/${path}`);
  url.searchParams.set('consumer_key', WC_CONSUMER_KEY);
  url.searchParams.set('consumer_secret', WC_CONSUMER_SECRET);

  if (wcMethod === 'GET') {
    for (const [k, v] of Object.entries(body.params ?? {})) {
      url.searchParams.set(k, String(v));
    }
  }

  const fetchOptions: RequestInit =
    wcMethod === 'POST'
      ? {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(body.body ?? {}),
        }
      : { method: 'GET' };

  const res = await fetch(url.toString(), fetchOptions);
  const text = await res.text();

  return new Response(text, {
    status: res.status,
    headers: { 'Content-Type': 'application/json', ...CORS },
  });
});
