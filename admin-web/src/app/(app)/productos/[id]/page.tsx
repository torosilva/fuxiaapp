import Link from 'next/link';
import { EventCard } from '@/components/EventCard';
import { ColorDot, ProductImage } from '@/components/ProductImage';
import { IconBack, IconCheck, IconDown } from '@/components/icons';
import { canWrite, getArchiveState, getColorRemoveState, getLegacySources, getMe, getProduct, getProductPrices, getPublication, listCategories, listEvents, listLocations } from '@/lib/f360';
import { MISSING_LABEL, pares, precio } from '@/lib/format';
import { ColorPhotos } from './ColorPhotos';
import { ProductInfoForm } from './ProductInfoForm';
import { PublishPanel } from './PublishPanel';
import { PricesPanel } from './PricesPanel';
import { StoreOrigin } from './StoreImport';
import { ArchivePanel } from './ArchivePanel';
import { MakeToOrderPanel } from './MakeToOrderPanel';
import { AdjustPanel } from './AdjustPanel';
import { publisherAvailable } from '@/lib/env-guard';

const MISSING_ANCHOR: Record<string, string> = { precio: '#info', categoria: '#info', descripcion: '#info', fotos: '#fotos', color: '#fotos', talla: '#fotos' };

export default async function ProductoDetalle({ params, searchParams }: { params: Promise<{ id: string }>; searchParams: Promise<{ color?: string; creado?: string }> }) {
  const [{ id }, sp] = await Promise.all([params, searchParams]);
  const [me, product, locations, events, categories, pub, prices] = await Promise.all([getMe(), getProduct(id), listLocations(), listEvents({ productId: id, limit: 20 }), listCategories(), getPublication(id), getProductPrices(id)]);
  const edit = canWrite(me.role);
  const sources = edit ? await getLegacySources(id) : [];   // adopted from the current store (Track D)
  const legacy = sources.length > 0;
  const archive = await getArchiveState(id);
  const color = product.colors.find((c) => c.id === sp.color) ?? product.colors[0];
  const removeBlockers = edit && color ? (await getColorRemoveState(color.id)).blockers : [];
  const qty = (locId: string, size: string) => color?.balances.find((b) => b.location_id === locId && b.size === size)?.on_hand ?? 0;
  const colorTotal = color?.balances.reduce((a, b) => a + b.on_hand, 0) ?? 0;
  const ready = product.readiness.ready;

  return (
    <div>
      <Link href="/productos" className="inline-flex items-center gap-1 text-sm text-muted hover:text-ink"><IconBack className="size-4" />Productos</Link>
      {archive.status === 'archived' && (
        <div className="mt-4 rounded-2xl bg-surface-2 px-5 py-4 text-ink-2" data-testid="archived-banner">Este producto está <b>archivado</b>: no aparece en las listas. Puedes reactivarlo abajo.</div>
      )}

      {sp.creado && edit && (
        <div className="mt-4 rounded-2xl bg-success-soft px-5 py-4 text-success"><p className="flex items-center gap-2"><IconCheck />Producto creado. Ahora agrega las fotos de cada color y la información para la tienda.</p></div>
      )}

      <div className="mt-6 grid gap-8 lg:grid-cols-[minmax(0,360px)_1fr]">
        <div className="aspect-square overflow-hidden rounded-3xl border border-line"><ProductImage path={color?.image_path ?? product.image_path} name={product.name} /></div>
        <div>
          <div className="flex flex-wrap items-center gap-2">
            {product.category && <span className="text-xs uppercase tracking-[0.2em] text-muted">{product.category}</span>}
            <span className={`rounded-full px-3 py-1 text-xs font-medium ${legacy || ready ? 'bg-success-soft text-success' : 'bg-gold-soft text-ink-2'}`}>{legacy ? 'En la tienda' : ready ? 'Listo para publicar' : 'Borrador'}</span>
          </div>
          <h1 className="font-display mt-2 break-words text-5xl text-ink md:text-6xl">{product.name}</h1>
          <p className="tabular mt-2 text-lg text-ink-2">
            {product.regular_price != null && <span className="mr-3 font-medium text-ink">{precio(product.sale_price ?? product.regular_price)}</span>}
            {pares(product.pairs)} en inventario
          </p>
          <div className="mt-4 flex flex-wrap gap-1.5">
            {product.colors.map((c) => <span key={c.id} className="flex items-center gap-1.5 rounded-full bg-surface-2 px-3 py-1 text-sm text-ink-2"><ColorDot hex={c.hex} className="size-3" />{c.name}</span>)}
          </div>

          {legacy ? (
            <StoreOrigin productId={product.id} sources={sources} canEdit={edit} owner={me.role === 'owner'}
              missing={product.readiness.missing.filter((m) => m === 'precio' || m === 'descripcion' || m === 'fotos').map((m) => (MISSING_LABEL[m] ?? m).toLowerCase())} />
          ) : !ready ? (
            <div className="mt-6 rounded-2xl border border-line bg-surface p-5">
              <p className="text-ink">Para la tienda en línea falta:</p>
              <ul className="mt-3 space-y-2">
                {product.readiness.missing.map((m) => (
                  <li key={m}><a href={MISSING_ANCHOR[m] ?? '#'} className="flex items-center gap-2 text-ink-2 hover:text-ink"><span className="size-2 rounded-full bg-gold" />{MISSING_LABEL[m] ?? m}</a></li>
                ))}
              </ul>
            </div>
          ) : (
            <div className="mt-6 rounded-2xl border border-success/30 bg-success-soft p-5 text-success">
              <p className="flex items-center gap-2"><IconCheck />Todo listo para la tienda en línea.</p>
            </div>
          )}

          <div className="mt-6 flex flex-wrap gap-3">
            <Link href={`/productos/${product.id}/tienda`} className="inline-flex items-center gap-2 rounded-full border border-ink px-6 py-3.5 text-ink transition hover:bg-ink hover:text-surface">Así se verá en la tienda</Link>
            {edit && color && (
              <Link href={`/recibir?producto=${product.id}&color=${color.id}`} className="inline-flex items-center gap-2 rounded-full bg-ink px-6 py-3.5 text-surface transition hover:bg-ink-2">
                <IconDown className="size-5" />Recibir mercancía
              </Link>
            )}
          </div>
        </div>
      </div>

      {!legacy && <PublishPanel productId={product.id} pub={pub} isOwner={me.role === 'owner'} publisherReady={publisherAvailable()} />}

      {color && <ColorPhotos product={product} color={color} canEdit={edit} removeBlockers={removeBlockers} />}
      <ProductInfoForm key={`${product.regular_price}-${product.category_key}-${product.description?.length ?? 0}`} product={product} categories={categories} canEdit={edit} />
      <PricesPanel key={prices.map((p) => `${p.code}:${p.amount}`).join('|')} productId={product.id} prices={prices} canEdit={edit} />

      {color && (
        <section className="mt-12">
          <h2 className="font-display text-3xl text-ink">{color.name}: tallas por ubicación</h2>
          <p className="mt-1 text-sm text-muted">{pares(colorTotal)} de este color</p>
          <div className="mt-4 overflow-x-auto rounded-2xl border border-line bg-surface">
            <table className="tabular w-full min-w-max text-center">
              <thead>
                <tr className="border-b border-line text-sm text-muted">
                  <th className="sticky left-0 bg-surface px-4 py-3 text-left font-normal">Ubicación</th>
                  {product.sizes.map((s) => <th key={s} className="px-3 py-3 font-normal">{s}</th>)}
                  <th className="px-4 py-3 font-medium text-ink-2">Total</th>
                </tr>
              </thead>
              <tbody>
                {locations.map((l) => {
                  const total = product.sizes.reduce((a, s) => a + qty(l.id, s), 0);
                  return (
                    <tr key={l.id} className="border-b border-line last:border-0">
                      <td className="sticky left-0 bg-surface px-4 py-4 text-left">
                        <div className="text-ink">{l.name}</div>
                        {l.sales_sync_pending && <div className="text-xs text-muted">Ventas de tienda aún no descontadas</div>}
                      </td>
                      {product.sizes.map((s) => { const n = qty(l.id, s); return <td key={s} className={`px-3 py-4 text-lg ${n ? 'font-medium text-ink' : 'text-line'}`}>{n || '·'}</td>; })}
                      <td className="px-4 py-4 text-lg font-semibold text-ink">{total}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
          {me.role === 'owner' && <AdjustPanel key={color.id} productId={product.id} color={color} sizes={product.sizes} locations={locations} />}
        </section>
      )}

      <details className="mt-12 rounded-2xl border border-line bg-surface p-5">
        <summary className="cursor-pointer text-ink-2">Códigos para la tienda en línea</summary>
        <p className="mt-3 text-sm text-muted">{product.codes_locked ? 'Fijos: ya se usaron para publicar y no cambian aunque cambies el nombre.' : 'Se generan solos. Quedan fijos cuando el producto se publica, aunque cambies el nombre.'}</p>
        <p className="mt-3 text-sm text-ink-2">Producto: <span className="font-mono text-ink">{product.code}</span></p>
        {product.colors.map((c) => (
          <div key={c.id} className="mt-3">
            <p className="flex items-center gap-2 text-sm text-ink-2"><ColorDot hex={c.hex} className="size-3" />{c.name}: <span className="font-mono text-ink">{c.code}</span></p>
            <div className="mt-1 flex flex-wrap gap-1.5">{c.variants.map((v) => <span key={v.id} className="rounded-md bg-surface-2 px-2 py-0.5 font-mono text-xs text-ink-2">{v.sku}</span>)}</div>
          </div>
        ))}
      </details>

      <section className="mt-12">
        <h2 className="font-display text-3xl text-ink">Historial</h2>
        <div className="mt-4 space-y-3">
          {events.length === 0 ? <p className="rounded-2xl border border-dashed border-line bg-surface p-6 text-ink-2">Todavía no hay movimientos de este producto.</p>
            : events.map((e) => <EventCard key={e.id} e={e} />)}
        </div>
      </section>
      {edit && <MakeToOrderPanel productId={product.id} on={product.make_to_order !== false} />}
      {edit && <ArchivePanel productId={product.id} name={product.name} state={archive} />}
    </div>
  );
}
