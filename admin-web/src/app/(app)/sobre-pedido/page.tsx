import { listMadeToOrder, listStoreShipments } from '@/lib/f360';
import { ShipButton } from './ShipButton';
import { fecha } from '@/lib/format';
import { StatusButtons } from './StatusButtons';

const ESTADO: Record<string, string> = { pendiente: 'Pendiente', en_proceso: 'En proceso', enviado: 'Enviado', cancelado: 'Cancelado' };

// Online orders of a size that had no stock (sobre pedido). Nothing was discounted from inventory; the pair has to be
// made or found and shipped within 5–7 business days.
export default async function SobrePedido() {
  const [rows, ships] = await Promise.all([listMadeToOrder(), listStoreShipments()]);
  const open = rows.filter((r) => r.status === 'pendiente' || r.status === 'en_proceso');
  return (
    <div className="mx-auto max-w-5xl">
      <h1 className="font-display text-5xl text-ink">Pedidos en línea</h1>
      <h2 className="mt-8 font-display text-3xl text-ink">Enviar desde una tienda</h2>
      <p className="mt-2 text-ink-2">Compras en línea que se surten con un par que está en una tienda (las tiendas también son bodega). La tienda recibió un aviso.</p>
      {ships.length === 0 ? <p className="mt-4 text-sm text-muted">Nada por enviar.</p> : (
        <ul className="mt-4 space-y-2">{ships.map((s) => (
          <li key={s.id} className={`flex flex-wrap items-center justify-between gap-3 rounded-2xl border bg-surface p-4 ${s.status === 'por_enviar' ? 'border-gold' : 'border-line'}`}>
            <p className="text-ink">Pedido #{s.order} · <b>{s.label}</b>{s.quantity > 1 && <> × {s.quantity}</>} · desde <b>{s.store}</b> <span className="text-sm text-muted">· {fecha(s.created_at)}</span></p>
            {s.status === 'por_enviar' ? <ShipButton id={s.id} /> : <span className="text-sm text-ink-2">Enviado · {s.shipped_by}</span>}
          </li>))}</ul>
      )}
      <h2 className="mt-10 font-display text-3xl text-ink">De 5 a 7 días</h2>
      <p className="mt-2 text-ink-2">Compras en línea de una talla que no había en Bodega. A la clienta se le dijo <b>5 a 7 días hábiles</b>. No se descontó inventario: cuando el par llegue a Bodega, se recibe como siempre y se envía.</p>
      <p className="mt-4 text-sm text-muted">{open.length} por surtir · {rows.length} en los últimos 90 días</p>
      {rows.length === 0 ? (
        <p className="mt-8 rounded-2xl border border-dashed border-line bg-surface p-8 text-center text-ink-2">Todavía no hay pedidos de tallas sin existencia.</p>
      ) : (
        <ul className="mt-6 space-y-3">
          {rows.map((r) => (
            <li key={r.id} className={`rounded-2xl border bg-surface p-4 ${r.status === 'pendiente' ? 'border-gold' : 'border-line'}`}>
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <p className="text-ink"><b>{r.product}</b> · {r.color} · talla {r.size} {r.quantity > 1 && <>· {r.quantity} pares</>}</p>
                  <p className="mt-1 text-sm text-ink-2">Pedido #{r.order} · {r.store} · {fecha(r.created_at)}{r.ship_by && <> · enviar a más tardar el <b>{fecha(r.ship_by)}</b></>}</p>
                  {r.updated_by && <p className="mt-1 text-xs text-muted">{ESTADO[r.status]} · {r.updated_by}</p>}
                </div>
                <StatusButtons id={r.id} status={r.status} />
              </div>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
