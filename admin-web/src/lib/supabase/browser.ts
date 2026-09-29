'use client';
import { createBrowserClient } from '@supabase/ssr';

// Browser client (same cookie session). Used only for photo uploads to Storage.
export function createClient() {
  return createBrowserClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!);
}
