// Fuxia 360 · S0.2 authenticated seller shift (client side).
// The SERVER derives identity, role, authorized locations and the shift location. This module only carries the opaque
// shift token, IN MEMORY (never persisted): closing the app ends the shift on this phone.
// Enabled only when EXPO_PUBLIC_F360_SELLER_SESSION=1 (staging/dev builds pointing at a database that has Fuxia 360).
// Production builds keep the legacy flow until the rollout is approved.
import { supabase } from '@/lib/supabase';

export const F360_SELLER_SESSION = process.env.EXPO_PUBLIC_F360_SELLER_SESSION === '1';

export type ShiftLocation = { id: string; name: string; type: string; sellable: boolean; ledger_authority: 'legacy' | 'f360'; legacy_channel_id?: string | null };
export type Shift = { token: string; person: string; location: ShiftLocation; expiresAt: string };

let current: Shift | null = null;
export const currentShift = () => current;

export async function myF360Role(): Promise<string | null> {
  const { data, error } = await supabase.rpc('f360_me');
  return error ? null : ((data as { role?: string })?.role ?? null);
}

/** Only the locations the server says this person may start a shift at (sellers: their assignments). */
export async function myShiftLocations(): Promise<ShiftLocation[]> {
  const { data, error } = await supabase.rpc('f360_my_locations');
  if (error) throw new Error(error.message);
  return ((data as ShiftLocation[]) ?? []).filter((l) => l.sellable);
}

export async function startShift(locationId: string, pin: string): Promise<{ ok: true; shift: Shift } | { ok: false; error: string; locked?: boolean }> {
  const { data, error } = await supabase.rpc('f360_start_seller_shift', { p_location_id: locationId, p_pin: pin });
  if (error) return { ok: false, error: error.message };
  const r = data as { ok: boolean; error?: string; locked?: boolean; token?: string; person?: string; location?: ShiftLocation; expires_at?: string };
  if (!r.ok || !r.token || !r.location) return { ok: false, error: r.error ?? 'No se pudo iniciar turno.', locked: r.locked };
  current = { token: r.token, person: r.person ?? '', location: r.location, expiresAt: r.expires_at ?? '' };
  return { ok: true, shift: current };
}

/** Heartbeat / guard before any operation. The location is the SHIFT's, never chosen by the client. */
export async function checkShift(): Promise<{ ok: boolean; error?: string }> {
  if (!current) return { ok: false, error: 'No hay turno activo.' };
  const { data, error } = await supabase.rpc('f360_seller_session', { p_token: current.token, p_location_claim: current.location.id });
  const r = (data ?? {}) as { ok?: boolean; error?: string };
  if (error || !r.ok) { current = null; return { ok: false, error: error?.message ?? r.error }; }
  return { ok: true };
}

export async function endShift() {
  if (!current) return;
  const token = current.token;
  current = null;
  await supabase.rpc('f360_end_seller_shift', { p_token: token });
}
