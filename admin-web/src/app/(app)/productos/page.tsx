import Link from 'next/link';
import { ColorDot, ProductImage } from '@/components/ProductImage';
import { IconPlus, IconSearch } from '@/components/icons';
import { canWrite, getMe, listCategories, listProducts } from '@/lib/f360';
import { pares, precio } from '@/lib/format';
import { StoreContentPush } from './StoreContentPush';
import { ConsolidatePanel } from './ConsolidatePanel';
import { PublishAllPanel } from './PublishAllPanel';
import { publisherAvailable } from '@/lib/env-guard';
import { MERGE_ENABLED, STORE_KEY } from '@/lib/store';

export default async function Productos({ searchParams }: { searchParams: Promise<{ q?: string; categoria?: string }> }) {
  const { q, categoria } = await searchParams;
  const [me, all, categories] = await Promise.all([getMe(), listProducts(q), listCategories()]);
  const tabs = [...categories.map((c) => ({ key: c.key, name: c.name })), { key: 'sin', name: 'Sin categoría' }];
  const inTab = (key: string | null, tab: string) => (tab === 'sin' ? !key : key === tab);
  const products = categoria ? all.filter((p) => inTab(p.category_key, categoria)) : all;
  const href = (cat?: string) => `/productos?${new URLSearchParams({ ...(q ? { q } : {}), ...(cat ? { categoria: cat } : {}) })}`;
  return (
    <div>
      <div className="flex flex-wrap items-end justify-between gap-4">
        <h1 className="font-display text-5xl text-ink">Productos</h1>
        <Link href="/bandeja" className="ml-auto rounded-full px-5 py-3 text-ink-2 ring-1 ring-line">Bandeja de clientas</Link>
        <Link href="/sobre-pedido" className="rounded-full px-5 py-3 text-ink-2 ring-1 ring-line">Pedidos en línea</Link>
        {canWrite(me.role) && (
          <Link href="/productos/nuevo" className="flex items-center gap-2 rounded-full bg-ink px-5 py-3 text-surface transition hover:bg-ink-2">
            <IconPlus className="size-5" />Nuevo producto
          </Link>
        )}
      </div>
      {me.role === 'owner' && !categoria && !q && publisherAvailable() && <div className="mt-6"><PublishAllPanel storeName={STORE_KEY === 'woo_production' ? 'fuxiaballerinas.com' : 'la tienda de pruebas'} /></div>}
      {me.role === 'owner' && !categoria && !q && MERGE_ENABLED && <div className="mt-6 grid gap-4 lg:grid-cols-2"><ConsolidatePanel /><StoreContentPush /></div>}
      <form className="relative mt-6 max-w-md" role="search">
        <IconSearch className="absolute left-4 top-1/2 size-5 -translate-y-1/2 text-muted" />
        <input name="q" defaultValue={q} placeholder="Busca por nombre o color" className="w-full rounded-full border border-line bg-surface py-3.5 pl-12 pr-4 text-base outline-none focus:border-gold" />
        {categoria && <input type="hidden" name="categoria" value={categoria} />}
      </form>
      <nav className="mt-4 flex flex-wrap gap-2" data-testid="category-tabs">
        <Link href={href()} className={`rounded-full px-4 py-2 text-sm ${!categoria ? 'bg-ink text-surface' : 'bg-surface text-ink-2 ring-1 ring-line'}`}>Todos <span className="tabular opacity-70">{all.length}</span></Link>
        {tabs.map((t) => {
          const n = all.filter((p) => inTab(p.category_key, t.key)).length;
          if (!n && t.key === 'sin') return null;
          return <Link key={t.key} href={href(t.key)} data-testid={`cat-${t.key}`} className={`rounded-full px-4 py-2 text-sm ${categoria === t.key ? 'bg-ink text-surface' : 'bg-surface text-ink-2 ring-1 ring-line'}`}>{t.name} <span className="tabular opacity-70">{n}</span></Link>;
        })}
      </nav>

      {products.length === 0 ? (
        <div className="mt-10 rounded-3xl border border-dashed border-line bg-surface p-10 text-center">
          <p className="text-lg text-ink-2">{q ? `No encontramos “${q}”.` : categoria ? 'No hay productos en esta categoría.' : 'Todavía no hay productos.'}</p>
          {canWrite(me.role) && !q && <Link href="/productos/nuevo" className="mt-4 inline-block rounded-full bg-ink px-5 py-3 text-surface">Crear el primero</Link>}
        </div>
      ) : (
        <div className="mt-8 grid grid-cols-2 gap-4 md:grid-cols-3 xl:grid-cols-4">
          {products.map((p) => (
            <Link key={p.id} href={`/productos/${p.id}`} className="group overflow-hidden rounded-2xl border border-line bg-surface transition hover:border-gold/40">
              <div className="relative aspect-[4/3] overflow-hidden">
                <ProductImage path={p.image_path} name={p.name} className="transition duration-500 group-hover:scale-[1.03]" />
                <span className={`absolute left-3 top-3 rounded-full px-2.5 py-0.5 text-xs font-medium ${p.from_store || p.ready ? 'bg-success-soft text-success' : 'bg-gold-soft text-ink-2'}`}>{p.from_store ? 'En la tienda' : p.ready ? 'Listo' : 'Borrador'}</span>
              </div>
              <div className="p-4">
                <div className="font-display text-2xl leading-tight text-ink">{p.name}</div>
                {p.regular_price != null && <div className="tabular text-sm text-ink-2">{precio(p.sale_price ?? p.regular_price)}</div>}
                <div className="mt-2 flex items-center justify-between">
                  <div className="flex -space-x-1">{p.colors.map((c) => <ColorDot key={c.name} hex={c.hex} className="size-4 ring-2 ring-surface" />)}</div>
                  <div className="tabular text-sm text-ink-2">{pares(p.pairs)}</div>
                </div>
              </div>
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}
