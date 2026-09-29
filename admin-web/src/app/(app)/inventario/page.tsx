import Link from 'next/link';
import { EventCard } from '@/components/EventCard';
import { ColorDot, ProductImage } from '@/components/ProductImage';
import { inventoryByLocation, listEvents } from '@/lib/f360';
import { pares } from '@/lib/format';

export default async function Inventario({ searchParams }: { searchParams: Promise<{ ubicacion?: string; vista?: string }> }) {
  const sp = await searchParams;
  const vista = sp.vista === 'historial' ? 'historial' : 'ubicacion';
  const all = await inventoryByLocation();
  const selected = all.find((l) => l.id === sp.ubicacion) ?? all[0];
  const events = vista === 'historial' ? await listEvents({ limit: 100, locationId: sp.ubicacion }) : [];
  const tab = (active: boolean) => `rounded-full px-5 py-2.5 text-[15px] transition ${active ? 'bg-ink text-surface' : 'text-ink-2 hover:bg-surface-2'}`;

  return (
    <div>
      <h1 className="font-display text-5xl text-ink">Inventario</h1>
      <div className="mt-6 inline-flex rounded-full border border-line bg-surface p-1">
        <Link href={`/inventario${selected ? `?ubicacion=${selected.id}` : ''}`} className={tab(vista === 'ubicacion')}>Por ubicación</Link>
        <Link href="/inventario?vista=historial" className={tab(vista === 'historial')}>Historial</Link>
      </div>

      {vista === 'ubicacion' ? (
        <>
          <div className="mt-6 flex flex-wrap gap-2">
            {all.map((l) => (
              <Link key={l.id} href={`/inventario?ubicacion=${l.id}`}
                className={`rounded-2xl border px-4 py-3 transition ${l.id === selected?.id ? 'border-ink bg-ink text-surface' : 'border-line bg-surface text-ink hover:border-gold/50'}`}>
                <div className="text-[15px]">{l.name}</div>
                <div className={`tabular text-sm ${l.id === selected?.id ? 'text-surface/70' : 'text-muted'}`}>{pares(l.pairs)}</div>
              </Link>
            ))}
          </div>

          {selected && (
            <section className="mt-8">
              {selected.sales_sync_pending && (
                <p className="mb-4 rounded-2xl bg-gold-soft px-4 py-3 text-sm text-ink-2">
                  Las ventas de esta tienda todavía no se descuentan aquí. No uses estas cantidades para prometer entrega inmediata.
                </p>
              )}
              {selected.products.length === 0 ? (
                <p className="rounded-2xl border border-dashed border-line bg-surface p-8 text-center text-ink-2">No hay pares en {selected.name}.</p>
              ) : (
                <div className="space-y-4">
                  {selected.products.map((p) => (
                    <Link key={p.id} href={`/productos/${p.id}`} className="block rounded-3xl border border-line bg-surface p-4 transition hover:border-gold/40 md:p-5">
                      <div className="flex items-center gap-4">
                        <div className="size-16 shrink-0 overflow-hidden rounded-2xl"><ProductImage path={p.image_path} name={p.name} /></div>
                        <div className="flex-1"><div className="font-display text-3xl leading-none text-ink">{p.name}</div></div>
                        <div className="tabular text-right"><div className="text-2xl font-semibold text-ink">{p.pairs}</div><div className="text-xs text-muted">pares</div></div>
                      </div>
                      {p.colors.map((c) => (
                        <div key={c.name} className="mt-4">
                          <div className="flex items-center gap-2 text-ink-2"><ColorDot hex={c.hex} />{c.name}</div>
                          <div className="mt-2 flex flex-wrap gap-2">
                            {c.sizes.map((s) => (
                              <span key={s.size} className="tabular rounded-xl bg-surface-2 px-3 py-2 text-center">
                                <span className="block text-xs text-muted">Talla {s.size}</span>
                                <span className="text-lg font-semibold text-ink">{s.on_hand}</span>
                              </span>
                            ))}
                          </div>
                        </div>
                      ))}
                    </Link>
                  ))}
                </div>
              )}
            </section>
          )}
        </>
      ) : (
        <section className="mt-8 space-y-3">
          <p className="text-sm text-muted">Cada movimiento queda registrado y no se puede modificar.</p>
          {events.length === 0 ? <p className="rounded-2xl border border-dashed border-line bg-surface p-8 text-center text-ink-2">Todavía no hay movimientos.</p>
            : events.map((e) => <EventCard key={e.id} e={e} />)}
        </section>
      )}
    </div>
  );
}
