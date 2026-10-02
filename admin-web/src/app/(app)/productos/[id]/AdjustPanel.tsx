'use client';
import { useRouter } from 'next/navigation';
import { useState, useTransition } from 'react';
import type { Color, Location } from '@/lib/f360';
import { pares } from '@/lib/format';
import { adjustInventoryAction } from '../../actions';

// Owner only: correct the pairs of one colour at one location (damaged, lost, test pairs, a count difference).
// Each change is one audited ADJUSTMENT with a reason; the database refuses anything that would go below zero.
export function AdjustPanel({ productId, color, sizes, locations }: { productId: string; color: Color; sizes: string[]; locations: Location[] }) {
  const router = useRouter();
  const usable = locations.filter((l) => l.type !== 'transit' && (l.ledger_authority ?? 'f360') === 'f360');
  const [open, setOpen] = useState(false);
  const [loc, setLoc] = useState(usable.find((l) => color.balances.some((b) => b.location_id === l.id && b.on_hand > 0))?.id ?? usable[0]?.id ?? '');
  const [delta, setDelta] = useState<Record<string, number>>({});
  const [reason, setReason] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [key, setKey] = useState(() => crypto.randomUUID());
  const [pending, start] = useTransition();
  const has = (size: string) => color.balances.find((b) => b.location_id === loc && b.size === size)?.on_hand ?? 0;
  const bump = (size: string, n: number) => setDelta((d) => ({ ...d, [size]: Math.max(-has(size), (d[size] ?? 0) + n) }));
  const out = Object.values(delta).filter((n) => n < 0).reduce((a, n) => a - n, 0);
  const inn = Object.values(delta).filter((n) => n > 0).reduce((a, n) => a + n, 0);
  const save = () => start(async () => {
    setError(null);
    const lines = color.variants.map((v) => ({ variantId: v.id, delta: delta[v.size] ?? 0 })).filter((l) => l.delta !== 0);
    const r = await adjustInventoryAction({ idempotencyKey: key, productId, locationId: loc, lines, reason });
    if (!r.ok) { setError(r.error); return; }
    setOpen(false); setDelta({}); setReason(''); setKey(crypto.randomUUID()); router.refresh();
  });
  if (!usable.length) return null;
  if (!open) return (
    <button type="button" onClick={() => setOpen(true)} className="mt-3 rounded-full border border-line bg-surface px-4 py-2 text-sm text-ink-2 hover:border-gold/50" data-testid="adjust-open">
      Ajustar inventario de {color.name}
    </button>
  );
  return (
    <div className="mt-3 rounded-2xl border border-line bg-surface p-5" data-testid="adjust-panel">
      <p className="text-ink">Ajustar inventario · {color.name}</p>
      <p className="mt-1 text-sm text-muted">Para pares dañados, perdidos, de prueba o una diferencia de conteo. Queda en el historial con tu nombre y el motivo.</p>
      <label className="mt-4 block text-sm text-ink-2">Ubicación
        <select aria-label="Ubicación del ajuste" value={loc} onChange={(e) => { setLoc(e.target.value); setDelta({}); }} className="mt-1 block w-full rounded-xl border border-line bg-bg px-3 py-2.5 sm:w-80">
          {usable.map((l) => <option key={l.id} value={l.id}>{l.name}</option>)}
        </select>
      </label>
      <div className="mt-4 grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-6">
        {sizes.filter((s) => color.variants.some((v) => v.size === s)).map((s) => {
          const d = delta[s] ?? 0;
          return (
            <div key={s} className="rounded-xl border border-line bg-bg p-3 text-center">
              <div className="text-xs text-muted">Talla {s}</div>
              <div className="tabular mt-1 text-sm text-ink-2">Hay {has(s)}{d ? <> → <b className={d < 0 ? 'text-danger' : 'text-success'}>{has(s) + d}</b></> : null}</div>
              <div className="mt-2 flex items-center justify-center gap-2">
                <button type="button" aria-label={`Quitar un par talla ${s}`} onClick={() => bump(s, -1)} disabled={has(s) + d <= 0} className="size-8 rounded-full border border-line text-lg disabled:opacity-30">−</button>
                <span className="tabular w-8 text-ink">{d > 0 ? `+${d}` : d < 0 ? `−${-d}` : '0'}</span>
                <button type="button" aria-label={`Agregar un par talla ${s}`} onClick={() => bump(s, 1)} className="size-8 rounded-full border border-line text-lg">+</button>
              </div>
            </div>
          );
        })}
      </div>
      <input aria-label="Motivo del ajuste" value={reason} onChange={(e) => setReason(e.target.value)} placeholder="Motivo (por ejemplo: pares de prueba, dañados, conteo)"
        className="mt-4 w-full rounded-xl border border-line bg-bg px-3 py-2.5 text-sm outline-none focus:border-gold" />
      {error && <p role="alert" className="mt-3 rounded-xl bg-danger-soft px-4 py-3 text-sm text-danger">{error}</p>}
      <div className="mt-4 flex flex-wrap items-center gap-3">
        <button type="button" disabled={pending || (!out && !inn)} onClick={save} className="rounded-full bg-ink px-5 py-3 text-sm text-surface disabled:opacity-40">
          {pending ? 'Guardando…' : `Guardar ajuste${out ? ` · quitar ${pares(out)}` : ''}${inn ? ` · agregar ${pares(inn)}` : ''}`}
        </button>
        <button type="button" onClick={() => { setOpen(false); setDelta({}); }} className="text-sm text-muted">Cancelar</button>
      </div>
    </div>
  );
}
