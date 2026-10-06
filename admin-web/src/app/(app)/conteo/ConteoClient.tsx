'use client';
import { useRouter } from 'next/navigation';
import { useState, useTransition } from 'react';
import type { OpeningLineStatus, OpeningSheet, OpeningSize, OpeningStatus, OpeningView } from '@/lib/f360';
import { ColorDot } from '@/components/ProductImage';
import { linkChannelAction, openingAddUnlistedAction, openingLoadAction, openingRecordAction, openingRefreshAction, openingResolveUnlistedAction, openingStartAction, openingStepAction } from '../actions';
import { STORE_KEY } from '@/lib/store';

const LINE: Record<OpeningLineStatus, { label: string; tone: string }> = {
  pendiente: { label: 'Sin contar', tone: 'bg-surface-2 text-muted' }, contado_1: { label: 'Falta 2º conteo', tone: 'bg-surface-2 text-ink-2' },
  doble_ok: { label: 'Coincide', tone: 'bg-success-soft text-success' }, diferencia: { label: 'Diferencia', tone: 'bg-danger-soft text-danger' },
  recontado: { label: 'Recontado', tone: 'bg-success-soft text-success' }, recontar: { label: 'Recontar', tone: 'bg-danger-soft text-danger' },
  contado: { label: 'Contado', tone: 'bg-success-soft text-success' },
};
const Msg = ({ m }: { m: { ok: boolean; text: string } | null }) =>
  m ? <p role={m.ok ? 'status' : 'alert'} className={`mt-3 rounded-xl px-4 py-3 text-sm ${m.ok ? 'bg-success-soft text-success' : 'bg-danger-soft text-danger'}`}>{m.text}</p> : null;

export function StartCount() {
  const router = useRouter();
  const [note, setNote] = useState('');
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);
  const [pending, start] = useTransition();
  return (
    <div className="mt-8 rounded-3xl border border-line bg-surface p-5">
      <p className="text-ink">Iniciar el conteo de Bodega CDMX</p>
      <p className="mt-1 text-sm text-muted">La hoja sale de lo confirmado en Homologación. Lo que se confirme después se agrega con “Actualizar lista”. Se puede contar antes (preliminar) y congelar la bodega solo al final.</p>
      <input aria-label="Nota" value={note} onChange={(e) => setNote(e.target.value)} placeholder="Nota (opcional)" className="mt-3 w-full rounded-xl border border-line bg-bg px-3 py-2.5 text-sm" />
      <button type="button" disabled={pending} onClick={() => start(async () => {
        const r = await openingStartAction(STORE_KEY, note);
        if (!r.ok) setMsg({ ok: false, text: r.error }); else router.refresh();
      })} className="mt-3 rounded-full bg-ink px-5 py-3 text-sm text-surface disabled:opacity-40">{pending ? 'Iniciando…' : 'Iniciar conteo'}</button>
      <Msg m={msg} />
    </div>
  );
}

export function CountControls({ id, status, owner, blockers }: { id: string; status: OpeningStatus; owner: boolean; blockers: string[] }) {
  const router = useRouter();
  const [ask, setAsk] = useState<null | 'approve' | 'cancel'>(null);
  const [note, setNote] = useState('');
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);
  const [loadKey] = useState(() => crypto.randomUUID());
  const [pending, start] = useTransition();
  const run = (fn: () => Promise<{ ok: boolean; error?: string }>, ok: string) => start(async () => {
    const r = await fn(); setMsg(r.ok ? { ok: true, text: ok } : { ok: false, text: r.error ?? 'No se pudo.' }); if (r.ok) { setAsk(null); setNote(''); } router.refresh();
  });
  const open = status === 'preliminar' || status === 'congelado';
  return (
    <section className="mt-6 rounded-3xl border border-line bg-surface p-5" data-testid="count-controls">
      <div className="flex flex-wrap gap-2">
        {open && <button type="button" disabled={pending} onClick={() => run(() => openingRefreshAction(id), 'Lista actualizada con lo confirmado en Homologación.')} className="rounded-full border border-line px-4 py-2 text-sm text-ink-2">Actualizar lista</button>}
        {owner && status === 'preliminar' && <button type="button" disabled={pending} onClick={() => run(() => openingStepAction(id, 'freeze'), 'Bodega congelada. Ahora reconcilia y termina los reconteos.')} className="rounded-full border border-danger px-4 py-2 text-sm text-danger">Congelar bodega (ventana final)</button>}
        {status === 'congelado' && <button type="button" disabled={pending} onClick={() => run(() => openingStepAction(id, 'reconcile'), 'Reconciliado: revisa “Reconteo” por si algo vendió o se movió después de contarse.')} className="rounded-full border border-line px-4 py-2 text-sm text-ink-2">Reconciliar ventas y movimientos</button>}
        {owner && status === 'congelado' && <button type="button" disabled={pending || blockers.length > 0} onClick={() => setAsk('approve')} className="rounded-full bg-ink px-4 py-2 text-sm text-surface disabled:opacity-40">Aprobar conteo</button>}
        {owner && status === 'aprobado' && <button type="button" disabled={pending} data-testid="load-opening" onClick={() => run(() => openingLoadAction(id, loadKey), 'Inventario inicial cargado en Bodega CDMX.')} className="rounded-full bg-ink px-4 py-2 text-sm text-surface">Cargar inventario inicial</button>}
        {owner && status === 'cargado' && <button type="button" disabled={pending} onClick={() => run(async () => { const r = await linkChannelAction(STORE_KEY); return r.ok ? { ok: true } : r; }, 'Tienda ligada: las cantidades se envían en ~1 minuto (0 = agotado).')} className="rounded-full bg-ink px-4 py-2 text-sm text-surface">Ligar la tienda completa</button>}
        {owner && open && <button type="button" disabled={pending} onClick={() => setAsk('cancel')} className="ml-auto rounded-full px-4 py-2 text-sm text-muted underline">Cancelar conteo</button>}
      </div>
      {status === 'congelado' && blockers.length > 0 && (
        <div className="mt-3 text-sm text-ink-2" data-testid="blockers"><p>Para aprobar falta:</p><ul className="mt-1 list-disc pl-5 text-muted">{blockers.map((b) => <li key={b}>{b}</li>)}</ul></div>
      )}
      {status === 'preliminar' && <p className="mt-3 text-xs text-muted">Cuando el conteo esté casi listo, congela la bodega (ventana corta), reconcilia, haz los reconteos que pida y Mario aprueba.</p>}
      {ask && (
        <div className="mt-4 flex flex-wrap items-center gap-2">
          <input aria-label={ask === 'approve' ? 'Nota de aprobación' : 'Motivo de cancelación'} value={note} onChange={(e) => setNote(e.target.value)}
            placeholder={ask === 'approve' ? 'Nota de aprobación' : '¿Por qué se cancela?'} className="min-w-64 flex-1 rounded-xl border border-line bg-bg px-3 py-2.5 text-sm" />
          <button type="button" disabled={pending} onClick={() => run(() => openingStepAction(id, ask, note), ask === 'approve' ? 'Conteo aprobado. El inventario no se ha cargado todavía.' : 'Conteo cancelado; la bodega ya no está congelada.')}
            className="rounded-xl bg-ink px-4 py-2.5 text-sm text-surface">{ask === 'approve' ? 'Aprobar' : 'Cancelar conteo'}</button>
          <button type="button" onClick={() => setAsk(null)} className="text-sm text-muted">Volver</button>
        </div>
      )}
      <Msg m={msg} />
    </section>
  );
}

const visible = (view: OpeningView, s: OpeningSize) =>
  view === 'reconteo' ? s.status === 'diferencia' || s.status === 'recontar' : view === 'conteo2' ? s.count1_done : true;

export function CountSheet({ id, view, open, sheet }: { id: string; view: OpeningView; open: boolean; sheet: OpeningSheet }) {
  if (view === 'reporte') return <Report sheet={sheet} />;
  const models = sheet.models.map((m) => ({ ...m, colors: m.colors.map((c) => ({ ...c, sizes: c.sizes.filter((s) => visible(view, s)) })).filter((c) => c.sizes.length) })).filter((m) => m.colors.length);
  return (
    <div className="mt-6 grid gap-4">
      <p className="text-sm text-muted">
        {view === 'conteo1' && 'Cuenta los pares físicos de cada talla y guarda por color. Si una talla tiene 0, escribe 0.'}
        {view === 'conteo2' && 'Segundo conteo, hecho por otra persona: no ves el primer conteo. Si no coincide, la talla pasa a reconteo.'}
        {view === 'reconteo' && 'Tallas donde el conteo 1 y 2 no coinciden, o que vendieron/se movieron después de contarse. Vuelve a contarlas.'}
      </p>
      {models.length === 0 && <p className="rounded-2xl border border-dashed border-line bg-surface p-6 text-ink-2">{view === 'reconteo' ? 'No hay nada que recontar.' : view === 'conteo2' ? 'Todavía no hay tallas con primer conteo.' : 'No hay modelos confirmados en Homologación todavía.'}</p>}
      {models.map((m) => (
        <section key={m.product_id} className="rounded-3xl border border-line bg-surface p-5" data-testid={`count-model-${m.model}`}>
          <h2 className="font-display text-3xl text-ink">{m.model}</h2>
          <div className="mt-3 grid gap-3">{m.colors.map((c) => <ColorRow key={c.color} id={id} view={view} open={open} color={c} />)}</div>
        </section>
      ))}
    </div>
  );
}

function ColorRow({ id, view, open, color }: { id: string; view: OpeningView; open: boolean; color: OpeningSheet['models'][number]['colors'][number] }) {
  const router = useRouter();
  const round = view === 'conteo1' ? '1' : view === 'conteo2' ? '2' : 're';
  const shown = (s: OpeningSize) => (view === 'conteo1' ? s.count1 : view === 'conteo2' ? s.count2 : null);
  const [qty, setQty] = useState<Record<string, string>>(() => Object.fromEntries(color.sizes.map((s) => [s.variant_id, shown(s)?.toString() ?? ''])));
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);
  const [pending, start] = useTransition();
  const locked = (s: OpeningSize) => !open || (view === 'conteo1' && s.count2 !== null) || (view === 'conteo2' && s.count2 !== null);
  const save = () => start(async () => {
    const lines = color.sizes.filter((s) => !locked(s) && qty[s.variant_id] !== '').map((s) => ({ variantId: s.variant_id, qty: Number(qty[s.variant_id]) }));
    const r = await openingRecordAction(id, round, lines);
    setMsg(r.ok ? { ok: true, text: `${color.color}: guardado.` } : { ok: false, text: r.error }); if (r.ok) router.refresh();
  });
  return (
    <div className="rounded-2xl bg-bg p-4" data-testid={`count-color-${color.color}`}>
      <p className="flex items-center gap-2 text-ink"><ColorDot hex={color.hex} />{color.color}</p>
      <div className="mt-3 grid grid-cols-3 gap-2 sm:grid-cols-6">
        {color.sizes.map((s) => (
          <label key={s.variant_id} className="rounded-xl border border-line bg-surface p-2 text-center">
            <span className="block text-xs text-muted">Talla {s.size}</span>
            <input aria-label={`${color.color} talla ${s.size}`} inputMode="numeric" value={qty[s.variant_id] ?? ''} disabled={locked(s) || pending}
              onChange={(e) => setQty({ ...qty, [s.variant_id]: e.target.value.replace(/[^0-9]/g, '') })}
              className="tabular mt-1 w-full rounded-lg border border-line bg-bg px-2 py-2 text-center text-xl outline-none focus:border-gold disabled:opacity-50" />
            <span className={`mt-1 inline-block rounded-full px-2 py-0.5 text-[11px] ${LINE[s.status].tone}`}>{LINE[s.status].label}</span>
            {view === 'reconteo' && (
              <span className="mt-1 block text-[11px] text-muted">{s.status === 'diferencia' ? `C1 ${s.count1} · C2 ${s.count2}` : s.affected ? `${s.affected.woo_sold ? `vendió ${s.affected.woo_sold} en línea` : ''}${s.affected.woo_sold && s.affected.moves ? ' · ' : ''}${s.affected.moves ? `${s.affected.moves} movimientos` : ''} después de contarse` : ''}</span>
            )}
            {view === 'conteo2' && s.count2 === null && <span className="mt-1 block text-[11px] text-muted">Conteo 1 hecho</span>}
          </label>
        ))}
      </div>
      {open && <button type="button" disabled={pending} onClick={save} className="mt-3 rounded-full bg-ink px-4 py-2 text-sm text-surface disabled:opacity-40">{pending ? 'Guardando…' : `Guardar ${color.color}`}</button>}
      <Msg m={msg} />
    </div>
  );
}

function Report({ sheet }: { sheet: OpeningSheet }) {
  const rows = sheet.models.flatMap((m) => m.colors.flatMap((c) => c.sizes.map((s) => ({ model: m.model, color: c.color, ...s }))));
  const total = rows.filter((r) => r.in_scope).reduce((a, r) => a + (r.final_qty ?? 0), 0);
  const csv = () => {
    const head = ['Modelo', 'Color', 'Talla', 'SKU F360', 'variation_id Woo', 'Woo actual', 'Conteo 1', 'Conteo 2', 'Reconteo', 'Opening balance', 'Diferencia vs Woo', 'Estado'];
    const body = rows.map((r) => [r.model, r.color, r.size, r.sku ?? '', (r.woo_variations ?? []).join(' '), r.woo_managed ? r.woo_stock ?? 0 : 'sin control', r.count1 ?? '', r.count2 ?? '', r.recount ?? '',
      r.in_scope ? r.final_qty ?? '' : 'fuera', r.difference ?? '', LINE[r.status].label]);
    const text = [head, ...body].map((l) => l.map((v) => `"${String(v).replace(/"/g, '""')}"`).join(',')).join('\n');
    const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([text], { type: 'text/csv' })); a.download = 'conteo-apertura-bodega-cdmx.csv'; a.click();
  };
  return (
    <section className="mt-6" data-testid="count-report">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="text-sm text-ink-2"><b>Opening balance propuesto:</b> <span className="tabular">{total}</span> pares (solo tallas con conteo final). Woo es solo referencia.</p>
        <button type="button" onClick={csv} className="rounded-full border border-line px-4 py-2 text-sm text-ink-2">Descargar CSV</button>
      </div>
      <div className="mt-3 overflow-x-auto rounded-2xl border border-line bg-surface">
        <table className="tabular w-full min-w-[980px] text-sm">
          <thead className="text-left text-xs uppercase tracking-wider text-muted"><tr className="border-b border-line">
            <th className="px-4 py-2 font-normal">Modelo · color · talla</th><th className="px-3 py-2 font-normal">Woo actual</th><th className="px-3 py-2 font-normal">Conteo 1</th>
            <th className="px-3 py-2 font-normal">Conteo 2</th><th className="px-3 py-2 font-normal">Reconteo</th><th className="px-3 py-2 font-normal">Conteo físico (final)</th>
            <th className="px-3 py-2 font-normal">Diferencia</th><th className="px-3 py-2 font-normal">Opening balance</th><th className="px-3 py-2 font-normal">Estado</th></tr></thead>
          <tbody>{rows.map((r) => (
            <tr key={r.variant_id} className={`border-b border-line last:border-0 ${r.in_scope ? '' : 'opacity-40'}`}>
              <td className="px-4 py-2 text-ink">{r.model} · {r.color} · {r.size}<div className="text-[11px] text-muted">{r.sku}{r.woo_variations?.length ? ` · Woo ${r.woo_variations.join(', ')}` : ''}</div></td>
              <td className="px-3 py-2 text-ink-2">{r.woo_managed ? r.woo_stock ?? 0 : <span className="text-muted">sin control · en stock</span>}</td>
              <td className="px-3 py-2">{r.count1 ?? '—'}<div className="text-[11px] text-muted">{r.count1_by}</div></td>
              <td className="px-3 py-2">{r.count2 ?? '—'}<div className="text-[11px] text-muted">{r.count2_by}</div></td>
              <td className="px-3 py-2">{r.recount ?? '—'}<div className="text-[11px] text-muted">{r.recount_by}</div></td>
              <td className="px-3 py-2 font-medium text-ink">{r.final_qty ?? '—'}</td>
              <td className="px-3 py-2">{r.difference == null ? '—' : r.difference > 0 ? `+${r.difference}` : r.difference}</td>
              <td className="px-3 py-2 font-semibold text-ink">{r.in_scope ? r.final_qty ?? '—' : 'fuera de alcance'}</td>
              <td className="px-3 py-2"><span className={`rounded-full px-2 py-0.5 text-[11px] ${LINE[r.status].tone}`}>{LINE[r.status].label}</span></td>
            </tr>))}
          </tbody>
        </table>
      </div>
    </section>
  );
}

export function Unlisted({ id, open, owner, items }: { id: string; open: boolean; owner: boolean; items: OpeningSheet['unlisted'] }) {
  const router = useRouter();
  const [f, setF] = useState({ description: '', size: '', quantity: '1' });
  const [res, setRes] = useState<Record<string, string>>({});
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);
  const [pending, start] = useTransition();
  return (
    <section className="mt-6 grid gap-4" data-testid="unlisted">
      <p className="text-sm text-muted">Pares que encuentras en la bodega pero no están en la hoja (no se homologaron). Se anotan aquí para no perderlos; no cuentan como inventario hasta resolverlos.</p>
      {open && (
        <div className="flex flex-wrap items-end gap-2 rounded-2xl border border-line bg-surface p-4">
          <label className="min-w-56 flex-1 text-sm text-ink-2">Cómo es (modelo y color como lo ves)<input aria-label="Descripción" value={f.description} onChange={(e) => setF({ ...f, description: e.target.value })} className="mt-1 w-full rounded-xl border border-line bg-bg px-3 py-2.5" /></label>
          <label className="w-24 text-sm text-ink-2">Talla<input aria-label="Talla sin ficha" value={f.size} onChange={(e) => setF({ ...f, size: e.target.value })} className="mt-1 w-full rounded-xl border border-line bg-bg px-3 py-2.5" /></label>
          <label className="w-24 text-sm text-ink-2">Pares<input aria-label="Pares sin ficha" inputMode="numeric" value={f.quantity} onChange={(e) => setF({ ...f, quantity: e.target.value.replace(/[^0-9]/g, '') })} className="mt-1 w-full rounded-xl border border-line bg-bg px-3 py-2.5" /></label>
          <button type="button" disabled={pending} onClick={() => start(async () => {
            const r = await openingAddUnlistedAction(id, f.description, f.size, Number(f.quantity));
            setMsg(r.ok ? { ok: true, text: 'Anotado.' } : { ok: false, text: r.error }); if (r.ok) { setF({ description: '', size: '', quantity: '1' }); router.refresh(); }
          })} className="rounded-xl bg-ink px-4 py-2.5 text-sm text-surface">Anotar</button>
        </div>
      )}
      <Msg m={msg} />
      {items.length === 0 ? <p className="rounded-2xl border border-dashed border-line bg-surface p-6 text-ink-2">No hay pares sin ficha.</p> : items.map((u) => (
        <div key={u.id} className="rounded-2xl border border-line bg-surface p-4">
          <p className="text-ink">{u.description}{u.size ? ` · talla ${u.size}` : ''} · <b>{u.quantity}</b> {u.quantity === 1 ? 'par' : 'pares'}</p>
          <p className="text-xs text-muted">Anotó {u.found_by}{u.status === 'resuelto' ? ` · resuelto por ${u.resolved_by}: “${u.resolution}”` : ' · por resolver'}</p>
          {owner && open && u.status === 'abierto' && (
            <div className="mt-2 flex flex-wrap gap-2">
              <input aria-label="Cómo se resolvió" value={res[u.id] ?? ''} onChange={(e) => setRes({ ...res, [u.id]: e.target.value })} placeholder="Cómo se resolvió (p. ej. se homologó como …)" className="min-w-64 flex-1 rounded-xl border border-line bg-bg px-3 py-2 text-sm" />
              <button type="button" disabled={pending} onClick={() => start(async () => {
                const r = await openingResolveUnlistedAction(u.id, res[u.id] ?? ''); setMsg(r.ok ? { ok: true, text: 'Resuelto.' } : { ok: false, text: r.error }); if (r.ok) router.refresh();
              })} className="rounded-xl border border-line px-3 py-2 text-sm">Marcar resuelto</button>
            </div>
          )}
        </div>
      ))}
    </section>
  );
}
