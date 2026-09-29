'use client';
import { useActionState, useState } from 'react';
import { loginWithPassword, sendCode, verifyCode, type LoginState } from './actions';

const input = 'w-full rounded-xl border border-line bg-surface px-4 py-3.5 text-lg text-ink outline-none transition focus:border-gold';
const primary = 'w-full rounded-xl bg-ink py-4 text-base font-medium text-surface transition hover:bg-ink-2 disabled:opacity-50';

export function LoginForm({ staging, reason }: { staging: boolean; reason?: string }) {
  const [mode, setMode] = useState<'phone' | 'email'>(staging ? 'email' : 'phone');
  const [sendState, sendAction, sending] = useActionState<LoginState, FormData>(sendCode, { step: 'phone' });
  const [codeState, codeAction, verifying] = useActionState<LoginState, FormData>(verifyCode, {});
  const [pwState, pwAction, signingIn] = useActionState<LoginState, FormData>(loginWithPassword, {});
  const onCodeStep = sendState.step === 'code' && codeState.step !== 'phone';
  const error = mode === 'email' ? pwState.error : (onCodeStep ? codeState.error : sendState.error ?? codeState.error);

  return (
    <div className="w-full max-w-sm">
      {reason && !error && <p className="mb-4 rounded-xl bg-gold-soft px-4 py-3 text-sm text-ink-2">{reason}</p>}
      {error && <p role="alert" className="mb-4 rounded-xl bg-danger-soft px-4 py-3 text-sm text-danger">{error}</p>}

      {mode === 'phone' && !onCodeStep && (
        <form action={sendAction} className="space-y-4">
          <label className="block text-sm text-ink-2">Tu número de celular
            <input name="phone" inputMode="tel" autoComplete="tel" placeholder="55 1234 5678" className={`${input} mt-2`} required />
          </label>
          <button disabled={sending} className={primary}>{sending ? 'Enviando…' : 'Enviar código'}</button>
        </form>
      )}
      {mode === 'phone' && onCodeStep && (
        <form action={codeAction} className="space-y-4">
          <input type="hidden" name="phone" value={sendState.phone} />
          <label className="block text-sm text-ink-2">Escribe el código que te llegó
            <input name="code" inputMode="numeric" autoComplete="one-time-code" maxLength={6} placeholder="••••••" className={`${input} mt-2 text-center tracking-[0.5em]`} required />
          </label>
          <button disabled={verifying} className={primary}>{verifying ? 'Entrando…' : 'Entrar'}</button>
        </form>
      )}
      {mode === 'email' && (
        <form action={pwAction} className="space-y-4">
          <label className="block text-sm text-ink-2">Correo
            <input name="email" type="email" autoComplete="username" className={`${input} mt-2`} required />
          </label>
          <label className="block text-sm text-ink-2">Contraseña
            <input name="password" type="password" autoComplete="current-password" className={`${input} mt-2`} required />
          </label>
          <button disabled={signingIn} className={primary}>{signingIn ? 'Entrando…' : 'Entrar'}</button>
        </form>
      )}

      {staging && (
        <button type="button" onClick={() => setMode(mode === 'email' ? 'phone' : 'email')} className="mt-6 w-full text-center text-sm text-muted underline-offset-4 hover:underline">
          {mode === 'email' ? 'Entrar con mi celular' : 'Entrar con correo (ambiente de pruebas)'}
        </button>
      )}
    </div>
  );
}
