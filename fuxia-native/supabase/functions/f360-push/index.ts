// Supabase Edge Function entry (Deno). Deployed with --no-verify-jwt: the caller is the database (pg_net), authorized by
// Bearer F360_PUSH_SECRET (the same value lives in Vault as 'f360_push_secret').
import { handlePush } from './handler.ts';

const env = {
  SUPABASE_URL: Deno.env.get('SUPABASE_URL') ?? '',
  SUPABASE_SERVICE_ROLE_KEY: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  F360_PUSH_SECRET: Deno.env.get('F360_PUSH_SECRET') ?? '',
};

Deno.serve((req) => handlePush(req, env));
