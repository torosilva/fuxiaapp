// Supabase Edge Function entry (Deno). --no-verify-jwt: the caller is the database (pg_net), Bearer F360_EMAIL_SECRET.
import { handleEmail } from './handler.ts';
Deno.serve((req) => handleEmail(req, {
  SUPABASE_URL: Deno.env.get('SUPABASE_URL') ?? '', SUPABASE_SERVICE_ROLE_KEY: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  F360_EMAIL_SECRET: Deno.env.get('F360_EMAIL_SECRET') ?? '', RESEND_API_KEY: Deno.env.get('RESEND_API_KEY') ?? '', EMAIL_FROM: Deno.env.get('EMAIL_FROM') ?? '',
}));
