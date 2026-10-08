import { createClient } from '@/lib/supabase/server';
import { MfaChallenge, MfaEnroll } from './MfaForms';

// Second factor for Strategy & Board only (Supabase Auth TOTP). Rendered by the layout ONLY when the database says the caller
// is a Board member whose session lacks aal2 (f360_board_access_state = 'mfa_required'); the rest of Fuxia 360 never asks.
export async function BoardMfa() {
  const supabase = await createClient();
  const { data } = await supabase.auth.mfa.listFactors();
  const verified = data?.totp?.[0] ?? null;
  return (
    <div className="mx-auto flex w-full max-w-md flex-col gap-5 rounded-2xl border border-line bg-surface p-6">
      <div>
        <p className="text-xs uppercase tracking-[0.2em] text-muted">Strategy &amp; Board 🔒</p>
        <h1 className="font-display mt-1 text-3xl">Verificación en dos pasos</h1>
        <p className="mt-2 text-sm text-ink-2">
          {verified
            ? 'Escribe el código de 6 dígitos de tu app de autenticación (Google Authenticator, 1Password, Authy…).'
            : 'Para entrar a Strategy & Board necesitas una app de autenticación en tu celular. Se configura una sola vez.'}
        </p>
      </div>
      {verified ? <MfaChallenge factorId={verified.id} /> : <MfaEnroll />}
      <p className="text-xs text-muted">
        Solo Strategy &amp; Board pide este código; el resto de Fuxia 360 funciona igual. ¿Perdiste tu celular? Pide a Mario (dueño del
        proyecto en Supabase) que borre tu verificación; después vuelves a configurarla aquí.
      </p>
    </div>
  );
}
