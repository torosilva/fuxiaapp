// Supabase Edge Function entry (Deno). NOT deployed in P2.3A (local Woo only). In a real environment it is called
// every minute by a scheduler (pg_cron + pg_net, Bearer F360_SYNC_SECRET) and on demand by owners/operators.
import { handleSync } from './handler.ts';

const env = {
  SUPABASE_URL: Deno.env.get('SUPABASE_URL') ?? '',
  SUPABASE_ANON_KEY: Deno.env.get('SUPABASE_ANON_KEY') ?? '',
  SUPABASE_SERVICE_ROLE_KEY: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  WOO_TARGET_KEY: Deno.env.get('WOO_TARGET_KEY') ?? '',
  WOO_BASE_URL: Deno.env.get('WOO_BASE_URL') ?? '',
  WOO_USER: Deno.env.get('WOO_USER') ?? '',
  WOO_SECRET: Deno.env.get('WOO_SECRET') ?? '',
  F360_SYNC_SECRET: Deno.env.get('F360_SYNC_SECRET') ?? '',
};

Deno.serve((req) => handleSync(req, env));
