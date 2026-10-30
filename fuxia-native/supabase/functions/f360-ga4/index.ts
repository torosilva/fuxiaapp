// Supabase Edge Function entry (Deno). Daily by pg_cron (f360.growth_source_tick, Bearer F360_SYNC_SECRET).
import { handleGa4 } from './handler.ts';

const env = {
  SUPABASE_URL: Deno.env.get('SUPABASE_URL') ?? '',
  SUPABASE_ANON_KEY: Deno.env.get('SUPABASE_ANON_KEY') ?? '',
  SUPABASE_SERVICE_ROLE_KEY: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  GA4_SA_KEY_JSON: Deno.env.get('GA4_SA_KEY_JSON') ?? '',
  GA4_PROPERTY_ID: Deno.env.get('GA4_PROPERTY_ID') ?? '',
  F360_SYNC_SECRET: Deno.env.get('F360_SYNC_SECRET') ?? '',
};

Deno.serve((req) => handleGa4(req, env));
