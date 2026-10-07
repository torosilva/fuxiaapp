import Link from 'next/link';
import { ColorDot, ProductImage } from '@/components/ProductImage';
import { IconPlus, IconSearch } from '@/components/icons';
import { canWrite, getMe, getProduct, getQueueStatus, listCategories, listProducts } from '@/lib/f360';
import type { Readiness } from '@/lib/f360';
import { pares, precio } from '@/lib/format';
import { StoreContentPush } from './StoreContentPush';
import { ConsolidatePanel } from './ConsolidatePanel';
import { PublishAllPanel } from './PublishAllPanel';
import { QueueStatusPanel } from './QueueStatusPanel';
import { publisherAvailable } from '@/lib/env-guard';
import { MERGE_ENABLED, STORE_KEY } from '@/lib/store';

// Atelier redesign (canvas "Fuxia 360 · Rediseño" → Productos, Mario 2026-10-06): the product is the interface — big photos,
// one main action (Nuevo modelo) top right, and what is missing before a model can go to the store, in plain words.
const MISSING: Record<Readiness['missing'][number], string> = { precio: 'precio', categoria: 'categoría', descripcion: 'descripción', color: 'colores', talla: 'tallas', fotos: 'fotos' };

export default async function Productos({ searchParams }: { searchParams: Promise<{ q?: string; categoria?: string }> }) {
  const { q, categoria } = await searchParams;
  const [me, all, categories, queue] = await Promise.all([getMe(), listProducts(q), listCategories(), publisherAvailable() ? getQueueStatus().catch(() => null) : Promise.resolve(null)]);
  const tabs = [...categories.map((c) => ({ key: c.key, name: c.name })), { key: 'sin', name: 'Sin categoría' }];
  const inTab = (key: string | null, tab: string) => (tab === 'sin' ? !key : key === tab);
  const products = categoria ? all.filter((p) => inTab(p.category_key, categoria)) : all;
  const href = (cat?: string) => `/productos?${new URLSearchParams({ ...(q ? { q } : {}), ...(cat ? { categoria: cat } : {}) })}`;
  const storeName = STORE_KEY === 'woo_production' ? 'fuxiaballerinas.com' : 'la tienda de pruebas';
  const home = !categoria && !q;
  // "Por terminar": models Fuxia 360 created that still miss something to be published (what exactly, from their readiness)
  const pending = all.filter((p) => !p.ready && !p.from_store);
  const todo = home ? await Promise.all(pending.slice(0, 12).map(async (p) => {
    const r = await getProduct(p.id).then((x) => x.readiness).catch(() => null);
    return { id: p.id, name: p.name, missing: r ? r.missing.map((m) => MISSING[m] ?? m).join(' · ') : 'revisar' };
  })) : [];
  const inStore = all.filter((p) => p.from_store || p.ready).length;

  return (
    <div className="flex flex-col gap-6">
      <header className="flex flex-wrap items-end justify-between gap-4">
        <div className="flex flex-col gap-2">
          <h1 className="font-display text-[56px] font-semibold leading-none text-ink">Productos</h1>
          <span className="text-[15px] text-ink-2">{all.length} modelos · {inStore} listos o en {storeName}{pending.length ? ` · ${pending.length} por terminar` : ''}</span>
        </div>
        <div className="flex flex-wrap items-center gap-2.5">
          <form role="search" className="flex min-h-12 min-w-[260px] items-center gap-2.5 rounded-full border border-line bg-surface px-[18px]">
            <IconSearch className="size-[18px] text-muted" />
            <label className="sr-only" htmlFor="productos-q">Buscar modelo o color</label>
            <input id="productos-q" name="q" type="search" defaultValue={q} placeholder="Busca un modelo o un color" className="flex-1 bg-transparent text-sm text-ink outline-none" />
            {categoria && <input type="hidden" name="categoria" value={categoria} />}
          </form>
          {canWrite(me.role) && (
            <Link href="/productos/nuevo" className="flex min-h-12 items-center gap-2 rounded-full bg-ink px-6 text-sm font-semibold text-[#F7E7C4] transition hover:bg-ink-2">
              <IconPlus className="size-5" />Nuevo modelo
            </Link>
          )}
        </div>
      </header>

      <nav className="flex flex-wrap gap-2 text-sm" aria-label="Más de productos">
        <Link href="/productos/orden" className="rounded-full border border-line px-4 py-2 text-ink-2 hover:border-gold/40" data-testid="link-store-order">⭐ Orden en la tienda</Link>
        <Link href="/bandeja" className="rounded-full border border-line px-4 py-2 text-ink-2 hover:border-gold/40">Bandeja de clientas</Link>
        <Link href="/sobre-pedido" className="rounded-full border border-line px-4 py-2 text-ink-2 hover:border-gold/40">Pedidos en línea</Link>
      </nav>

      {publisherAvailable() && home && <QueueStatusPanel initial={queue} storeName={storeName} />}
      {me.role === 'owner' && home && publisherAvailable() && <PublishAllPanel storeName={storeName} />}
      {me.role === 'owner' && home && MERGE_ENABLED && <div className="grid gap-4 lg:grid-cols-2"><ConsolidatePanel />{STORE_KEY !== 'woo_production' && <StoreContentPush />}</div>}

      <div role="group" aria-label="Categorías" className="flex flex-wrap gap-2" data-testid="category-tabs">
        <Link href={href()} className={`flex min-h-[42px] items-center rounded-full px-4 text-[13px] font-semibold ${!categoria ? 'bg-ink text-[#F7E7C4]' : 'border border-line bg-surface text-ink'}`}>Todos <span className="tabular ml-1 opacity-60">{all.length}</span></Link>
        {tabs.map((t) => {
          const n = all.filter((p) => inTab(p.category_key, t.key)).length;
          if (!n && t.key === 'sin') return null;
          return <Link key={t.key} href={href(t.key)} data-testid={`cat-${t.key}`} className={`flex min-h-[42px] items-center rounded-full px-4 text-[13px] font-semibold ${categoria === t.key ? 'bg-ink text-[#F7E7C4]' : 'border border-line bg-surface text-ink'}`}>{t.name} <span className="tabular ml-1 opacity-60">{n}</span></Link>;
        })}
      </div>

      {todo.length > 0 && (
        <section className="flex flex-wrap items-center gap-5 rounded-3xl border border-gold-strong/35 bg-surface px-6 py-5" data-testid="por-terminar">
          <div className="flex min-w-[240px] flex-1 flex-col gap-1.5">
            <span className="text-[11px] font-bold tracking-[0.24em] text-gold-strong">POR TERMINAR ANTES DE PUBLICAR</span>
            <span className="text-[15px] leading-relaxed text-ink">A <b>{pending.length} {pending.length === 1 ? 'modelo' : 'modelos'}</b> les falta algo para salir a la tienda.</span>
          </div>
          <div className="flex flex-[2_1_420px] flex-wrap gap-2">
            {todo.map((t) => (
              <Link key={t.id} href={`/productos/${t.id}`} className="flex min-h-11 flex-col gap-0.5 rounded-2xl bg-gold-soft px-3.5 py-2.5 text-ink">
                <b className="text-[13px]">{t.name}</b><span className="text-xs text-gold-strong">le falta {t.missing}</span>
              </Link>
            ))}
            {pending.length > todo.length && <span className="self-center text-xs text-muted">y {pending.length - todo.length} más</span>}
          </div>
        </section>
      )}

      {products.length === 0 ? (
        <div className="rounded-3xl border border-dashed border-line bg-surface p-10 text-center">
          <p className="text-lg text-ink-2">{q ? `No encontramos “${q}”.` : categoria ? 'No hay productos en esta categoría.' : 'Todavía no hay productos.'}</p>
          {canWrite(me.role) && !q && <Link href="/productos/nuevo" className="mt-4 inline-block rounded-full bg-ink px-5 py-3 text-[#F7E7C4]">Crear el primero</Link>}
        </div>
      ) : (
        <section className="grid gap-5 [grid-template-columns:repeat(auto-fill,minmax(250px,1fr))]">
          {products.map((p) => {
            const state = p.from_store ? 'Viene de la tienda' : p.ready ? 'Listo' : 'Por terminar';
            return (
              <Link key={p.id} href={`/productos/${p.id}`} className="group flex flex-col overflow-hidden rounded-[26px] border border-line bg-surface text-ink transition hover:border-gold/40">
                <div className="relative h-[260px] overflow-hidden bg-surface-2">
                  <ProductImage path={p.image_path} name={p.name} className="transition duration-500 group-hover:scale-[1.03]" />
                  <span className={`absolute left-3.5 top-3.5 rounded-full px-3 py-1.5 text-xs font-semibold ${state === 'Por terminar' ? 'bg-gold-soft text-gold-strong' : 'bg-surface/90 text-success'}`}>{state}</span>
                </div>
                <div className="flex flex-col gap-2.5 px-5 pb-5 pt-[18px]">
                  <div className="flex items-baseline justify-between gap-2.5">
                    <span className="font-display text-[28px] font-semibold leading-none">{p.name}</span>
                    {p.regular_price != null && <span className="tabular text-sm font-semibold">{precio(p.sale_price ?? p.regular_price)}</span>}
                  </div>
                  <div className="flex items-center gap-1.5">
                    {p.colors.slice(0, 6).map((c) => <ColorDot key={c.name} hex={c.hex} className="size-4" />)}
                    <span className="ml-1 text-xs text-muted">{p.colors.length} {p.colors.length === 1 ? 'color' : 'colores'}</span>
                  </div>
                  <div className="flex justify-between border-t border-dashed border-[#e0d5c4] pt-2.5 text-xs text-muted">
                    <span>{p.category ?? 'Sin categoría'}</span><b className="tabular text-ink">{pares(p.pairs)}</b>
                  </div>
                </div>
              </Link>
            );
          })}
        </section>
      )}
    </div>
  );
}
