// Supabase Edge Function entry (Deno). Called by the admin with the user's session (deploy with --no-verify-jwt: the handler
// verifies the session itself and every data read goes through the board gate with that same session).
import { handleAnalyst } from './handler.ts';

const env = {
  SUPABASE_URL: Deno.env.get('SUPABASE_URL') ?? '',
  SUPABASE_ANON_KEY: Deno.env.get('SUPABASE_ANON_KEY') ?? '',
  SUPABASE_SERVICE_ROLE_KEY: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  ANTHROPIC_API_KEY: Deno.env.get('ANTHROPIC_API_KEY') ?? '',
  F360_AI_PROVIDER: Deno.env.get('F360_AI_PROVIDER') ?? '',
};

Deno.serve((req) => handleAnalyst(req, env));
