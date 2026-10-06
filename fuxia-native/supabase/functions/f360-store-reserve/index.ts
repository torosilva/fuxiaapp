// Supabase Edge Function entry (Deno). Public (--no-verify-jwt): it is called from the store's product page.
import { handleReserve } from './handler.ts';

const env = {
  SUPABASE_URL: Deno.env.get('SUPABASE_URL') ?? '',
  SUPABASE_SERVICE_ROLE_KEY: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  ALLOWED_ORIGINS: Deno.env.get('F360_RESERVE_ORIGINS') ?? '',
  TEST_PHONES: Deno.env.get('F360_RESERVE_TEST_PHONES') ?? '',
  TEST_CODE: Deno.env.get('F360_RESERVE_TEST_CODE') ?? '',
  WOO_BASE_URL: Deno.env.get('WOO_BASE_URL') ?? '',
  WOO_USER: Deno.env.get('WOO_USER') ?? '',
  WOO_SECRET: Deno.env.get('WOO_SECRET') ?? '',
  TARGET_KEY: Deno.env.get('F360_STOREFRONT_TARGET') ?? '',   // the store this project serves (same secret as f360-storefront)
};

Deno.serve((req) => handleReserve(req, env));
