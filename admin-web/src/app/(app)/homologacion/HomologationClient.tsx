'use client';
import { useRouter } from 'next/navigation';
import { Fragment, useMemo, useState, useTransition } from 'react';
import type { ChannelState, Homologation, HomologationRow, HomologationStatus } from '@/lib/f360';
import { confirmHomologationAction, markHomologationAction, reopenHomologationAction, storeVisibilityAction } from '../actions';
import { runStoreImport } from '../productos/[id]/StoreImport';

const LABEL: Record<HomologationStatus, string> = {
  propuesto: 'Propuesto', confirmado: 'Confirmado', requiere_revision: 'Requiere revisión', conflicto: 'Conflicto', sin_correspondencia: 'Sin correspondencia',
};
const TONE: Record<HomologationStatus, string> = {
  propuesto: 'bg-gold-soft text-gold-strong', confirmado: 'bg-success-soft text-success', requiere_revision: 'bg-surface-2 text-ink-2',
  conflicto: 'bg-danger-soft text-danger', sin_correspondencia: 'bg-surface-2 text-muted',
};
const FILTERS: (HomologationStatus | 'todos')[] = ['todos', 'propuesto', 'requiere_revision', 'conflicto', 'sin_correspondencia', 'confirmado'];

// A "unit" is what Carolina decides at once: one Woo product (one colour), or one colour inside a multi-colour Woo product.
type Unit = { key: string; wooProductId: number; wooProductName: string; wooColor: string | null; sku: string | null; category: string | null;
  price: number | null; rows: HomologationRow[]; detectedColor: string | null; status: HomologationStatus | 'mixto'; sold: number };
type Group = { key: string; name: string; proposedProductId: string | null; units: Unit[] };

const sizeSort = (a: HomologationRow, b: HomologationRow) => Number(a.woo_size) - Number(b.woo_size) || String(a.woo_size).localeCompare(String(b.woo_size));

function buildGroups(rows: HomologationRow[]): Group[] {
  const units = new Map<string, Unit>();
  for (const r of rows) {
    const key = `${r.woo_product_id}|${r.woo_color ?? ''}`;
    const u = units.get(key) ?? { key, wooProductId: r.woo_product_id, wooProductName: r.woo_product_name, wooColor: r.woo_color, sku: r.woo_parent_sku,
      category: r.woo_category, price: r.woo_regular_price, rows: [], detectedColor: null, status: r.status, sold: 0 };
    u.rows.push(r); u.sold += r.sold_all;
    if (u.status !== r.status) u.status = 'mixto';
    u.detectedColor = u.detectedColor ?? r.woo_color ?? r.proposed_color;
    units.set(key, u);
  }
  const groups = new Map<string, Group>();
  for (const u of units.values()) {
    u.rows.sort(sizeSort);
    const confirmed = u.rows.find((r) => r.confirmed)?.confirmed;
    const name = confirmed?.product_name ?? u.rows[0].proposed_model ?? 'Sin modelo propuesto';
    const g = groups.get(name.toLowerCase()) ?? { key: name.toLowerCase(), name, proposedProductId: confirmed?.product_id ?? u.rows[0].proposed_product_id, units: [] };
    g.units.push(u);
    groups.set(g.key, g);
  }
  return [...groups.values()].sort((a, b) => priority(a) - priority(b) || b.units.length - a.units.length || a.name.localeCompare(b.name));
}

// 0 = everything pending is ready to confirm · 1 = partly ready · 2 = conflict · 3 = needs a decision · 4 = done
// A row is decided when it is confirmed, or a person marked it "sin correspondencia" (e.g. "no existe").
const decided = (r: HomologationRow) => r.status === 'confirmado' || (r.status === 'sin_correspondencia' && r.human_locked);

function priority(g: Group) {
  const pending = g.units.flatMap((u) => u.rows).filter((r) => !decided(r));
  if (!pending.length) return 4;
  if (pending.every((r) => r.status === 'propuesto')) return 0;
  if (pending.some((r) => r.status === 'propuesto')) return 1;
  if (pending.some((r) => r.status === 'conflicto')) return 2;
  return 3;
}

// What the person has to do with this Woo product, in plain words.
function todo(u: Unit): string {
  const r = u.rows.find((x) => !decided(x)) ?? u.rows.find((x) => x.status !== 'confirmado') ?? u.rows[0];
  if (r.status === 'confirmado') return `Listo${r.decided_by_name ? ` · confirmó ${r.decided_by_name}` : ''}`;
  if (r.status === 'propuesto') return 'Revisa que modelo y color estén bien y confirma';
  if (r.status === 'conflicto') return 'Otro producto de la tienda quedó con el mismo modelo, color y talla: decide cuál es';
  if (r.status === 'sin_correspondencia' && r.human_locked) return `Decidido: no se usa${r.note ? ` (“${r.note}”)` : ''}${r.decided_by_name ? ` · ${r.decided_by_name}` : ''}`;
  if (r.human_locked) return r.note ? `Marcado: ${r.note}` : 'Marcado por una persona';
  const why = r.proposal_reason ?? '';
  if (/cualquier color/.test(why)) return 'La tienda vende esta talla en “cualquier color”: solo confírmala si sabes qué color sale';
  if (/ya existe un modelo/.test(why)) return 'Ya hay un modelo con ese nombre en Fuxia 360: decide si es el mismo';
  if (!r.proposed_color) return 'No sabemos el color: escríbelo al confirmar, o márcalo si no estás segura';
  if (/a mitad del nombre/.test(why)) return 'El color estaba a mitad del nombre: revisa modelo y color';
  return 'Revisa modelo y color';
}

type Vis = ChannelState['visibility'][number];
const isNoExiste = (u: Unit) => u.rows.every((r) => r.status === 'sin_correspondencia' && r.human_locked);

export function HomologationClient({ data, visibility }: { data: Homologation; visibility: Vis[] }) {
  const router = useRouter();
  const [hiding, startHiding] = useTransition();
  const vis = useMemo(() => new Map(visibility.map((v) => [v.woo_product_id, v])), [visibility]);
  const [filter, setFilter] = useState<HomologationStatus | 'todos'>('todos');
  const [query, setQuery] = useState('');
  const [flash, setFlash] = useState<string | null>(null);
  const groups = useMemo(() => buildGroups(data.rows), [data.rows]);
  const q = query.trim().toLowerCase();
  const visible = groups.map((g) => ({ ...g, units: g.units.filter((u) =>
      (filter === 'todos' || u.rows.some((r) => r.status === filter))
      && (!q || g.name.toLowerCase().includes(q) || u.wooProductName.toLowerCase().includes(q) || (u.sku ?? '').toLowerCase().includes(q)
          || u.rows.some((r) => String(r.woo_variation_id) === q))) }))
    .filter((g) => g.units.length);
  const s = data.summary;
  const nDiscarded = data.rows.filter((r) => r.status === 'sin_correspondencia' && r.human_locked).length;
  const nDecided = s.confirmado + nDiscarded;
  const nPending = s.variations - nDecided;
  const pctDecided = s.variations ? Math.round((1000 * nDecided) / s.variations) / 10 : 0;
  const noExiste = [...new Map(groups.flatMap((g) => g.units).filter(isNoExiste).map((u) => [u.wooProductId, u])).values()];
  const hidden = (id: number) => { const v = vis.get(id); return !!v && !v.pending && v.last?.kind === 'ocultar' && v.last.status === 'hecho'; };
  const toHide = noExiste.filter((u) => !hidden(u.wooProductId) && !vis.get(u.wooProductId)?.pending);
  const hideAll = () => startHiding(async () => {
    let n = 0; let err = '';
    for (const u of toHide) { const r = await storeVisibilityAction(data.target.key, u.wooProductId, 'ocultar', 'Marcado “no existe” en Homologación'); if (r.ok) n++; else err = r.error; }
    setFlash(`${n} productos enviados a ocultar en la tienda (se aplican en ~1 minuto).${err ? ` Error: ${err}` : ''}`); router.refresh();
  });
  const count = (f: HomologationStatus | 'todos') => (f === 'todos' ? s.variations : s[f]);

  return (
    <div>
      <h1 className="font-display text-5xl text-ink">Homologación</h1>
      <p className="mt-2 max-w-3xl text-ink-2">
        En la tienda en línea cada color es un producto aparte (<i>Paula negro</i>, <i>Paula nude</i>…). En Fuxia 360 es <b>un modelo con colores</b> (<i>Paula → Negro, Nude…</i>).
        Aquí le dices a Fuxia 360 a qué modelo y color corresponde cada producto de la tienda.
      </p>
      <p className="mt-1 text-sm text-muted">Tienda: {data.target.name}. Esto no mueve inventario ni cambia nada en la tienda.</p>

      <ol className="mt-5 grid gap-3 rounded-2xl border border-line bg-surface p-4 text-sm text-ink-2 md:grid-cols-3" data-testid="how-to">
        <li><b className="text-ink">1 · Abre un modelo.</b> Fuxia 360 ya propone el modelo y el color de cada producto de la tienda.</li>
        <li><b className="text-ink">2 · Si está bien, confirma.</b> Las tallas se toman solas. Si un color está mal, corrígelo antes de confirmar.</li>
        <li><b className="text-ink">3 · Si no sabes qué es,</b> usa <i>Marcar… → Requiere revisión</i> y escribe por qué. Nadie lo cambia sin ti.</li>
      </ol>

      <div className="mt-5" data-testid="progress">
        <div className="flex items-baseline justify-between text-sm"><span className="text-ink">Avance: <b className="tabular">{nDecided}</b> de <span className="tabular">{s.variations}</span> tallas decididas · {s.confirmado} confirmadas, {nDiscarded} marcadas “no existe”</span><span className="tabular text-muted">{pctDecided}%</span></div>
        <div className="mt-1.5 h-2 overflow-hidden rounded-full bg-surface-2"><div className="h-full rounded-full bg-success" style={{ width: `${pctDecided}%` }} /></div>
      </div>

      <div className="mt-6 grid grid-cols-2 gap-3 sm:grid-cols-4" data-testid="homologation-summary">
        <Stat label="Variaciones Woo" value={s.variations} sub={`${s.woo_products} productos Woo`} />
        <Stat label="Modelos F360 propuestos" value={s.models_proposed} sub={`${s.models_confirmed} con algo confirmado`} />
        <Stat label="Confirmadas" value={s.confirmado} sub={`${s.coverage_pct}% de cobertura`} tone="text-success" />
        <Stat label="Falta tu decisión" value={nPending - s.propuesto} sub={`${s.propuesto} listas para confirmar`} tone={s.conflicto ? 'text-danger' : undefined} />
      </div>

      <div className="mt-6 flex flex-wrap items-center gap-2">
        {FILTERS.map((f) => (
          <button key={f} type="button" onClick={() => setFilter(f)} data-testid={`filter-${f}`}
            className={`rounded-full px-4 py-2 text-sm ${filter === f ? 'bg-ink text-surface' : 'bg-surface text-ink-2 ring-1 ring-line'}`}>
            {f === 'todos' ? 'Todas' : LABEL[f]} <span className="tabular opacity-70">{count(f)}</span>
          </button>
        ))}
        <input aria-label="Buscar" value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Buscar modelo, producto Woo, SKU o variation ID"
          className="ml-auto w-full rounded-xl border border-line bg-surface px-3 py-2 text-sm outline-none focus:border-gold sm:w-80" />
      </div>

      {noExiste.length > 0 && (
        <div className="mt-6 flex flex-wrap items-center gap-3 rounded-2xl border border-line bg-surface p-4" data-testid="no-existe-panel">
          <p className="flex-1 text-sm text-ink-2"><b>{noExiste.length} productos de la tienda</b> se marcaron “no existe”. Siguen publicados en la tienda: {noExiste.filter((u) => hidden(u.wooProductId)).length} ya ocultos.
            Ocultarlos los deja como <i>privados</i> en Woo (no se borran y se pueden volver a mostrar).</p>
          {toHide.length > 0 && <button type="button" disabled={hiding} onClick={hideAll} className="rounded-full bg-ink px-4 py-2 text-sm text-surface disabled:opacity-40">{hiding ? 'Enviando…' : `Ocultar de la tienda (${toHide.length})`}</button>}
        </div>
      )}
      {flash && <p className="mt-4 rounded-xl bg-success-soft px-4 py-3 text-sm text-success" role="status" data-testid="flash">{flash}</p>}

      <div className="mt-6 grid gap-4">
        {visible.length === 0 && <p className="rounded-2xl border border-line bg-surface p-6 text-muted">Nada con ese filtro.</p>}
        {visible.map((g) => <GroupCard key={g.key} g={g} data={data} onDone={setFlash} vis={vis} />)}
      </div>
    </div>
  );
}

function Stat({ label, value, sub, tone }: { label: string; value: number; sub: string; tone?: string }) {
  return (
    <div className="rounded-2xl border border-line bg-surface p-4">
      <div className="text-xs uppercase tracking-wider text-muted">{label}</div>
      <div className={`tabular mt-1 text-3xl ${tone ?? 'text-ink'}`}>{value}</div>
      <div className="text-xs text-muted">{sub}</div>
    </div>
  );
}

function Badge({ status }: { status: HomologationStatus | 'mixto' }) {
  if (status === 'mixto') return <span className="rounded-full bg-surface-2 px-2.5 py-1 text-xs text-ink-2">Mixto</span>;
  return <span className={`whitespace-nowrap rounded-full px-2.5 py-1 text-xs ${TONE[status]}`}>{LABEL[status]}</span>;
}

function GroupCard({ g, data, onDone, vis }: { g: Group; data: Homologation; onDone: (text: string) => void; vis: Map<number, Vis> }) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [expanded, setExpanded] = useState<string | null>(null);
  const pendingUnits = g.units.filter((u) => u.rows.some((r) => !decided(r)));
  const existing = data.models.filter((m) => !m.published);
  const firstCat = g.units[0]?.category?.split('|')[0] ?? '';
  const [mode, setMode] = useState<'new' | 'existing'>(g.proposedProductId ? 'existing' : 'new');
  const [productId, setProductId] = useState<string>(g.proposedProductId ?? '');
  const [newName, setNewName] = useState(g.proposedProductId ? '' : g.name);
  const [category, setCategory] = useState(data.categories.some((c) => c.key === firstCat) ? firstCat : '');
  const [sel, setSel] = useState<Record<string, { on: boolean; color: string }>>({});
  const [action, setAction] = useState<{ unit: Unit; kind: 'requiere_revision' | 'sin_correspondencia' | 'reopen' } | null>(null);
  const [reason, setReason] = useState('');
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);
  const [pending, start] = useTransition();

  const openPanel = () => {
    setMsg(null); setOpen(!open);
    setSel(Object.fromEntries(pendingUnits.map((u) => [u.key, {
      on: u.rows.every((r) => r.status === 'propuesto'),
      color: u.wooColor ?? (u.rows.some((r) => r.proposed_color) ? u.detectedColor ?? '' : ''),
    }])));
  };
  const chosen = pendingUnits.filter((u) => sel[u.key]?.on);
  const modelLabel = mode === 'existing' ? existing.find((m) => m.id === productId)?.name ?? '…' : newName.trim() || '…';

  const confirm = () => start(async () => {
    setMsg(null);
    let pid: string | null = mode === 'existing' ? productId || null : null;
    if (mode === 'existing' && !pid) { setMsg({ ok: false, text: 'Elige el modelo F360.' }); return; }
    let done = 0;
    for (const u of chosen) {
      const color = sel[u.key]?.color.trim() ?? '';
      if (!color) { setMsg({ ok: false, text: `Escribe el color F360 de "${u.wooProductName}${u.wooColor ? ` · ${u.wooColor}` : ''}".` }); break; }
      const r = await confirmHomologationAction({ target: data.target.key, variationIds: u.rows.filter((x) => x.status !== 'confirmado').map((x) => x.woo_variation_id),
        productId: pid, newModelName: pid ? null : newName, categoryKey: category || null, color });
      if (!r.ok) { setMsg({ ok: false, text: `${u.wooProductName}: ${r.error}` }); break; }
      pid = r.data.product_id; done++;
    }
    if (done && pid) {
      const head = `${done} producto${done === 1 ? '' : 's'} de la tienda confirmado${done === 1 ? '' : 's'} en ${modelLabel}.`;
      onDone(`${head} Trayendo fotos, precio y descripción de la tienda…`);
      const imp = await runStoreImport(pid, (t) => onDone(`${head} ${t}`));
      onDone(`${head} ${imp.ok ? imp.text : `No se pudieron traer los datos de la tienda: ${imp.error}`}`);
      router.refresh();
    }
    if (done === chosen.length) setOpen(false);
  });

  const runAction = () => start(async () => {
    if (!action) return;
    const ids = action.unit.rows.filter((r) => (action.kind === 'reopen' ? r.status === 'confirmado' : r.status !== 'confirmado')).map((r) => r.woo_variation_id);
    const r = action.kind === 'reopen' ? await reopenHomologationAction(data.target.key, ids, reason) : await markHomologationAction(data.target.key, ids, action.kind, reason);
    if (!r.ok) { setMsg({ ok: false, text: r.error }); return; }
    const what = action.kind === 'reopen' ? 'reabierto' : `marcado “${LABEL[action.kind]}”`;
    setAction(null); setReason(''); setMsg(null); onDone(`${action.unit.wooProductName}${action.unit.wooColor ? ` · ${action.unit.wooColor}` : ''}: ${what}.`); router.refresh();
  });

  const counts = g.units.flatMap((u) => u.rows).reduce<Record<string, number>>((m, r) => ((m[r.status] = (m[r.status] ?? 0) + 1), m), {});

  return (
    <section className="rounded-3xl border border-line bg-surface" data-testid={`group-${g.key}`}>
      <header className="flex flex-wrap items-center gap-3 px-5 py-4">
        <div className="flex-1">
          <div className="text-xs uppercase tracking-wider text-muted">{pendingUnits.length ? 'Modelo propuesto por Fuxia 360' : 'Modelo confirmado'}</div>
          <h2 className="font-display text-3xl text-ink">{g.name}</h2>
          <div className="text-sm text-muted">{g.units.length} {g.units.length === 1 ? 'producto de la tienda' : 'productos de la tienda'} = {g.units.length} {g.units.length === 1 ? 'color' : 'colores'} de este modelo</div>
        </div>
        <div className="flex flex-wrap gap-1.5">{Object.entries(counts).map(([k, n]) => <span key={k} className={`rounded-full px-2.5 py-1 text-xs ${TONE[k as HomologationStatus]}`}>{LABEL[k as HomologationStatus]} {n}</span>)}</div>
        {pendingUnits.length > 0 && (
          <button type="button" onClick={openPanel} className="rounded-2xl bg-ink px-4 py-2.5 text-sm text-surface">{open ? 'Cerrar' : priority(g) === 0 ? 'Revisar y confirmar' : 'Decidir'}</button>
        )}
      </header>

      {open && (
        <div className="border-t border-line bg-bg/60 px-5 py-5" data-testid="confirm-panel">
          <div className="grid gap-4 md:grid-cols-[1fr_1fr]">
            <div>
              <div className="text-sm font-medium text-ink">1 · ¿A qué modelo F360 pertenecen?</div>
              <label className="mt-2 flex items-center gap-2 text-sm text-ink-2"><input type="radio" checked={mode === 'new'} onChange={() => setMode('new')} />Modelo nuevo</label>
              {mode === 'new' && (
                <div className="mt-2 grid gap-2 sm:grid-cols-2">
                  <input aria-label="Nombre del modelo" value={newName} onChange={(e) => setNewName(e.target.value)} className="rounded-xl border border-line bg-surface px-3 py-2.5 outline-none focus:border-gold" />
                  <select aria-label="Categoría" value={category} onChange={(e) => setCategory(e.target.value)} className="rounded-xl border border-line bg-surface px-3 py-2.5">
                    <option value="">Sin categoría</option>{data.categories.map((c) => <option key={c.key} value={c.key}>{c.name}</option>)}
                  </select>
                </div>
              )}
              <label className="mt-3 flex items-center gap-2 text-sm text-ink-2"><input type="radio" checked={mode === 'existing'} onChange={() => setMode('existing')} />Un modelo F360 que ya existe (agrupar)</label>
              {mode === 'existing' && (
                <select aria-label="Modelo existente" value={productId} onChange={(e) => setProductId(e.target.value)} className="mt-2 w-full rounded-xl border border-line bg-surface px-3 py-2.5">
                  <option value="">Elige un modelo…</option>
                  {existing.map((m) => <option key={m.id} value={m.id}>{m.name}{m.colors.length ? ` — ${m.colors.join(', ')}` : ''}</option>)}
                </select>
              )}
            </div>
            <div>
              <div className="text-sm font-medium text-ink">2 · Productos Woo y su color F360</div>
              <p className="mt-1 text-xs text-muted">Cada producto Woo es un color del modelo. Las tallas se toman de Woo. Si no estás segura del color, no lo confirmes: márcalo “Requiere revisión”.</p>
              <div className="mt-2 grid gap-2">
                {pendingUnits.map((u) => (
                  <div key={u.key} className="rounded-xl border border-line bg-surface px-3 py-2">
                    <div className="flex flex-wrap items-center gap-2">
                      <input type="checkbox" aria-label={`Incluir ${u.wooProductName}${u.wooColor ? ` ${u.wooColor}` : ''}`} checked={sel[u.key]?.on ?? false}
                        onChange={(e) => setSel({ ...sel, [u.key]: { ...(sel[u.key] ?? { color: '' }), on: e.target.checked } })} />
                      <span className="flex-1 text-sm text-ink">{u.wooProductName}{u.wooColor ? <span className="text-muted"> · {u.wooColor}</span> : u.rows[0].status === 'requiere_revision' && !u.rows[0].proposed_color ? <span className="text-danger"> · color no determinado</span> : null}</span>
                      <input aria-label={`Color F360 de ${u.wooProductName}${u.wooColor ? ` ${u.wooColor}` : ''}`} value={sel[u.key]?.color ?? ''} placeholder="Color F360"
                        onChange={(e) => setSel({ ...sel, [u.key]: { ...(sel[u.key] ?? { on: true }), color: e.target.value, on: true } })}
                        className="w-40 rounded-lg border border-line bg-surface px-2 py-1.5 text-sm outline-none focus:border-gold" />
                    </div>
                    {u.rows[0].proposal_reason && u.rows[0].status !== 'propuesto' && <p className="mt-1 text-xs text-muted">{u.rows[0].proposal_reason}</p>}
                  </div>
                ))}
              </div>
            </div>
          </div>
          {msg && <p className={`mt-4 rounded-xl px-4 py-3 text-sm ${msg.ok ? 'bg-success-soft text-success' : 'bg-danger-soft text-danger'}`}>{msg.text}</p>}
          <button type="button" disabled={pending || !chosen.length} onClick={confirm} className="mt-4 rounded-2xl bg-ink px-5 py-3 text-surface disabled:opacity-40">
            {pending ? 'Confirmando…' : `Confirmar ${chosen.length} ${chosen.length === 1 ? 'producto Woo' : 'productos Woo'} como ${modelLabel}`}
          </button>
        </div>
      )}

      <div className="overflow-x-auto border-t border-line">
        <table className="w-full min-w-[760px] text-sm">
          <thead className="text-left text-xs uppercase tracking-wider text-muted">
            <tr className="border-b border-line">
              <th className="px-5 py-2 font-normal">En la tienda</th><th className="px-3 py-2 font-normal">En Fuxia 360</th>
              <th className="px-3 py-2 font-normal">Estado</th><th className="px-3 py-2 font-normal">Qué falta</th><th className="px-3 py-2" />
            </tr>
          </thead>
          <tbody>
            {g.units.map((u) => {
              const c = u.rows.find((r) => r.confirmed)?.confirmed;
              const conf = u.rows[0].confidence;
              return (
                <Fragment key={u.key}>
                  <tr className="border-b border-line align-top" data-testid={`unit-${u.wooProductId}${u.wooColor ? `-${u.wooColor}` : ''}`}>
                    <td className="px-5 py-3"><div className="text-ink">{u.wooProductName}{u.wooColor ? <span className="text-muted"> · {u.wooColor}</span> : null}</div>
                      <button type="button" onClick={() => setExpanded(expanded === u.key ? null : u.key)} className="mt-0.5 text-xs text-muted underline decoration-line underline-offset-4">
                        {expanded === u.key ? 'Ocultar detalle' : `Ver detalle · tallas ${u.rows[0].woo_size}–${u.rows[u.rows.length - 1].woo_size}`}</button></td>
                    <td className="px-3 py-3 text-ink">{c ? <>{c.product_name} · <b>{c.color}</b></>
                      : <span className="text-ink-2">{u.rows[0].proposed_model ?? '—'} · {u.rows[0].proposed_color ? <b>{u.rows[0].proposed_color}</b> : <span className="text-danger">color sin definir</span>}</span>}</td>
                    <td className="px-3 py-3"><div className="flex flex-col items-start gap-1"><Badge status={u.status} />{conf && u.status !== 'confirmado' && <span className="text-xs text-muted">confianza {conf}</span>}</div></td>
                    <td className="max-w-xs px-3 py-3 text-ink-2">{todo(u)}</td>
                    <td className="px-3 py-3 text-right">
                      {isNoExiste(u) && <StoreVisibility target={data.target.key} unit={u} v={vis.get(u.wooProductId)} onDone={onDone} />}
                      {u.rows.some((r) => r.status === 'confirmado')
                        ? <button type="button" onClick={() => { setAction({ unit: u, kind: 'reopen' }); setReason(''); }} className="text-xs text-muted underline">Reabrir</button>
                        : <select aria-label={`Marcar ${u.wooProductName}`} value="" onChange={(e) => { setAction({ unit: u, kind: e.target.value as 'requiere_revision' | 'sin_correspondencia' }); setReason(''); }}
                            className="rounded-lg border border-line bg-surface px-2 py-1 text-xs text-ink-2">
                            <option value="">Marcar…</option><option value="requiere_revision">Requiere revisión</option><option value="sin_correspondencia">Sin correspondencia</option>
                          </select>}
                    </td>
                  </tr>
                  {action?.unit.key === u.key && (
                    <tr className="border-b border-line bg-bg/60"><td colSpan={5} className="px-5 py-3">
                      <div className="flex flex-wrap items-center gap-2">
                        <span className="text-sm text-ink">{action.kind === 'reopen' ? 'Reabrir: ¿por qué?' : `${LABEL[action.kind]}: motivo`}</span>
                        <input aria-label="Motivo" value={reason} onChange={(e) => setReason(e.target.value)} className="min-w-64 flex-1 rounded-lg border border-line bg-surface px-3 py-2 text-sm outline-none focus:border-gold" />
                        <button type="button" disabled={pending} onClick={runAction} className="rounded-xl bg-ink px-4 py-2 text-sm text-surface disabled:opacity-40">Guardar</button>
                        <button type="button" onClick={() => setAction(null)} className="text-sm text-muted">Cancelar</button>
                      </div>
                    </td></tr>
                  )}
                  {expanded === u.key && (
                    <tr className="border-b border-line bg-bg/40"><td colSpan={5} className="px-5 py-3">
                      <table className="w-full text-xs" data-testid={`variations-${u.wooProductId}`}>
                        <thead className="text-left text-muted"><tr><th className="py-1 font-normal">variation_id (Woo)</th><th className="font-normal">Talla Woo</th><th className="font-normal">Color Woo</th><th className="font-normal">Producto F360</th><th className="font-normal">Color F360</th><th className="font-normal">Talla F360</th><th className="font-normal">Vendidos (90 d / total)</th><th className="font-normal">Estado</th><th className="font-normal">SKU F360</th><th className="font-normal">Decidió</th></tr></thead>
                        <tbody>{u.rows.map((r) => (
                          <tr key={r.woo_variation_id} className="border-t border-line">
                            <td className="tabular py-1.5">{r.woo_variation_id}</td><td>{r.woo_size}</td><td>{r.woo_color ?? '—'}</td>
                            <td>{r.confirmed?.product_name ?? r.proposed_model ?? '—'}</td><td>{r.confirmed?.color ?? r.proposed_color ?? '—'}</td><td>{r.confirmed?.size ?? r.proposed_size ?? '—'}</td>
                            <td className="tabular">{r.sold_90d} / {r.sold_all}</td><td><Badge status={r.status} /></td><td>{r.confirmed?.sku ?? '—'}</td>
                            <td>{r.decided_by_name ? `${r.decided_by_name}${r.note ? ` — ${r.note}` : ''}` : '—'}</td>
                          </tr>))}
                        </tbody>
                      </table>
                      {u.sku && <p className="mt-2 text-xs text-muted">SKU de la tienda (solo referencia, no se cambia): {u.sku}</p>}
                      {u.rows[0].proposal_reason && <p className="mt-1 text-xs text-muted">Por qué lo propuso Fuxia 360: {u.rows[0].proposal_reason}</p>}
                    </td></tr>
                  )}
                </Fragment>
              );
            })}
          </tbody>
        </table>
      </div>
      {!open && msg && <p className={`mx-5 my-3 rounded-xl px-4 py-2 text-sm ${msg.ok ? 'bg-success-soft text-success' : 'bg-danger-soft text-danger'}`}>{msg.text}</p>}
    </section>
  );
}

function StoreVisibility({ target, unit, v, onDone }: { target: string; unit: Unit; v: Vis | undefined; onDone: (t: string) => void }) {
  const router = useRouter();
  const [pending, start] = useTransition();
  const ask = (kind: 'ocultar' | 'mostrar') => start(async () => {
    const r = await storeVisibilityAction(target, unit.wooProductId, kind, kind === 'ocultar' ? 'Marcado “no existe” en Homologación' : 'Se vuelve a mostrar');
    onDone(r.ok ? `${unit.wooProductName}: ${kind === 'ocultar' ? 'se ocultará' : 'se volverá a mostrar'} en la tienda en ~1 minuto.` : r.error); router.refresh();
  });
  if (v?.pending) return <span className="mb-1 block text-xs text-muted">{v.pending === 'ocultar' ? 'Ocultándose en la tienda…' : 'Mostrándose en la tienda…'}</span>;
  const isHidden = v?.last?.kind === 'ocultar' && v.last.status === 'hecho';
  return (
    <div className="mb-1 text-xs">
      {v?.last?.status === 'error' && <span className="block text-danger">No se pudo: {v.last.error}</span>}
      {isHidden
        ? <span className="text-success">Oculto en la tienda · <button type="button" disabled={pending} onClick={() => ask('mostrar')} className="text-muted underline">Volver a mostrar</button></span>
        : <button type="button" disabled={pending} onClick={() => ask('ocultar')} className="rounded-full border border-line px-3 py-1 text-ink-2">Ocultar de la tienda</button>}
    </div>
  );
}
