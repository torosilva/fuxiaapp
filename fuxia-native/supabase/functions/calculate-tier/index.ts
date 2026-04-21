import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';

type Tier = 'bronze' | 'silver' | 'gold';

interface TierRule {
  tier: Tier;
  min_pairs: number;
  min_points: number;
}

const TIERS: TierRule[] = [
  { tier: 'gold',   min_pairs: 13, min_points: 1201 },
  { tier: 'silver', min_pairs: 6,  min_points: 501  },
  { tier: 'bronze', min_pairs: 0,  min_points: 0    },
];

const TIER_ORDER: Tier[] = ['bronze', 'silver', 'gold'];

interface RequestBody {
  total_points: number;
  pairs_count: number;
}

interface ResponseBody {
  tier: Tier;
  next_tier: Tier | null;
  points_to_next: number | null;
  pairs_to_next: number | null;
}

function calculateTier(total_points: number, pairs_count: number): Tier {
  for (const rule of TIERS) {
    if (total_points >= rule.min_points || pairs_count >= rule.min_pairs) {
      return rule.tier;
    }
  }
  return 'bronze';
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
    const { total_points, pairs_count }: RequestBody = await req.json();

    if (typeof total_points !== 'number' || typeof pairs_count !== 'number') {
      return new Response(JSON.stringify({ error: 'total_points and pairs_count must be numbers' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    const tier = calculateTier(total_points, pairs_count);
    const tierIndex = TIER_ORDER.indexOf(tier);
    const next_tier: Tier | null = tierIndex < TIER_ORDER.length - 1 ? TIER_ORDER[tierIndex + 1] : null;

    let points_to_next: number | null = null;
    let pairs_to_next: number | null = null;

    if (next_tier) {
      const nextRule = TIERS.find((r) => r.tier === next_tier)!;
      points_to_next = Math.max(0, nextRule.min_points - total_points);
      pairs_to_next = Math.max(0, nextRule.min_pairs - pairs_count);
    }

    const body: ResponseBody = { tier, next_tier, points_to_next, pairs_to_next };

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
