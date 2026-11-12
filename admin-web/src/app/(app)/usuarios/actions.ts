'use server';
// Configuración → Usuarios (Fase 1, Mario 2026-11-12). Every rule lives in the database (owner only, reason required,
// last owner kept, sensitive permissions untouchable from here); these actions only pass the request through.
import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';

type Result = { ok: true } | { ok: false; error: string };

async function call(fn: string, args: Record<string, unknown>): Promise<Result> {
  const supabase = await createClient();
  const { error } = await supabase.rpc(fn, args);
  if (error) return { ok: false, error: error.message };
  revalidatePath('/usuarios');
  return { ok: true };
}

export async function setProfileAction(input: { userId: string; profile: string; name: string; reason: string }): Promise<Result> {
  return call('f360_admin_set_profile', { p_auth_user_id: input.userId, p_profile: input.profile, p_display_name: input.name, p_reason: input.reason });
}

export async function setModuleAction(input: { userId: string; module: string; on: boolean; reason: string }): Promise<Result> {
  return call('f360_admin_set_module', { p_auth_user_id: input.userId, p_module: input.module, p_on: input.on, p_reason: input.reason });
}

export async function removeUserAction(input: { userId: string; reason: string }): Promise<Result> {
  return call('f360_admin_remove_user', { p_auth_user_id: input.userId, p_reason: input.reason });
}
