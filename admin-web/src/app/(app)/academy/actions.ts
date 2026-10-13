'use server';
// Fuxia Academy — server actions. They only relay to the f360_academy_* RPCs with the user's own session: the database decides who
// may do what (learner / editor / approver with aal2) and grades answers. Nothing here trusts a value sent by the browser.
import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';

type R = { ok: boolean; error?: string; [k: string]: unknown };
async function call(fn: string, args: Record<string, unknown>): Promise<R> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc(fn, args);
  if (error) return { ok: false, error: 'No se pudo guardar.' };
  return (data ?? { ok: false, error: 'No disponible.' }) as R;
}
// Opening the lesson enrolls the learner in its course version (needed before saving progress).
export async function openLesson(lesson: string) {
  return call('f360_academy_lesson', { p_lesson: lesson });
}
export async function saveProgress(lesson: string, card: number, done: boolean) {
  return call('f360_academy_progress_save', { p_lesson: lesson, p_card: card, p_done: done });
}
export async function answer(item: string, value: Record<string, unknown>) {
  return call('f360_academy_answer', { p_item: item, p_answer: value });
}
export async function saveLesson(version: string, lesson: string, title: string, minutes: number, blocks: unknown[], codes: string[]) {
  const r = await call('f360_academy_lesson_save', { p_lesson: lesson, p_title: title, p_minutes: minutes, p_blocks: blocks, p_product_codes: codes });
  revalidatePath(`/academy/admin/version/${version}`);
  return r;
}
export async function saveItem(version: string, item: string, fields: Record<string, unknown>) {
  const r = await call('f360_academy_item_save', { p_item: item, p_fields: fields });
  revalidatePath(`/academy/admin/version/${version}`);
  return r;
}
export async function comment(version: string, lessonKey: string | null, itemKey: string | null, block: number | null, body: string) {
  const r = await call('f360_academy_comment', { p_version: version, p_lesson_key: lessonKey, p_item_key: itemKey, p_block: block, p_body: body });
  revalidatePath(`/academy/admin/version/${version}`);
  return r;
}
export async function submit(version: string, reason: string) {
  const r = await call('f360_academy_submit', { p_version: version, p_reason: reason });
  revalidatePath(`/academy/admin/version/${version}`); revalidatePath('/academy/admin');
  return r;
}
export async function decide(version: string, approve: boolean, reason: string) {
  const r = await call('f360_academy_decide', { p_version: version, p_approve: approve, p_reason: reason });
  revalidatePath(`/academy/admin/version/${version}`); revalidatePath('/academy/admin');
  return r;
}
export async function newDraft(course: string) {
  const r = await call('f360_academy_new_draft', { p_course: course });
  revalidatePath('/academy/admin');
  return r;
}
