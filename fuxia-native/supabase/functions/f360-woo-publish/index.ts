// Supabase Edge Function entry (Deno). NOT deployed in P2.2: there is no real Woo test store yet (DW2).
// When deployed (staging first), secrets: WOO_TARGET_KEY, WOO_BASE_URL, WOO_USER, WOO_SECRET (a dedicated Woo REST
// key for that ONE store). SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY are provided by the platform.
import { handle } from './handler.ts';

const env = {
  SUPABASE_URL: Deno.env.get('SUPABASE_URL') ?? '',
  SUPABASE_ANON_KEY: Deno.env.get('SUPABASE_ANON_KEY') ?? '',
  SUPABASE_SERVICE_ROLE_KEY: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  WOO_TARGET_KEY: Deno.env.get('WOO_TARGET_KEY') ?? '',
  WOO_BASE_URL: Deno.env.get('WOO_BASE_URL') ?? '',
  WOO_USER: Deno.env.get('WOO_USER') ?? '',
  WOO_SECRET: Deno.env.get('WOO_SECRET') ?? '',
};

// Queue mode keeps working after responding (EdgeRuntime.waitUntil) and chains itself job by job.
declare const EdgeRuntime: { waitUntil(p: Promise<unknown>): void };
Deno.serve((req) => handle(req, env, { waitUntil: (p) => EdgeRuntime.waitUntil(p) }));
