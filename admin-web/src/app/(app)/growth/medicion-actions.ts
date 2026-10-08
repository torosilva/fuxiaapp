'use server';
// S-G0 · D3 marketing spend upload (owner only — the database checks the role, validates every row and audits the upload).
import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';
import type { SpendRow } from '@/lib/spend-csv';

type UploadResult = { ok: true; result: 'accepted' | 'duplicate'; rows?: number } | { ok: false; error: string; errors?: { row: number | null; error: string }[] };

export async function uploadSpendAction(platform: string, fileName: string, rows: SpendRow[]): Promise<UploadResult> {
  if (!Array.isArray(rows) || rows.length === 0 || rows.length > 5000) return { ok: false, error: 'El archivo debe tener de 1 a 5,000 filas.' };
  const supabase = await createClient();
  const { data, error } = await supabase.rpc('f360_marketing_spend_upload', { p_platform: platform, p_source: 'csv', p_file_name: fileName.slice(0, 200), p_rows: rows });
  if (error) return { ok: false, error: error.code === '42501' ? 'Solo una dueña puede subir gasto.' : error.message };
  const r = data as { ok: boolean; result: 'accepted' | 'duplicate' | 'rejected'; rows?: number; errors?: { row: number | null; error: string }[] };
  if (!r.ok || r.result === 'rejected') return { ok: false, error: 'El archivo tiene errores; no se cargó nada (el intento quedó registrado).', errors: r.errors };
  revalidatePath('/growth');
  return { ok: true, result: r.result as 'accepted' | 'duplicate', rows: r.rows };
}
