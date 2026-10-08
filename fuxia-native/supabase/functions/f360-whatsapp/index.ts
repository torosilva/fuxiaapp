// Supabase Edge Function entry (Deno). Deployed with --no-verify-jwt: it takes no input and only delivers what the database
// already queued and hands out once (f360_whatsapp_claim), so any call just sends pending thank-yous sooner.
import { handleWhatsApp } from './handler.ts';

const env = {
  SUPABASE_URL: Deno.env.get('SUPABASE_URL') ?? '',
  SUPABASE_SERVICE_ROLE_KEY: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  TWILIO_ACCOUNT_SID: Deno.env.get('TWILIO_ACCOUNT_SID') ?? '',
  TWILIO_AUTH_TOKEN: Deno.env.get('TWILIO_AUTH_TOKEN') ?? '',
  TWILIO_WHATSAPP_FROM: Deno.env.get('TWILIO_WHATSAPP_FROM') ?? '',
  TWILIO_THANKS_CONTENT_SID: Deno.env.get('TWILIO_THANKS_CONTENT_SID') ?? '',
  TWILIO_THANKS_MEMBER_CONTENT_SID: Deno.env.get('TWILIO_THANKS_MEMBER_CONTENT_SID') ?? '',
};

Deno.serve((req) => handleWhatsApp(req, env));
