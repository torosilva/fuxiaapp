// Supabase Edge Function entry (Deno). Daily by pg_cron (f360.meta_spend_tick, Bearer F360_SYNC_SECRET); backfill by an owner.
import { handleMetaSpend } from './handler.ts';

const env = {
  SUPABASE_URL: Deno.env.get('SUPABASE_URL') ?? '',
  SUPABASE_ANON_KEY: Deno.env.get('SUPABASE_ANON_KEY') ?? '',
  SUPABASE_SERVICE_ROLE_KEY: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  META_ADS_TOKEN: Deno.env.get('META_ADS_TOKEN') ?? '',
  META_AD_ACCOUNT_ID: Deno.env.get('META_AD_ACCOUNT_ID') ?? '',
  META_API_VERSION: Deno.env.get('META_API_VERSION') ?? '',
  F360_SYNC_SECRET: Deno.env.get('F360_SYNC_SECRET') ?? '',
};

Deno.serve((req) => handleMetaSpend(req, env));
