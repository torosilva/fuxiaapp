// Supabase Edge Function entry (Deno). Daily by pg_cron (f360.growth_source_tick, Bearer F360_SYNC_SECRET).
import { handleClarity } from './handler.ts';

const env = {
  SUPABASE_URL: Deno.env.get('SUPABASE_URL') ?? '',
  SUPABASE_ANON_KEY: Deno.env.get('SUPABASE_ANON_KEY') ?? '',
  SUPABASE_SERVICE_ROLE_KEY: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  CLARITY_API_TOKEN: Deno.env.get('CLARITY_API_TOKEN') ?? '',
  F360_SYNC_SECRET: Deno.env.get('F360_SYNC_SECRET') ?? '',
};

Deno.serve((req) => handleClarity(req, env));
