import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;

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
  if (req.method !== 'POST') return json({ error: 'POST only' }, 405);

  const authHeader = req.headers.get('Authorization') ?? '';
  const jwt = authHeader.replace(/^Bearer\s+/i, '').trim();
  if (!jwt) return json({ error: 'Missing Authorization Bearer token' }, 401);

  // Verify the JWT belongs to a real signed-in user before deleting anything.
  const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${jwt}` } },
  });
  const { data: { user }, error: userErr } = await userClient.auth.getUser();
  if (userErr || !user) return json({ error: 'Invalid session' }, 401);

  const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  const phone = user.user_metadata?.phone as string | undefined;

  // Find the customer record by phone (the join key for everything else).
  let customerId: string | null = null;
  if (phone) {
    const { data: customer } = await admin
      .from('customers')
      .select('id')
      .eq('phone', phone)
      .maybeSingle();
    customerId = customer?.id ?? null;
  }

  if (customerId) {
    const { data: cards } = await admin
      .from('loyalty_cards')
      .select('id')
      .eq('customer_id', customerId);
    const cardIds = (cards ?? []).map((c) => c.id);

    if (cardIds.length > 0) {
      const { data: txs } = await admin
        .from('transactions')
        .select('id')
        .in('loyalty_card_id', cardIds);
      const txIds = (txs ?? []).map((t) => t.id);

      if (txIds.length > 0) {
        await admin.from('purchase_items').delete().in('transaction_id', txIds);
      }
      await admin.from('rewards').delete().in('loyalty_card_id', cardIds);
      await admin.from('qr_scans').delete().in('loyalty_card_id', cardIds);
      await admin.from('transactions').delete().in('loyalty_card_id', cardIds);
      await admin.from('loyalty_cards').delete().in('id', cardIds);
    }

    await admin.from('push_tokens').delete().eq('customer_id', customerId);
    await admin.from('otp_verifications').delete().eq('phone', phone);
    await admin.from('customers').delete().eq('id', customerId);
  }

  // Delete any avatar files belonging to this auth user.
  try {
    const { data: files } = await admin.storage.from('avatars').list(user.id);
    if (files && files.length > 0) {
      const paths = files.map((f) => `${user.id}/${f.name}`);
      await admin.storage.from('avatars').remove(paths);
    }
  } catch (err) {
    console.warn(`[delete-account] avatar cleanup failed: ${err instanceof Error ? err.message : err}`);
  }

  // Finally, delete the auth user. This invalidates the JWT.
  const { error: deleteErr } = await admin.auth.admin.deleteUser(user.id);
  if (deleteErr) {
    console.error(`[delete-account] auth deletion failed: ${deleteErr.message}`);
    return json({ error: 'Could not delete account', debug: deleteErr.message }, 500);
  }

  console.log(`[delete-account] deleted user=${user.id} phone=${phone ?? 'unknown'}`);
  return json({ success: true });
});
