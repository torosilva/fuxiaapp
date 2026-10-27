// Supabase Edge Function entry (Deno). Daily and every 4 h by pg_cron (f360.growth_source_tick, Bearer F360_SYNC_SECRET); backfill by an owner.
import { handleInstagram } from './handler.ts';

const env = {
  SUPABASE_URL: Deno.env.get('SUPABASE_URL') ?? '',
  SUPABASE_ANON_KEY: Deno.env.get('SUPABASE_ANON_KEY') ?? '',
  SUPABASE_SERVICE_ROLE_KEY: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  INSTAGRAM_TOKEN: Deno.env.get('INSTAGRAM_TOKEN') ?? '',
  META_ADS_TOKEN: Deno.env.get('META_ADS_TOKEN') ?? '',
  INSTAGRAM_USER_ID: Deno.env.get('INSTAGRAM_USER_ID') ?? '',
  META_API_VERSION: Deno.env.get('META_API_VERSION') ?? '',
  F360_SYNC_SECRET: Deno.env.get('F360_SYNC_SECRET') ?? '',
};

Deno.serve((req) => handleInstagram(req, env));
