import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';

interface RequestBody {
  amount: number;      // total en MXN
  pairs_count: number; // número de pares en la orden
}

interface ResponseBody {
  points_earned: number;
  breakdown: {
    points_from_amount: number;
    points_from_pairs: number;
  };
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
      },
    });
  }

  try {
    const { amount, pairs_count }: RequestBody = await req.json();

    if (typeof amount !== 'number' || amount < 0) {
      return new Response(JSON.stringify({ error: 'amount must be a non-negative number' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    if (typeof pairs_count !== 'number' || pairs_count < 0) {
      return new Response(JSON.stringify({ error: 'pairs_count must be a non-negative number' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    const points_from_amount = Math.floor(amount / 50);
    const points_from_pairs = pairs_count * 10;
    const points_earned = points_from_amount + points_from_pairs;

    const body: ResponseBody = {
      points_earned,
      breakdown: { points_from_amount, points_from_pairs },
    };

    return new Response(JSON.stringify(body), {
      headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
    });
  } catch {
    return new Response(JSON.stringify({ error: 'Invalid request body' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }
});
