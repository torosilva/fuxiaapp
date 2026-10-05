// Supabase Edge Function entry (Deno). Public (--no-verify-jwt): it is called from the store's product page.
import { handleStorefront } from './handler.ts';

const env = {
  SUPABASE_URL: Deno.env.get('SUPABASE_URL') ?? '',
  SUPABASE_SERVICE_ROLE_KEY: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  ALLOWED_ORIGINS: Deno.env.get('F360_STOREFRONT_ORIGINS') || Deno.env.get('F360_RESERVE_ORIGINS') || '',
  TARGET_KEY: Deno.env.get('F360_STOREFRONT_TARGET') ?? '',
  SERVER_KEY: Deno.env.get('F360_STOREFRONT_SERVER_KEY') ?? '',
};

Deno.serve((req) => handleStorefront(req, env));
