'use server';
import { redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';
import { boardAccessState } from '@/lib/board';

// Strategy & Board second factor (Supabase Auth TOTP). Only a Board member who is missing the second factor in this session
// (f360_board_access_state = 'mfa_required', decided in the database) gets past the first line; the database re-checks aal2
// on every Board RPC, so these actions only drive Supabase Auth's own enroll / challenge / verify endpoints.
export type MfaState = { error?: string; factorId?: string; qr?: string; secret?: string };

const CODE = /^\d{6}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export async function startEnroll(): Promise<MfaState> {
  if ((await boardAccessState()) !== 'mfa_required') return { error: 'No disponible.' };
  const supabase = await createClient();
  const { data: list } = await supabase.auth.mfa.listFactors();
  if ((list?.totp?.length ?? 0) > 0) return { error: 'Ya tienes una app configurada: recarga la página y escribe tu código.' };
  // an abandoned, never-verified setup blocks a new one with the same name → remove only UNVERIFIED totp factors
  for (const f of list?.all ?? []) {
    if (f.factor_type === 'totp' && f.status !== 'verified') await supabase.auth.mfa.unenroll({ factorId: f.id });
  }
  const { data, error } = await supabase.auth.mfa.enroll({ factorType: 'totp', friendlyName: 'Fuxia 360 · Strategy & Board', issuer: 'Fuxia 360' });
  if (error || !data) return { error: 'No se pudo iniciar la configuración. Intenta de nuevo.' };
  return { factorId: data.id, qr: data.totp.qr_code, secret: data.totp.secret };
}

export async function verifyCode(prev: MfaState, form: FormData): Promise<MfaState> {
  const factorId = String(form.get('factor_id') ?? '');
  const code = String(form.get('code') ?? '').replace(/\s/g, '');
  if (!UUID.test(factorId)) return { ...prev, error: 'No disponible.' };
  if (!CODE.test(code)) return { ...prev, error: 'Escribe los 6 dígitos.' };
  if ((await boardAccessState()) !== 'mfa_required') return { ...prev, error: 'No disponible.' };
  const supabase = await createClient();
  const { error } = await supabase.auth.mfa.challengeAndVerify({ factorId, code });   // sets the aal2 session cookies
  if (error) return { ...prev, error: 'Código incorrecto o vencido. Escribe el código que se ve ahora en tu app.' };
  redirect('/estrategia');
}
