// Supabase Edge Function entry (Deno). --no-verify-jwt: the caller is HiloLabs' backend, Bearer F360_HILO_SECRET.
import { handleIntake } from './handler.ts';
Deno.serve((req) => handleIntake(req, { SUPABASE_URL: Deno.env.get('SUPABASE_URL') ?? '', SUPABASE_SERVICE_ROLE_KEY: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '', F360_HILO_SECRET: Deno.env.get('F360_HILO_SECRET') ?? '' }));
