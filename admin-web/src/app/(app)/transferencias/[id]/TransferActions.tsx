'use client';
import { useRouter } from 'next/navigation';
import { useState, useTransition } from 'react';
import type { Transfer } from '@/lib/f360';
import { pares } from '@/lib/format';
import { cancelTransferAction, receiveTransferAction, resolveTransferAction, sendTransferAction } from '../../actions';

type Mode = null | 'send' | 'receive' | 'resolve' | 'cancel';

// The buttons shown come from `t.can`, computed by the database for this person right now; the database checks again.
export function TransferActions({ t }: { t: Transfer }) {
  const router = useRouter();
  const [mode, setMode] = useState<Mode>(null);
  const [qty, setQty] = useState<Record<string, number>>({});
  const [how, setHow] = useState<Record<string, 'return' | 'write_off'>>({});
  const [reason, setReason] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  const [idemKey, setIdemKey] = useState(() => crypto.randomUUID());   // one key per action: a double click can't repeat it

  if (!t.can.send && !t.can.receive && !t.can.resolve && !t.can.cancel) return null;

  const open = (m: Mode) => {
    setError(null); setReason(''); setIdemKey(crypto.randomUUID()); setMode(m);
    if (m === 'send') setQty(Object.fromEntries(t.lines.map((l) => [l.variant_id, Math.min(l.requested, l.available_at_origin)])));
    if (m === 'receive') setQty(Object.fromEntries(t.lines.map((l) => [l.variant_id, l.sent ?? 0])));
    if (m === 'resolve') { setQty(Object.fromEntries(t.lines.map((l) => [l.variant_id, l.outstanding]))); setHow({}); }
  };
  const max = (variantId: string) => {
    const l = t.lines.find((x) => x.variant_id === variantId)!;
    return mode === 'send' ? Math.min(l.requested, l.available_at_origin) : mode === 'receive' ? l.sent ?? 0 : l.outstanding;
  };
  const set = (variantId: string, n: number) => setQty((q) => ({ ...q, [variantId]: Math.max(0, Math.min(max(variantId), Math.floor(n) || 0)) }));
  const lines = t.lines.filter((l) => (mode === 'receive' ? (l.sent ?? 0) > 0 : mode === 'resolve' ? l.outstanding > 0 : true));
  const total = lines.reduce((a, l) => a + (qty[l.variant_id] ?? 0), 0);
  const expected = mode === 'receive' ? t.totals.sent : 0;

  const run = () => start(async () => {
    setError(null);
    const q = lines.map((l) => ({ variantId: l.variant_id, quantity: qty[l.variant_id] ?? 0 }));
    const r = mode === 'send' ? await sendTransferAction(t.id, idemKey, q)
      : mode === 'receive' ? await receiveTransferAction(t.id, idemKey, q)
      : mode === 'resolve' ? await resolveTransferAction(t.id, idemKey, q.map((x) => ({ ...x, action: how[x.variantId] ?? 'return' })), reason)
      : await cancelTransferAction(t.id, idemKey, reason);
    if (!r.ok) return setError(r.error);
    setMode(null);
    router.refresh();
  });

  const btn = 'rounded-2xl px-5 py-4 text-lg transition disabled:opacity-50';
  return (
    <section className="mt-8">
      {mode === null && (
        <div className="grid gap-3 sm:grid-cols-2">
          {t.can.send && <button type="button" onClick={() => open('send')} className={`${btn} bg-ink text-surface hover:bg-ink-2`}>Preparar y enviar</button>}
          {t.can.receive && <button type="button" onClick={() => open('receive')} className={`${btn} bg-ink text-surface hover:bg-ink-2`}>Confirmar recepción</button>}
          {t.can.resolve && <button type="button" onClick={() => open('resolve')} className={`${btn} bg-ink text-surface hover:bg-ink-2`}>Resolver diferencia</button>}
          {t.can.cancel && <button type="button" onClick={() => open('cancel')} className={`${btn} border border-line bg-surface text-ink`}>Cancelar solicitud</button>}
        </div>
      )}

      {mode && (
        <div className="rounded-3xl border border-line bg-surface p-5">
          <h2 className="font-display text-3xl text-ink">
            {mode === 'send' ? 'Preparar y enviar' : mode === 'receive' ? '¿Qué llegó?' : mode === 'resolve' ? '¿Qué pasó con lo que falta?' : 'Cancelar solicitud'}
          </h2>
          <p className="mt-1 text-sm text-muted">
            {mode === 'send' ? `Salen de ${t.from.name} y quedan en camino. Solo puedes enviar lo que hay.`
              : mode === 'receive' ? `Cuenta los pares que llegaron a ${t.to.name}. Si falta algo, escribe lo que sí llegó.`
              : mode === 'resolve' ? 'Regresar al origen (se encontró / volvió) o dar de baja (perdido o dañado). El motivo es obligatorio.'
              : 'No se ha movido ningún par. La solicitud queda registrada como cancelada.'}
          </p>

          {mode !== 'cancel' && (
            <div className="mt-4 divide-y divide-line">
              {lines.map((l) => {
                const n = qty[l.variant_id] ?? 0;
                return (
                  <div key={l.variant_id} className="flex flex-wrap items-center justify-between gap-3 py-3">
                    <div className="min-w-0">
                      <div className="font-medium text-ink">{l.product_name} · {l.color} · Talla {l.size}</div>
                      <div className="text-sm text-muted">
                        {mode === 'send' ? `pedido ${l.requested} · hay ${l.available_at_origin} en ${t.from.name}` : mode === 'receive' ? `enviado ${l.sent}` : `faltan ${l.outstanding}`}
                      </div>
                    </div>
                    <div className="flex items-center gap-2">
                      {mode === 'resolve' && (
                        <select aria-label={`Qué pasó con talla ${l.size}`} value={how[l.variant_id] ?? 'return'} onChange={(e) => setHow({ ...how, [l.variant_id]: e.target.value as 'return' | 'write_off' })}
                          className="rounded-xl border border-line bg-surface px-3 py-3">
                          <option value="return">Regresa a {t.from.name}</option>
                          <option value="write_off">Dar de baja</option>
                        </select>
                      )}
                      <input aria-label={`Cantidad talla ${l.size}`} inputMode="numeric" value={n} onChange={(e) => set(l.variant_id, Number(e.target.value.replace(/\D/g, '')))}
                        className="tabular w-20 rounded-xl border border-line bg-surface py-3 text-center text-2xl outline-none focus:border-gold" />
                    </div>
                  </div>
                );
              })}
            </div>
          )}

          {mode === 'receive' && total < expected && (
            <p className="mt-3 rounded-xl bg-danger-soft px-4 py-3 text-danger">Faltan {pares(expected - total)}. La transferencia quedará <b>con diferencia</b> y esos pares seguirán identificados hasta que operación los resuelva.</p>
          )}
          {(mode === 'resolve' || mode === 'cancel') && (
            <textarea value={reason} onChange={(e) => setReason(e.target.value)} rows={2} placeholder={mode === 'resolve' ? 'Motivo (obligatorio): p. ej. caja dañada en paquetería' : 'Motivo (opcional)'}
              className="mt-4 w-full rounded-2xl border border-line bg-surface px-4 py-3 outline-none focus:border-gold" aria-label="Motivo" />
          )}
          {error && <p role="alert" className="mt-4 rounded-xl bg-danger-soft px-4 py-3 text-danger">{error}</p>}
          <div className="mt-5 grid gap-3 sm:grid-cols-2">
            <button type="button" onClick={run} disabled={pending || (mode === 'send' && total === 0) || (mode === 'resolve' && (total === 0 || reason.trim().length < 3))}
              className={`${btn} bg-ink font-semibold text-surface hover:bg-ink-2`}>
              {pending ? 'Guardando…' : mode === 'send' ? `Enviar ${pares(total)}` : mode === 'receive' ? `Recibí ${pares(total)}` : mode === 'resolve' ? `Resolver ${pares(total)}` : 'Sí, cancelar'}
            </button>
            <button type="button" onClick={() => setMode(null)} disabled={pending} className={`${btn} border border-line bg-surface text-ink`}>Volver</button>
          </div>
        </div>
      )}
    </section>
  );
}
