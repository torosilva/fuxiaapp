'use server';
// Fuxia Skills (Fase 2, Mario 2026-11-12). Every rule lives in the database: only Dirección edits, every edit is a new version
// with a note, old versions are never changed. These actions only pass the request through.
import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';

type Result = { ok: true; version?: number } | { ok: false; error: string };

export async function saveSkillAction(input: { key: string; description: string; body: string; note: string }): Promise<Result> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc('f360_skill_save', { p_key: input.key, p_description: input.description, p_body: input.body, p_note: input.note });
  if (error) return { ok: false, error: error.message };
  revalidatePath('/skills');
  revalidatePath(`/skills/${input.key}`);
  return { ok: true, version: (data as { version: number }).version };
}

export async function setSkillStatusAction(input: { key: string; status: string; note: string }): Promise<Result> {
  const supabase = await createClient();
  const { error } = await supabase.rpc('f360_skill_set_status', { p_key: input.key, p_status: input.status, p_note: input.note });
  if (error) return { ok: false, error: error.message };
  revalidatePath('/skills');
  revalidatePath(`/skills/${input.key}`);
  return { ok: true };
}
