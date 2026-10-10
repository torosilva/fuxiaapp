// Supabase Edge Function entry (Deno). NOT deployed in P2.3A (local Woo only). Deploy with --no-verify-jwt:
// Woo cannot send a Supabase JWT; authenticity comes from the HMAC signature (WOO_WEBHOOK_SECRET).
import { handleOrders } from './handler.ts';

const env = {
  SUPABASE_URL: Deno.env.get('SUPABASE_URL') ?? '',
  SUPABASE_SERVICE_ROLE_KEY: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  WOO_TARGET_KEY: Deno.env.get('WOO_TARGET_KEY') ?? '',
  WOO_WEBHOOK_SECRET: Deno.env.get('WOO_WEBHOOK_SECRET') ?? '',
  // read-only refund detail for Commerce Facts (same store credentials f360-woo-sync uses)
  WOO_BASE_URL: Deno.env.get('WOO_BASE_URL') ?? '',
  WOO_USER: Deno.env.get('WOO_USER') ?? '',
  WOO_SECRET: Deno.env.get('WOO_SECRET') ?? '',
  WOO_EXPECTED_SOURCE: Deno.env.get('WOO_EXPECTED_SOURCE') ?? '',
};

Deno.serve((req) => handleOrders(req, env));
