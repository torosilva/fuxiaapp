'use server';
import { redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';

export type LoginState = { error?: string; step?: 'phone' | 'code'; phone?: string };

const FUNCTIONS_URL = () => `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/whatsapp-otp`;
const otpHeaders = () => ({ 'Content-Type': 'application/json', Authorization: `Bearer ${process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY}`, apikey: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY! });

function normalizePhone(raw: string): string | null {
  const digits = raw.replace(/\D/g, '');
  if (raw.trim().startsWith('+') && digits.length >= 10) return `+${digits}`;
  if (digits.length === 10) return `+52${digits}`;
  if (digits.length === 12 && digits.startsWith('52')) return `+${digits}`;
  return null;
}

// After any login: only accounts with a Fuxia 360 role may stay signed in.
async function requireF360Role(): Promise<string | null> {
  const supabase = await createClient();
  const { error } = await supabase.rpc('f360_me');
  if (error) {
    await supabase.auth.signOut();
    return error.code === '42501' ? 'Esta cuenta no tiene acceso a Fuxia 360. Pídele acceso a Mario.' : 'No pudimos verificar tu acceso. Intenta de nuevo.';
  }
  return null;
}

export async function sendCode(_: LoginState, form: FormData): Promise<LoginState> {
  const phone = normalizePhone(String(form.get('phone') ?? ''));
  if (!phone) return { step: 'phone', error: 'Escribe tu número a 10 dígitos.' };
  const res = await fetch(FUNCTIONS_URL(), { method: 'POST', headers: otpHeaders(), body: JSON.stringify({ action: 'send', phone }) });
  if (!res.ok) {
    return { step: 'phone', error: process.env.NEXT_PUBLIC_F360_ENV === 'staging' ? 'En el ambiente de pruebas no se envían códigos. Usa “Entrar con correo”.' : 'No pudimos enviar el código. Intenta de nuevo.' };
  }
  return { step: 'code', phone };
}

export async function verifyCode(_: LoginState, form: FormData): Promise<LoginState> {
  const phone = String(form.get('phone') ?? '');
  const code = String(form.get('code') ?? '').replace(/\D/g, '');
  if (code.length !== 6) return { step: 'code', phone, error: 'El código tiene 6 dígitos.' };
  const res = await fetch(FUNCTIONS_URL(), { method: 'POST', headers: otpHeaders(), body: JSON.stringify({ action: 'verify', phone, code }) });
  const body = await res.json().catch(() => ({}));
  if (!res.ok || !body?.session?.access_token) return { step: 'code', phone, error: 'Código incorrecto o vencido.' };
  const supabase = await createClient();
  const { error } = await supabase.auth.setSession({ access_token: body.session.access_token, refresh_token: body.session.refresh_token });
  if (error) return { step: 'code', phone, error: 'No pudimos iniciar tu sesión.' };
  const denied = await requireF360Role();
  if (denied) return { step: 'phone', error: denied };
  redirect('/');
}

// Staging only: demo owner accounts (no SMS provider in staging).
export async function loginWithPassword(_: LoginState, form: FormData): Promise<LoginState> {
  if (process.env.NEXT_PUBLIC_F360_ENV !== 'staging') return { error: 'No disponible.' };
  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithPassword({ email: String(form.get('email') ?? '').trim(), password: String(form.get('password') ?? '') });
  if (error) return { error: 'Correo o contraseña incorrectos.' };
  const denied = await requireF360Role();
  if (denied) return { error: denied };
  redirect('/');
}

export async function signOut() {
  const supabase = await createClient();
  await supabase.auth.signOut();
  redirect('/login');
}
