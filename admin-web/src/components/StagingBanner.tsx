'use client';
import { useState, useSyncExternalStore } from 'react';

// Persistent, non-dismissible marker that this is NOT production. Fixed 48px strip on every page (login included).
// Mario 2026-10-07: Carolina kept working here after the pase (La Noria, Paula's new photos) because nothing stopped her, so the
// strip now says plainly that nothing captured here reaches the store and links to the real admin, and every new browser session
// opens with a notice that has to be answered on purpose ("Seguir en pruebas" is remembered only for that tab session).
const REAL_ADMIN = 'https://fuxia360.vercel.app';
const SEEN = 'f360-staging-notice';

export function StagingBanner() {
  // read once on the client (the server render never shows the notice, so nothing flashes or mismatches)
  const unseen = useSyncExternalStore(() => () => {}, () => { try { return !sessionStorage.getItem(SEEN); } catch { return true; } }, () => false);
  const [stayed, setStayed] = useState(false);
  const notice = unseen && !stayed;
  const stay = () => { try { sessionStorage.setItem(SEEN, '1'); } catch { /* still closes */ } setStayed(true); };
  return (
    <>
      <div role="note" aria-label="Ambiente de pruebas"
        className="fixed inset-x-0 top-0 z-50 flex h-12 items-center justify-center gap-3 bg-[#f0c63b] px-4 text-center text-ink shadow-[0_1px_0_rgba(0,0,0,0.12)]">
        <span className="text-[11px] leading-tight sm:text-[13px]"><b className="uppercase tracking-[0.12em]">Sistema de pruebas</b>
          <span className="hidden sm:inline"> · Lo que captures aquí no llega a la tienda ni al inventario real.</span></span>
        <a href={REAL_ADMIN} className="shrink-0 rounded-full bg-ink px-3 py-1 text-[11px] font-semibold text-surface sm:text-[12px]">Ir al sistema real</a>
      </div>
      {notice && (
        <div role="dialog" aria-modal="true" aria-labelledby="f360-staging-title" className="fixed inset-0 z-[60] flex items-center justify-center bg-ink/60 px-4">
          <div className="w-full max-w-md rounded-3xl bg-surface p-7 text-ink shadow-xl">
            <p className="text-xs font-bold uppercase tracking-[0.18em] text-[#9a7a12]">Sistema de pruebas</p>
            <h2 id="f360-staging-title" className="font-display mt-2 text-3xl">Este no es el sistema real</h2>
            <p className="mt-3 text-ink-2">Ventas, inventario, fotos y precios que captures aquí <b>no llegan</b> a fuxiaballerinas.com ni a tus tiendas.
              Para trabajar de verdad, entra a <b>fuxia360.vercel.app</b>.</p>
            <div className="mt-6 flex flex-col gap-2 sm:flex-row">
              <a href={REAL_ADMIN} className="rounded-full bg-ink px-5 py-3 text-center font-semibold text-surface">Ir al sistema real</a>
              <button type="button" onClick={stay} className="rounded-full border border-line px-5 py-3 text-ink-2">Seguir en pruebas</button>
            </div>
          </div>
        </div>
      )}
    </>
  );
}
