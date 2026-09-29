// Persistent, non-dismissible marker that this is NOT production. Fixed 48px strip on every page (login included).
export function StagingBanner() {
  return (
    <div role="note" aria-label="Ambiente de pruebas"
      className="fixed inset-x-0 top-0 z-50 flex h-12 flex-col items-center justify-center gap-0.5 bg-[#f0c63b] px-4 text-center text-ink shadow-[0_1px_0_rgba(0,0,0,0.12)] sm:flex-row sm:gap-3">
      <span className="text-[12px] font-bold uppercase tracking-[0.18em] sm:text-[13px]">Fuxia 360 · Ambiente de pruebas</span>
      <span className="text-[11px] leading-tight sm:text-[13px]">Los datos de este ambiente no afectan la operación real.</span>
    </div>
  );
}
