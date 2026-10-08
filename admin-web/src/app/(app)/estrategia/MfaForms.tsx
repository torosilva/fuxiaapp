'use client';
import { useActionState, useState, useTransition } from 'react';
import { startEnroll, verifyCode, type MfaState } from './mfa-actions';

const input = 'w-full rounded-xl border border-line bg-surface px-4 py-3.5 text-center text-2xl tracking-[0.5em] text-ink outline-none transition focus:border-gold';
const primary = 'w-full rounded-xl bg-ink py-4 text-base font-medium text-surface transition hover:bg-ink-2 disabled:opacity-50';

function CodeForm({ factorId, state, action, pending, label }: { factorId: string; state: MfaState; action: (f: FormData) => void; pending: boolean; label: string }) {
  return (
    <form action={action} className="space-y-4">
      {state.error && <p role="alert" className="rounded-xl bg-danger-soft px-4 py-3 text-sm text-danger">{state.error}</p>}
      <input type="hidden" name="factor_id" value={factorId} />
      <label className="block text-sm text-ink-2">Código de 6 dígitos
        <input name="code" inputMode="numeric" autoComplete="one-time-code" maxLength={7} placeholder="••••••" className={`${input} mt-2`} required autoFocus />
      </label>
      <button disabled={pending} className={primary}>{pending ? 'Verificando…' : label}</button>
    </form>
  );
}

export function MfaChallenge({ factorId }: { factorId: string }) {
  const [state, action, pending] = useActionState<MfaState, FormData>(verifyCode, {});
  return <CodeForm factorId={factorId} state={state} action={action} pending={pending} label="Entrar" />;
}

export function MfaEnroll() {
  const [setup, setSetup] = useState<MfaState>({});
  const [starting, start] = useTransition();
  const [state, action, pending] = useActionState<MfaState, FormData>(verifyCode, {});
  if (!setup.factorId) {
    return (
      <div className="space-y-4">
        {setup.error && <p role="alert" className="rounded-xl bg-danger-soft px-4 py-3 text-sm text-danger">{setup.error}</p>}
        <ol className="list-decimal space-y-1 pl-5 text-sm text-ink-2">
          <li>Instala una app de autenticación (Google Authenticator, Microsoft Authenticator, 1Password o Authy).</li>
          <li>Toca «Configurar» y escanea el código con esa app.</li>
          <li>Escribe el código de 6 dígitos que te muestre.</li>
        </ol>
        <button type="button" disabled={starting} className={primary} onClick={() => start(async () => setSetup(await startEnroll()))}>
          {starting ? 'Preparando…' : 'Configurar'}
        </button>
      </div>
    );
  }
  return (
    <div className="space-y-4">
      {/* eslint-disable-next-line @next/next/no-img-element -- Supabase returns the QR as an SVG data URL */}
      <img src={setup.qr} alt="Código QR para tu app de autenticación" className="mx-auto h-48 w-48 rounded-xl bg-white p-2" />
      <p className="text-center text-xs text-muted">¿No puedes escanear? Escribe esta clave en la app:<br /><span className="font-mono text-ink-2 break-all">{setup.secret}</span></p>
      <p className="rounded-xl bg-gold-soft px-4 py-3 text-xs text-ink-2">
        Recomendado: escanea el mismo código también en un segundo dispositivo o en tu gestor de contraseñas. Así, si pierdes el
        celular, sigues teniendo tu código.
      </p>
      <CodeForm factorId={setup.factorId} state={state} action={action} pending={pending} label="Activar y entrar" />
    </div>
  );
}
