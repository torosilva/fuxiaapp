// Supabase Edge Function entry (Deno). Deploy with --no-verify-jwt: Shopify cannot send a Supabase JWT; authenticity comes
// from the HMAC signature (the Fuxia 360 app's client secret) and the shop domain.
import { handleShopify } from './handler.ts';

const env = {
  SUPABASE_URL: Deno.env.get('SUPABASE_URL') ?? '',
  SUPABASE_SERVICE_ROLE_KEY: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  SHOPIFY_SHOP: Deno.env.get('SHOPIFY_SHOP') ?? '',
  SHOPIFY_CLIENT_SECRET: Deno.env.get('SHOPIFY_CLIENT_SECRET') ?? '',
  SHOPIFY_TARGET_KEY: Deno.env.get('SHOPIFY_TARGET_KEY') ?? '',
};

Deno.serve((req) => handleShopify(req, env));
