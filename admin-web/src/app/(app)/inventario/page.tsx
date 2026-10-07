import Link from 'next/link';
import { EventCard } from '@/components/EventCard';
import { ColorDot, ProductImage } from '@/components/ProductImage';
import { canWrite, getHome, getMe, inventoryByLocation, listEvents } from '@/lib/f360';
import { eventSentence, fecha, pares } from '@/lib/format';

// Atelier redesign (canvas "Fuxia 360 · Rediseño" → Inventario, Mario 2026-10-06): the network at a glance (one card per
// location + what is on its way), the selected location's models as colour × size matrices, and its latest movements.
const KIND: Record<string, string> = { store: 'TIENDA', warehouse: 'BODEGA', receiving: 'RECEPCIÓN', bazaar: 'BAZAR', workshop: 'TALLER', other: 'OTRA' };
const SIZE_ORDER = (a: string, b: string) => (Number(a) - Number(b)) || a.localeCompare(b);

function cell(n: number) {
  if (n <= 0) return 'text-danger ring-[1.5px] ring-inset ring-danger';
  if (n >= 3) return 'bg-ink text-[#F7E7C4]';
  return 'bg-[#E8C98A] text-ink';
}

export default async function Inventario({ searchParams }: { searchParams: Promise<{ ubicacion?: string; vista?: string }> }) {
  const sp = await searchParams;
  const vista = sp.vista === 'historial' ? 'historial' : 'ubicacion';
  const [me, all, home] = await Promise.all([getMe(), inventoryByLocation(), getHome().catch(() => null)]);
  const selected = all.find((l) => l.id === sp.ubicacion) ?? all[0];
  const [events, recent] = await Promise.all([
    vista === 'historial' ? listEvents({ limit: 100, locationId: sp.ubicacion }) : Promise.resolve([]),
    vista === 'ubicacion' && selected ? listEvents({ limit: 6, locationId: selected.id }).catch(() => []) : Promise.resolve([]),
  ]);
  const total = all.reduce((s, l) => s + l.pairs, 0);
  const tab = (active: boolean) => `rounded-full px-5 py-2.5 text-[15px] transition ${active ? 'bg-ink text-[#F7E7C4]' : 'text-ink-2 hover:bg-surface-2'}`;
  const write = canWrite(me.role);

  return (
    <div className="flex flex-col gap-7">
      <header className="flex flex-wrap items-end justify-between gap-4">
        <div className="flex flex-col gap-2">
          <h1 className="font-display text-[56px] font-semibold leading-none text-ink">Inventario</h1>
          <span className="text-[15px] text-ink-2"><span className="tabular">{pares(total)}</span> en la red · por tienda, en vivo</span>
        </div>
        {write && (
          <div className="flex flex-wrap gap-2.5">
            <Link href="/transferencias" className="flex min-h-12 items-center rounded-full border border-[#d8cdbb] px-5 text-sm font-semibold text-ink">Transferir</Link>
            <Link href="/mover" className="flex min-h-12 items-center rounded-full border border-[#d8cdbb] px-5 text-sm font-semibold text-ink">Mover pares</Link>
            <Link href="/recibir" className="flex min-h-12 items-center rounded-full bg-ink px-6 text-sm font-semibold text-[#F7E7C4]">Recibir mercancía</Link>
          </div>
        )}
      </header>

      <div className="inline-flex self-start rounded-full border border-line bg-surface p-1">
        <Link href={`/inventario${selected ? `?ubicacion=${selected.id}` : ''}`} className={tab(vista === 'ubicacion')}>Por ubicación</Link>
        <Link href="/inventario?vista=historial" className={tab(vista === 'historial')}>Historial</Link>
      </div>

      {vista === 'ubicacion' ? (
        <>
          <section className="grid gap-3.5 [grid-template-columns:repeat(auto-fit,minmax(170px,1fr))]" aria-label="Ubicaciones">
            {all.map((l) => {
              const on = l.id === selected?.id;
              return (
                <Link key={l.id} href={`/inventario?ubicacion=${l.id}`} aria-current={on ? 'page' : undefined}
                  className={`flex min-h-[150px] flex-col gap-2 rounded-3xl p-5 transition ${on ? 'bg-[#14110D] text-[#F7E7C4]' : 'border border-line bg-surface text-ink hover:border-gold/40'}`}>
                  <span className={`text-[11px] font-bold tracking-[0.2em] ${on ? 'text-[#E8C98A]' : 'text-gold-strong'}`}>{KIND[l.type] ?? l.type.toUpperCase()}</span>
                  <span className="font-display tabular text-5xl font-semibold leading-[.9]">{l.pairs}</span>
                  <span className="text-sm font-semibold">{l.name}</span>
                  <span className="text-xs opacity-75">{l.sales_sync_pending ? 'ventas aún sin descontar' : l.type === 'warehouse' ? 'surte la tienda en línea' : 'pares'}</span>
                </Link>
              );
            })}
            {home && home.in_transit_pairs > 0 && (
              <Link href="/transferencias" className="flex min-h-[150px] flex-col gap-2 rounded-3xl border border-line bg-surface p-5 text-ink hover:border-gold/40">
                <span className="text-[11px] font-bold tracking-[0.2em] text-gold-strong">EN CAMINO</span>
                <span className="font-display tabular text-5xl font-semibold leading-[.9]">{home.in_transit_pairs}</span>
                <span className="text-sm font-semibold">Transferencias</span>
                <span className="text-xs opacity-75">entre tiendas</span>
              </Link>
            )}
          </section>

          {selected && (
            <section className="grid gap-5 lg:grid-cols-12">
              <div className="flex flex-col gap-5 lg:col-span-8">
                {selected.sales_sync_pending && (
                  <p className="rounded-2xl bg-gold-soft px-4 py-3 text-sm text-ink-2">
                    Las ventas de esta tienda todavía no se descuentan aquí. No uses estas cantidades para prometer entrega inmediata.
                  </p>
                )}
                {selected.products.length === 0 ? (
                  <p className="rounded-[28px] border border-dashed border-line bg-surface p-8 text-center text-ink-2">No hay pares en {selected.name}.</p>
                ) : selected.products.map((p) => {
                  const sizes = [...new Set(p.colors.flatMap((c) => c.sizes.map((s) => s.size)))].sort(SIZE_ORDER);
                  return (
                    <article key={p.id} className="flex flex-col gap-4 rounded-[28px] border border-line bg-surface p-6">
                      <Link href={`/productos/${p.id}`} className="flex flex-wrap items-center gap-4">
                        <div className="size-[88px] shrink-0 overflow-hidden rounded-[20px]"><ProductImage path={p.image_path} name={p.name} /></div>
                        <div className="flex min-w-[180px] flex-1 flex-col gap-1">
                          <span className="font-display text-[38px] font-semibold leading-none text-ink">{p.name}</span>
                          <span className="text-[13px] text-muted">{p.colors.length} {p.colors.length === 1 ? 'color' : 'colores'}{sizes.length ? ` · tallas ${sizes[0]}–${sizes[sizes.length - 1]}` : ''}</span>
                        </div>
                        <div className="tabular text-right"><div className="font-display text-4xl font-semibold text-ink">{p.pairs}</div><div className="text-xs text-muted">pares en {selected.name}</div></div>
                      </Link>
                      <div className="overflow-x-auto">
                        <div className="grid gap-1.5" style={{ gridTemplateColumns: `190px repeat(${sizes.length}, minmax(52px, 1fr))`, minWidth: 190 + sizes.length * 58 }}>
                          <span className="self-end text-[11px] font-bold tracking-[0.2em] text-muted">COLOR / TALLA</span>
                          {sizes.map((s) => <span key={s} className="text-center text-[13px] font-semibold text-ink-2">{s}</span>)}
                          {p.colors.map((c) => {
                            const q = new Map(c.sizes.map((s) => [s.size, s.on_hand]));
                            return [
                              <span key={c.name} className="flex items-center gap-2.5 text-[13px] text-ink"><ColorDot hex={c.hex} className="size-[18px]" />{c.name}</span>,
                              ...sizes.map((s) => {
                                const n = q.get(s) ?? 0;
                                return <span key={c.name + s} className={`tabular flex h-[42px] items-center justify-center rounded-xl text-sm font-semibold ${cell(n)}`}>{n}</span>;
                              }),
                            ];
                          })}
                        </div>
                      </div>
                    </article>
                  );
                })}
                {selected.products.length > 0 && (
                  <div className="flex flex-wrap gap-4 text-xs text-muted">
                    <span className="inline-flex items-center gap-2"><span className="size-3.5 rounded bg-ink" />3 o más</span>
                    <span className="inline-flex items-center gap-2"><span className="size-3.5 rounded bg-[#E8C98A]" />1–2</span>
                    <span className="inline-flex items-center gap-2"><span className="size-3.5 rounded ring-[1.5px] ring-inset ring-danger" />0</span>
                  </div>
                )}
              </div>

              <aside className="flex h-fit flex-col gap-4 rounded-[28px] bg-[#14110D] p-6 text-[#F7E7C4] lg:col-span-4">
                <span className="text-[11px] font-bold tracking-[0.24em] text-[#E8C98A]">ÚLTIMOS MOVIMIENTOS · {selected.name.toUpperCase()}</span>
                {recent.length === 0 ? <span className="text-sm text-[#A79F92]">Todavía no hay movimientos aquí.</span> : recent.map((e) => (
                  <Link key={e.id} href={`/inventario/movimiento/${e.id}`} className="flex flex-col gap-1 border-b border-dashed border-[#E8C98A]/25 pb-3">
                    <span className="text-sm font-semibold">{eventSentence(e)}</span>
                    <span className="text-xs text-[#A79F92]">{fecha(e.occurred_at)}</span>
                  </Link>
                ))}
                <Link href={`/inventario?vista=historial&ubicacion=${selected.id}`} className="text-[13px] font-semibold text-[#E8C98A]">Ver todo el historial →</Link>
              </aside>
            </section>
          )}
        </>
      ) : (
        <section className="space-y-3">
          <p className="text-sm text-muted">Cada movimiento queda registrado y no se puede modificar.</p>
          {events.length === 0 ? <p className="rounded-2xl border border-dashed border-line bg-surface p-8 text-center text-ink-2">Todavía no hay movimientos.</p>
            : events.map((e) => <EventCard key={e.id} e={e} />)}
        </section>
      )}
    </div>
  );
}
