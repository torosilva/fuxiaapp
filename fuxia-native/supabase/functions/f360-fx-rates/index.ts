// Supabase Edge Function entry (Deno). Daily by pg_cron (f360.fx_daily_tick, Bearer F360_SYNC_SECRET); backfill by an owner.
import { handleFx } from './handler.ts';

const env = {
  SUPABASE_URL: Deno.env.get('SUPABASE_URL') ?? '',
  SUPABASE_ANON_KEY: Deno.env.get('SUPABASE_ANON_KEY') ?? '',
  SUPABASE_SERVICE_ROLE_KEY: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  F360_SYNC_SECRET: Deno.env.get('F360_SYNC_SECRET') ?? '',
};

Deno.serve((req) => handleFx(req, env));
