import { listCustomRequests } from '@/lib/f360';
import { fecha } from '@/lib/format';
import { RequestStatus } from './RequestStatus';

// Requests from Hilo's chat on the product page ("¿No encontraste tu color y talla? Lo hacemos a la medida").
export default async function ALaMedida() {
  const rows = await listCustomRequests();
  const wa = (phone: string, name: string, product: string, color: string) =>
    `https://wa.me/${phone.replace(/\D/g, '')}?text=${encodeURIComponent(`¡Hola, ${name}! Soy de Fuxia Ballerinas. Vimos que quieres tus ${product} en ${color} a la medida.`)}`;
  return (
    <div className="mx-auto max-w-5xl">
      <h1 className="font-display text-5xl text-ink">A la medida</h1>
      <p className="mt-2 text-ink-2">Clientas que no encontraron su color o talla y le pidieron a <b>Hilo</b> que se las hagamos. Escríbeles por WhatsApp para darles precio y tiempo.</p>
      {rows.length === 0 ? (
        <p className="mt-8 rounded-2xl border border-dashed border-line bg-surface p-8 text-center text-ink-2">Todavía no hay solicitudes.</p>
      ) : (
        <ul className="mt-6 space-y-3">
          {rows.map((r) => (
            <li key={r.id} className={`rounded-2xl border bg-surface p-4 ${r.status === 'nueva' ? 'border-gold' : 'border-line'}`}>
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <p className="text-ink"><b>{r.product}</b> · color <b>{r.color}</b>{r.size && <> · talla {r.size}</>}{r.store_size && <span className="text-muted"> ({r.store_size})</span>}{r.foot_cm && <> · pie {r.foot_cm} cm</>}</p>
                  <p className="mt-1 text-sm text-ink-2">{r.name} · {r.phone} · {fecha(r.created_at)}{r.country && <> · {r.country.toUpperCase()}</>}</p>
                  {r.note && <p className="mt-1 text-sm text-ink-2">“{r.note}”</p>}
                  {r.updated_by && <p className="mt-1 text-xs text-muted">{r.status} · {r.updated_by}</p>}
                </div>
                <div className="flex flex-col items-end gap-2">
                  {!r.phone.startsWith('···') && <a href={wa(r.phone, r.name, r.product, r.color)} target="_blank" rel="noreferrer" className="rounded-full bg-success px-4 py-2 text-sm text-surface">WhatsApp</a>}
                  <RequestStatus id={r.id} status={r.status} />
                </div>
              </div>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
