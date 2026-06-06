import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';

/**
 * Calcula puntos de lealtad para una orden.
 *
 * Regla oficial Fuxia: **100 puntos por cada par**. El monto no influye —
 * todos los pares valen lo mismo en puntos para que el cliente no se confunda
 * y el equipo de tienda pueda calcular en la cabeza.
 *
 * El campo `amount` queda en el body request por compatibilidad con clientes
 * existentes que aún lo mandan, pero se ignora en el cálculo. Si querés
 * volver a una fórmula híbrida en el futuro, este es el lugar.
 */

interface RequestBody {
  amount?: number;     // total en moneda local — actualmente IGNORADO
  pairs_count: number; // número de pares en la orden
}

interface ResponseBody {
  points_earned: number;
  breakdown: { points_per_pair: number; pairs: number };
}

const POINTS_PER_PAIR = 100;

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

  try {
    const body: RequestBody = await req.json();

    if (typeof body.pairs_count !== 'number' || body.pairs_count < 0) {
      return json({ error: 'pairs_count must be a non-negative number' }, 400);
    }

    const pairs = Math.floor(body.pairs_count);
    const points_earned = pairs * POINTS_PER_PAIR;

    const resp: ResponseBody = {
      points_earned,
      breakdown: { points_per_pair: POINTS_PER_PAIR, pairs },
    };
    return json(resp);
  } catch {
    return json({ error: 'Invalid request body' }, 400);
  }
});
