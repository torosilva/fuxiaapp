'use server';
import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';

// Who may change it and which file is acceptable are checked in the database (f360_set_app_welcome_photo).
export async function setAppPhotoAction(path: string | null, productId: string | null): Promise<{ ok: true } | { ok: false; error: string }> {
  const supabase = await createClient();
  const { error } = await supabase.rpc('f360_set_app_welcome_photo', { p_path: path, p_product_id: productId });
  if (error) return { ok: false, error: error.code === '42501' ? 'Tu cuenta no tiene permiso para esta acción.' : error.message };
  revalidatePath('/foto-app');
  return { ok: true };
}
