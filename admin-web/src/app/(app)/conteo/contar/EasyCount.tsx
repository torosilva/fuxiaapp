'use client';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useMemo, useRef, useState, useTransition } from 'react';
import type { EasyModel, EasySheet, EasySize } from '@/lib/f360';
import { ColorDot, ProductImage } from '@/components/ProductImage';
import { openingAddUnlistedAction, openingRecordAction } from '../../actions';

const norm = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();

function SizeTile({ countId, s, locked, onSaved }: { countId: string; s: EasySize; locked: boolean; onSaved: (qty: number) => void }) {
  const [qty, setQty] = useState<string>(s.qty === null ? '' : String(s.qty));
  const [state, setState] = useState<'idle' | 'saving' | 'saved' | 'error'>(s.qty === null ? 'idle' : 'saved');
  const [error, setError] = useState<string | null>(null);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const recount = s.status === 'recontar';

  const save = (value: string) => {
    if (timer.current) clearTimeout(timer.current);
    if (value === '') return;
    timer.current = setTimeout(async () => {
      setState('saving'); setError(null);
      const r = await openingRecordAction(countId, recount ? 're' : '1', [{ variantId: s.variant_id, qty: Number(value) }]);
      if (r.ok) { setState('saved'); onSaved(Number(value)); } else { setState('error'); setError(r.error); }
    }, 500);
  };
  const set = (v: string) => { const clean = v.replace(/\D/g, '').slice(0, 4); setQty(clean); setState('idle'); save(clean); };
  const step = (d: number) => set(String(Math.max(0, Number(qty || 0) + d)));

  const ring = state === 'error' ? 'border-danger bg-danger-soft' : recount ? 'border-danger bg-danger-soft/60'
    : state === 'saved' ? 'border-success/50 bg-success-soft/60' : 'border-line bg-surface';
  return (
    <div className={`flex flex-col items-center gap-2 rounded-2xl border p-3 ${ring}`}>
      <span className="text-sm text-muted">Talla <b className="text-lg text-ink">{s.size}</b></span>
      <div className="flex items-center gap-1.5">
        <button type="button" aria-label={`Menos, talla ${s.size}`} disabled={locked} onClick={() => step(-1)}
          className="h-11 w-11 rounded-full bg-surface-2 text-2xl leading-none text-ink disabled:opacity-40">−</button>
        <input aria-label={`Pares talla ${s.size}`} inputMode="numeric" value={qty} disabled={locked} onChange={(e) => set(e.target.value)} placeholder="–"
          className="tabular h-11 w-14 rounded-xl border border-line bg-bg text-center text-xl text-ink outline-none focus:border-gold" />
        <button type="button" aria-label={`Más, talla ${s.size}`} disabled={locked} onClick={() => step(1)}
          className="h-11 w-11 rounded-full bg-ink text-2xl leading-none text-surface disabled:opacity-40">+</button>
      </div>
      <span className="h-4 text-xs">
        {state === 'saving' ? <span className="text-muted">Guardando…</span>
          : state === 'saved' ? <span className="text-success">✓ Guardado</span>
          : recount ? <span className="text-danger">Se vendió o movió: vuelve a contar</span>
          : state === 'error' ? <span className="text-danger">No se guardó</span> : null}
      </span>
      {error && <span role="alert" className="text-center text-xs text-danger">{error}</span>}
    </div>
  );
}

function ModelCard({ m, onOpen }: { m: EasyModel & { done: number }; onOpen: () => void }) {
  const full = m.done >= m.sizes_total;
  return (
    <button type="button" onClick={onOpen} className="flex items-center gap-4 rounded-2xl border border-line bg-surface p-3 text-left transition hover:border-gold">
      <div className="h-16 w-16 flex-none overflow-hidden rounded-xl bg-surface-2">
        <ProductImage path={m.image} name={m.model} />
      </div>
      <div className="min-w-0 flex-1">
        <p className="truncate text-[17px] text-ink">{m.model}</p>
        <p className="text-sm text-muted">{m.colors.map((c) => c.color).join(' · ')}</p>
        <div className="mt-1.5 h-1.5 overflow-hidden rounded-full bg-surface-2"><div className={`h-full rounded-full ${full ? 'bg-success' : 'bg-gold'}`} style={{ width: `${(m.done / Math.max(1, m.sizes_total)) * 100}%` }} /></div>
      </div>
      <span className={`tabular rounded-full px-3 py-1 text-sm ${full ? 'bg-success-soft text-success' : 'bg-surface-2 text-ink-2'}`}>{full ? 'Listo' : `${m.done}/${m.sizes_total}`}</span>
    </button>
  );
}

function Unlisted({ countId }: { countId: string }) {
  const [open, setOpen] = useState(false);
  const [f, setF] = useState({ description: '', size: '', quantity: '1' });
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);
  const [pending, start] = useTransition();
  if (!open) return <button type="button" onClick={() => setOpen(true)} className="rounded-full border border-line bg-surface px-4 py-3 text-[15px] text-ink-2">Encontré un par que no está en la lista</button>;
  const input = 'mt-1 w-full rounded-xl border border-line bg-bg px-3 py-3 text-[16px]';
  return (
    <div className="rounded-2xl border border-gold/40 bg-gold-soft/50 p-4">
      <p className="text-ink">Par que no está en la lista</p>
      <label className="mt-3 block text-sm text-muted">¿Cómo es? (modelo y color como lo ves)<input className={input} value={f.description} onChange={(e) => setF({ ...f, description: e.target.value })} /></label>
      <div className="mt-3 grid grid-cols-2 gap-3">
        <label className="text-sm text-muted">Talla<input className={input} value={f.size} onChange={(e) => setF({ ...f, size: e.target.value })} /></label>
        <label className="text-sm text-muted">Pares<input inputMode="numeric" className={input} value={f.quantity} onChange={(e) => setF({ ...f, quantity: e.target.value.replace(/\D/g, '') })} /></label>
      </div>
      <div className="mt-3 flex gap-2">
        <button type="button" disabled={pending} onClick={() => start(async () => {
          const r = await openingAddUnlistedAction(countId, f.description.trim(), f.size.trim(), Number(f.quantity || 0));
          if (r.ok) { setMsg({ ok: true, text: 'Anotado. Carolina lo revisa antes de aprobar.' }); setF({ description: '', size: '', quantity: '1' }); }
          else setMsg({ ok: false, text: r.error });
        })} className="rounded-full bg-ink px-5 py-3 text-sm text-surface disabled:opacity-50">Anotar</button>
        <button type="button" onClick={() => { setOpen(false); setMsg(null); }} className="rounded-full px-4 py-3 text-sm text-ink-2">Cerrar</button>
      </div>
      {msg && <p role={msg.ok ? 'status' : 'alert'} className={`mt-3 text-sm ${msg.ok ? 'text-success' : 'text-danger'}`}>{msg.text}</p>}
    </div>
  );
}

export function EasyCount({ sheet }: { sheet: EasySheet }) {
  const router = useRouter();
  const [q, setQ] = useState('');
  const [openId, setOpenId] = useState<string | null>(null);
  const [counted, setCounted] = useState<Record<string, boolean>>(() =>
    Object.fromEntries(sheet.models.flatMap((m) => m.colors.flatMap((c) => c.sizes.map((s) => [s.variant_id, s.qty !== null && s.status !== 'recontar'])))));
  const locked = !['preliminar', 'congelado'].includes(sheet.status);

  const models = useMemo(() => sheet.models.map((m) => ({ ...m, done: m.colors.reduce((a, c) => a + c.sizes.filter((s) => counted[s.variant_id]).length, 0) })), [sheet.models, counted]);
  const total = models.reduce((a, m) => a + m.sizes_total, 0);
  const done = models.reduce((a, m) => a + m.done, 0);
  const shown = q.trim() ? models.filter((m) => norm(m.model).includes(norm(q.trim())) || m.colors.some((c) => norm(c.color).includes(norm(q.trim())))) : models;
  const current = models.find((m) => m.product_id === openId);

  if (current) {
    return (
      <div className="mx-auto max-w-3xl">
        <button type="button" onClick={() => { setOpenId(null); router.refresh(); }} className="text-[15px] text-muted">← Todos los modelos</button>
        <div className="mt-3 flex items-center gap-4">
          <div className="h-20 w-20 flex-none overflow-hidden rounded-2xl bg-surface-2"><ProductImage path={current.image} name={current.model} /></div>
          <div>
            <h1 className="font-display text-4xl text-ink">{current.model}</h1>
            <p className="text-sm text-muted">{current.done} de {current.sizes_total} tallas contadas · escribe 0 si no hay</p>
          </div>
        </div>
        {current.colors.map((c) => (
          <section key={c.color} className="mt-6">
            <h2 className="flex items-center gap-2 text-lg text-ink">
              <ColorDot hex={c.hex} />{c.color}
            </h2>
            <div className="mt-3 grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4">
              {c.sizes.map((s) => (
                <SizeTile key={s.variant_id} countId={sheet.count_id} s={s} locked={locked}
                  onSaved={() => setCounted((x) => ({ ...x, [s.variant_id]: true }))} />
              ))}
            </div>
          </section>
        ))}
        <button type="button" onClick={() => { setOpenId(null); setQ(''); router.refresh(); }} className="mt-8 w-full rounded-full bg-ink py-4 text-[16px] text-surface">Listo, siguiente modelo</button>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-3xl">
      <Link href="/conteo" className="text-sm text-muted">← Conteo de apertura</Link>
      <h1 className="font-display mt-2 text-5xl text-ink">Contar · {sheet.location}</h1>
      <p className="mt-1 text-ink-2">Busca el modelo, tócalo y escribe cuántos pares hay de cada talla. Se guarda solo.</p>

      <div className="mt-5 rounded-2xl bg-ink p-4 text-surface">
        <div className="flex items-baseline justify-between"><span>Tallas contadas</span><span className="tabular text-xl">{done} / {total}</span></div>
        <div className="mt-2 h-2 overflow-hidden rounded-full bg-surface/15"><div className="h-full rounded-full bg-gold" style={{ width: `${(done / Math.max(1, total)) * 100}%` }} /></div>
        {locked && <p className="mt-2 text-sm text-surface/70">Este conteo ya no está abierto.</p>}
      </div>

      <label className="mt-5 block">
        <span className="sr-only">Buscar modelo o color</span>
        <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Buscar modelo o color… (ej. maca, botas, nude)" autoFocus
          className="w-full rounded-2xl border border-line bg-surface px-5 py-4 text-[18px] text-ink outline-none focus:border-gold" />
      </label>

      <div className="mt-4 flex flex-col gap-3">
        {shown.length === 0 ? <p className="rounded-2xl border border-dashed border-line p-6 text-center text-muted">No encontramos “{q}”. Si el par no está en la lista, anótalo abajo.</p>
          : shown.map((m) => <ModelCard key={m.product_id} m={m} onOpen={() => setOpenId(m.product_id)} />)}
      </div>

      <div className="mt-6"><Unlisted countId={sheet.count_id} /></div>
    </div>
  );
}
