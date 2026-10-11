import Link from 'next/link';
import { MissingList, Missing, PartialNote, Seal, SourceInfo } from '@/components/IntelUi';
import {
  CHANNEL, MARKET, dayLabel, getCockpit, money, monthLabel, num, rateSentence, signed, when,
  type Block, type BudgetLine, type Card, type Consolidado, type Disponibilidad, type Meta, type Sales,
} from '@/lib/intel';

// Dirección · CEO Cockpit (I2, design §4). The 8 cards come from ONE call (f360_intel_cockpit) — the same layer the analyst
// reads. This page formats and lays out; it never adds, converts or projects a number. A block whose meta says FALTA shows no
// figure, only what is missing, why and who provides it.
export const dynamic = 'force-dynamic';

type SP = { semana?: string; moneda?: string };
const ISO = /^\d{4}-\d{2}-\d{2}$/;
const addDays = (iso: string, d: number) => { const t = new Date(`${iso}T12:00:00Z`); t.setUTCDate(t.getUTCDate() + d); return t.toISOString().slice(0, 10); };
const todayMx = () => new Date().toLocaleDateString('en-CA', { timeZone: 'America/Mexico_City' });
const seg = (m: string, c: string) => `${MARKET[m] ?? m} · ${CHANNEL[c] ?? c}`;

const card = 'flex min-w-0 flex-col gap-3 rounded-2xl border border-line bg-surface p-4 sm:p-5';
const big = 'font-display text-3xl leading-tight text-ink sm:text-4xl';

function CardHead({ n, title, d }: { n: number; title: string; d: Disponibilidad }) {
  return (
    <div className="flex items-start justify-between gap-2">
      <h2 className="font-semibold text-ink"><span className="mr-1.5 text-muted">{n}</span>{title}</h2>
      <Seal d={d} testId={`seal-${n}`} />
    </div>
  );
}

function Rates({ c }: { c: Consolidado }) {
  if (!c.tasas.length && !c.sin_tasa.length) return <p className="text-xs text-muted">Todo en pesos: no hizo falta tipo de cambio.</p>;
  return (
    <ul className="text-xs text-ink-2">
      {c.tasas.map((t, i) => (
        <li key={i}>{monthLabel(t.mes)}: {rateSentence(t.moneda, Number(t.tasa))}{t.estado === 'provisional' ? ' · tasa provisional (mes en curso)' : t.estado === 'approved' ? ' · tasa aprobada' : ''}</li>
      ))}
      {c.sin_tasa.map((t, i) => <li key={`s${i}`} className="text-danger">{t.moneda} de {monthLabel(t.mes)}: sin tasa aprobada, no se convierte</li>)}
    </ul>
  );
}

function Consolidated({ c }: { c: Consolidado | null }) {
  if (!c) return null;
  return (
    <div className="rounded-xl bg-surface-2 px-3 py-2" data-testid="consolidado">
      {c.mxn !== null
        ? <p className="text-sm text-ink">Consolidado: <b className="tabular-nums">{money(c.mxn, 'MXN')}</b></p>
        : <p className="text-sm text-ink-2">Sin consolidado: falta un tipo de cambio aprobado.</p>}
      <Rates c={c} />
    </div>
  );
}

function SalesBlock({ label, b, mxn }: { label: string; b: Block<Sales>; mxn: boolean }) {
  return (
    <div className="flex flex-col gap-2">
      <div className="flex items-center justify-between gap-2">
        <h3 className="text-xs font-bold uppercase tracking-[0.18em] text-muted">{label}</h3>
        <Seal d={b.meta.disponibilidad} />
      </div>
      {b.meta.disponibilidad === 'FALTA' ? <Missing meta={b.meta} /> : (<>
        {b.data.por_mercado_canal.length === 0 && <p className="text-sm text-muted">Sin pedidos pagados en el periodo.</p>}
        {b.data.por_mercado_canal.map((r) => (
          <div key={`${r.mercado}${r.canal}`} className="flex flex-col gap-0.5">
            <div className="flex flex-wrap items-baseline justify-between gap-x-3">
              <span className="text-sm text-ink-2">{seg(r.mercado, r.canal)}</span>
              <span className="font-display text-2xl tabular-nums text-ink">{money(r.venta_neta, r.moneda)}</span>
            </div>
            <p className="text-xs text-muted">{r.pedidos_pagados} pedidos pagados · {r.pares} pares · ticket {money(r.ticket_promedio, r.moneda)}
              {r.anterior && <> · periodo anterior {money(r.anterior.venta_neta, r.moneda)} ({r.anterior.pedidos_pagados} pedidos)</>}</p>
            {r.explicacion_cambio && (
              <p className="text-xs text-ink-2" title={r.explicacion_cambio.formula}>
                Cambio {signed(r.explicacion_cambio.cambio_venta, r.moneda)}: {signed(r.explicacion_cambio.por_pedidos, r.moneda)} por número de pedidos y {signed(r.explicacion_cambio.por_ticket, r.moneda)} por ticket promedio.
              </p>
            )}
          </div>
        ))}
        {mxn && <Consolidated c={b.data.consolidado_mxn} />}
        <PartialNote meta={b.meta} />
        {b.data.excluidas_por_conciliacion.length > 0 && (
          <p className="text-xs text-ink-2">Aparte, excluidas por Conciliación (no restadas): {b.data.excluidas_por_conciliacion.map((x) => `${MARKET[x.mercado] ?? x.mercado} ${x.pedidos} pedidos ${money(x.venta_neta, x.moneda)}`).join(' · ')}</p>)}
        {b.data.moneda_por_conciliar.length > 0 && (
          <p className="text-xs text-danger">Moneda por conciliar (no se convierte): {b.data.moneda_por_conciliar.map((x) => `#${x.pedido} (${x.moneda})`).join(', ')}</p>)}
      </>)}
    </div>
  );
}

function BudgetBlock({ label, b }: { label: string; b: Block<{ lineas: BudgetLine[] }> }) {
  return (
    <div className="flex flex-col gap-1.5">
      <div className="flex items-center justify-between gap-2">
        <h3 className="text-xs font-bold uppercase tracking-[0.18em] text-muted">{label}</h3>
        <Seal d={b.meta.disponibilidad} />
      </div>
      {b.meta.disponibilidad === 'FALTA' ? <Missing meta={b.meta} /> : b.data.lineas.map((l) => (
        <p key={`${l.mercado}${l.canal}`} className="text-sm text-ink-2">
          {seg(l.mercado, l.canal)}: real <b className="tabular-nums text-ink">{money(l.real, l.moneda)}</b> de {money(l.presupuesto, l.moneda)}
          {l.cumplimiento_pct !== null && <> · {num(l.cumplimiento_pct, 1)}%</>} · brecha {signed(l.brecha, l.moneda)}
        </p>
      ))}
      {b.meta.disponibilidad !== 'FALTA' && <PartialNote meta={b.meta} />}
    </div>
  );
}

function C1({ c, mxn }: { c: Extract<Card, { id: 1 }>; mxn: boolean }) {
  const sales = [c.semana.meta, c.mes.meta];
  const d: Disponibilidad = sales.every((m) => m.disponibilidad === 'FALTA') ? 'FALTA'
    : [...sales, c.presupuesto_semana.meta, c.presupuesto_mes.meta].some((m) => m.disponibilidad !== 'DISPONIBLE') ? 'PARCIAL' : 'DISPONIBLE';
  return (
    <section className={card} data-testid="card-1">
      <CardHead n={1} title={c.titulo} d={d} />
      <SalesBlock label="Esta semana" b={c.semana} mxn={mxn} />
      <BudgetBlock label="Presupuesto de la semana" b={c.presupuesto_semana} />
      <div className="border-t border-line" />
      <SalesBlock label="Mes a la fecha" b={c.mes} mxn={mxn} />
      <BudgetBlock label="Presupuesto del mes" b={c.presupuesto_mes} />
      <SourceInfo meta={c.semana.meta} />
    </section>
  );
}

function C2({ c }: { c: Extract<Card, { id: 2 }> }) {
  const { data: g, meta } = c.valor;
  return (
    <section className={card} data-testid="card-2">
      <CardHead n={2} title={c.titulo} d={meta.disponibilidad} />
      {meta.disponibilidad === 'FALTA' ? <Missing meta={meta} /> : (<>
        <div data-testid="goal-300k">
          <p className={big}><span className="tabular-nums">{money(g.real_al_dia, g.moneda)}</span></p>
          <p className="text-sm text-ink-2">de la meta de <b className="tabular-nums text-ink">{money(g.meta, g.moneda)}</b> · {g.meta_nombre ?? seg(g.mercado, g.canal)}</p>
        </div>
        <div>
          <div className="h-2.5 overflow-hidden rounded-full bg-surface-2" role="progressbar" aria-valuenow={g.avance_pct ?? 0} aria-valuemin={0} aria-valuemax={100}>
            <div className="h-full rounded-full bg-gold" style={{ width: `${Math.min(100, Math.max(0, g.avance_pct ?? 0))}%` }} />
          </div>
          <p className="mt-1 text-sm text-ink-2"><b className="text-ink">{num(g.avance_pct, 1)}% de avance</b> · faltan {money(g.faltante, g.moneda)} · día {g.dias_transcurridos} del mes, quedan {g.dias_restantes}</p>
        </div>
        <dl className="grid grid-cols-2 gap-2 text-sm">
          <div className="rounded-xl bg-surface-2 p-3"><dt className="text-xs text-muted">Ritmo necesario por día</dt><dd className="font-semibold tabular-nums text-ink">{money(g.ritmo_necesario_diario, g.moneda)}</dd></div>
          <div className="rounded-xl bg-surface-2 p-3"><dt className="text-xs text-muted">Ritmo actual por día</dt><dd className="font-semibold tabular-nums text-ink">{money(g.ritmo_actual_diario, g.moneda)}</dd></div>
          <div className="rounded-xl bg-surface-2 p-3"><dt className="text-xs text-muted">Mejor mes de los últimos 12</dt>
            <dd className="font-semibold tabular-nums text-ink">{g.mejor_mes_ultimos_12 ? <>{money(g.mejor_mes_ultimos_12.venta_neta, g.moneda)} <span className="font-normal text-muted">({monthLabel(g.mejor_mes_ultimos_12.mes)})</span></> : '—'}</dd></div>
          <div className="rounded-xl bg-surface-2 p-3"><dt className="text-xs text-muted">Proyección por ritmo <span className="text-amber-900">(cálculo, no pronóstico)</span></dt>
            <dd className="font-semibold tabular-nums text-ink">{money(g.proyeccion_por_ritmo, g.moneda)}</dd></div>
        </dl>
        {g.historial_12_meses.length > 0 && (
          <p className="text-xs text-muted">Historial: {g.historial_12_meses.map((h) => `${monthLabel(h.mes)} ${money(h.venta_neta, g.moneda)}`).join(' · ')}</p>)}
        <PartialNote meta={meta} />
      </>)}
      <SourceInfo meta={meta} extra={g?.formulas && (
        <ul className="mt-2 text-ink-2">{Object.entries(g.formulas).map(([k, v]) => <li key={k}>{k.replace(/_/g, ' ')}: {v}</li>)}{g.meta_motivo && <li>Meta: {g.meta_motivo}</li>}</ul>)} />
    </section>
  );
}

function C3({ c, mxn }: { c: Extract<Card, { id: 3 }>; mxn: boolean }) {
  const { data, meta } = c.valor;
  return (
    <section className={card} data-testid="card-3">
      <CardHead n={3} title={c.titulo} d={meta.disponibilidad} />
      {meta.disponibilidad === 'FALTA' ? <Missing meta={meta} /> : (<>
        <p className="text-xs text-muted">Mes a la fecha · moneda original de cada mercado</p>
        <ul className="flex flex-col divide-y divide-line">
          {data.por_mercado_canal.map((r) => (
            <li key={`${r.mercado}${r.canal}`} className="flex flex-col gap-0.5 py-2">
              <div className="flex flex-wrap items-baseline justify-between gap-x-3">
                <span className="font-medium text-ink">{seg(r.mercado, r.canal)}</span>
                <span className="tabular-nums text-ink">{money(r.venta_neta, r.moneda)}</span>
              </div>
              <span className="text-xs text-muted">{r.pedidos_pagados} pedidos · {r.pares} pares · ticket {money(r.ticket_promedio, r.moneda)}{r.anterior ? ` · antes ${money(r.anterior.venta_neta, r.moneda)}` : ''}</span>
            </li>
          ))}
          {data.por_mercado_canal.length === 0 && <li className="py-2 text-sm text-muted">Sin pedidos pagados en el periodo.</li>}
        </ul>
        {mxn && <Consolidated c={data.consolidado_mxn} />}
        <PartialNote meta={meta} />
      </>)}
      <SourceInfo meta={meta} />
    </section>
  );
}

function C4({ c }: { c: Extract<Card, { id: 4 }> }) {
  const { data, meta } = c.valor;
  return (
    <section className={card} data-testid="card-4">
      <CardHead n={4} title={c.titulo} d={meta.disponibilidad} />
      {meta.disponibilidad === 'FALTA' ? <Missing meta={meta} /> : (<>
        <p className="text-sm text-ink-2">Pares vendidos con costo aprobado: <b className="text-ink">{num(data.cobertura_costo_pct, 1)}%</b></p>
        {data.nota && <p className="text-sm text-ink-2">{data.nota}</p>}
        <PartialNote meta={meta} />
      </>)}
      <SourceInfo meta={meta} />
    </section>
  );
}

function C5({ c, mxn }: { c: Extract<Card, { id: 5 }> ; mxn: boolean }) {
  const { data, meta } = c.valor;
  return (
    <section className={card} data-testid="card-5">
      <CardHead n={5} title={c.titulo} d={meta.disponibilidad} />
      {meta.disponibilidad === 'FALTA' ? <Missing meta={meta} /> : (<>
        {data.por_mercado.map((r) => (
          <div key={r.mercado} className="flex flex-col gap-1.5">
            <h3 className="text-xs font-bold uppercase tracking-[0.18em] text-muted">{MARKET[r.mercado] ?? r.mercado}</h3>
            <dl className="grid grid-cols-2 gap-2 text-sm sm:grid-cols-3">
              <div><dt className="text-xs text-muted">Inversión</dt><dd className="tabular-nums text-ink">{r.inversion?.monto != null ? money(r.inversion.monto, r.inversion.moneda) : 'sin gasto registrado'}</dd></div>
              <div><dt className="text-xs text-muted">Venta neta</dt><dd className="tabular-nums text-ink">{r.venta_neta ? money(r.venta_neta.monto, r.venta_neta.moneda) : '—'}</dd></div>
              <div><dt className="text-xs text-muted">MER</dt><dd className="tabular-nums text-ink">{r.mer === null ? '—' : num(r.mer, 2)}</dd></div>
              <div><dt className="text-xs text-muted">CPA</dt><dd className="tabular-nums text-ink">{money(r.cpa_mxn, 'MXN')}</dd></div>
              <div><dt className="text-xs text-muted">CAC</dt><dd className="tabular-nums text-ink">{money(r.cac_mxn, 'MXN')}</dd></div>
              <div><dt className="text-xs text-muted">Pedidos · clientas nuevas</dt><dd className="tabular-nums text-ink">{r.pedidos_pagados} · {r.clientas_nuevas}</dd></div>
            </dl>
            {r.pedidos_sin_identidad > 0 && <p className="text-xs text-muted">{r.pedidos_sin_identidad} pedidos de invitada sin cuenta (no cuentan para CAC).</p>}
            {mxn && (
              <div className="rounded-xl bg-surface-2 px-3 py-2 text-xs text-ink-2">
                En pesos: inversión {r.inversion_mxn?.mxn != null ? money(r.inversion_mxn.mxn, 'MXN') : 'sin tasa'} · venta {r.venta_neta_mxn?.mxn != null ? money(r.venta_neta_mxn.mxn, 'MXN') : 'sin tasa'}
                {r.venta_neta_mxn && <Rates c={r.venta_neta_mxn} />}
              </div>
            )}
            <p className="text-xs text-ink-2"><b>ROAS atribuido:</b> falta — {r.roas_atribuido.por_que}</p>
          </div>
        ))}
        {data.campanas_top.length > 0 && (
          <div><h3 className="text-xs font-bold uppercase tracking-[0.18em] text-muted">Campañas con más inversión</h3>
            <ul className="mt-1 text-xs text-ink-2">{data.campanas_top.slice(0, 5).map((k, i) => <li key={i} className="break-words">{k.campana} · {MARKET[k.mercado] ?? k.mercado} · {money(k.inversion, k.moneda)}</li>)}</ul></div>)}
        <p className="text-xs text-muted">Google Ads: {data.google_ads}</p>
        <PartialNote meta={meta} />
      </>)}
      <SourceInfo meta={meta} extra={data?.formulas && <ul className="mt-2 text-ink-2">{Object.entries(data.formulas).map(([k, v]) => <li key={k}>{k.toUpperCase()}: {v}</li>)}</ul>} />
    </section>
  );
}

function C6({ c }: { c: Extract<Card, { id: 6 }> }) {
  const { data, meta } = c.valor;
  return (
    <section className={card} data-testid="card-6">
      <CardHead n={6} title={c.titulo} d={meta.disponibilidad} />
      {meta.disponibilidad === 'FALTA' ? <Missing meta={meta} /> : (<>
        <p className={big}><span className="tabular-nums">{num(data.pares_total)}</span> <span className="text-lg text-ink-2">pares</span></p>
        <ul className="grid grid-cols-2 gap-x-3 gap-y-0.5 text-sm text-ink-2">
          {data.por_ubicacion.map((u) => <li key={u.ubicacion} className="flex justify-between gap-2"><span className="truncate">{u.ubicacion}</span><span className="tabular-nums">{u.pares}</span></li>)}
        </ul>
        <div className="text-sm">
          <p className="text-ink"><b>Baja salida:</b> {data.baja_salida.length} modelos sin ventas en {data.ventana_dias} días</p>
          {data.baja_salida.length > 0 && <p className="text-xs text-muted">{data.baja_salida.slice(0, 6).map((m) => `${m.modelo} (${m.pares})`).join(' · ')}{data.baja_salida.length > 6 ? ' …' : ''}</p>}
        </div>
        <div className="text-sm">
          <p className="text-ink"><b>Riesgo de agotarse:</b> {data.riesgo_agotarse.length} modelos</p>
          {data.riesgo_agotarse.length > 0 && <p className="text-xs text-muted">{data.riesgo_agotarse.map((m) => `${m.modelo} (${m.pares} pares, ${m.vendidos_periodo ?? 0} vendidos)`).join(' · ')}</p>}
        </div>
        {data.historial_ventas_desde && <p className="text-xs text-muted">Ventas medidas desde {dayLabel(data.historial_ventas_desde)}.</p>}
        <PartialNote meta={meta} />
      </>)}
      <SourceInfo meta={meta} extra={data?.formulas && <ul className="mt-2 text-ink-2">{Object.entries(data.formulas).map(([k, v]) => <li key={k}>{k.replace(/_/g, ' ')}: {v}</li>)}</ul>} />
    </section>
  );
}

function C7({ c }: { c: Extract<Card, { id: 7 }> }) {
  const { data, meta } = c.valor;
  return (
    <section className={card} data-testid="card-7">
      <CardHead n={7} title={c.titulo} d={meta.disponibilidad} />
      {meta.disponibilidad === 'FALTA' ? <Missing meta={meta} /> : (<>
        <p className="text-sm text-ink-2">Cierre de {monthLabel(data.mes)}{data.capturas_por_aprobar > 0 ? ` · ${data.capturas_por_aprobar} capturas por aprobar` : ''}</p>
        <ul className="flex flex-col gap-0.5 text-sm">
          {data.cierre_aprobado.map((e, i) => <li key={i} className="flex flex-wrap justify-between gap-x-3"><span className="text-ink-2">{e.cuenta}</span><span className="tabular-nums text-ink">{money(e.monto, e.moneda)}</span></li>)}
        </ul>
        {data.compromisos_90_dias.length > 0 && (
          <div className="text-sm"><h3 className="text-xs font-bold uppercase tracking-[0.18em] text-muted">Compromisos próximos 90 días</h3>
            {data.compromisos_90_dias.map((k) => <p key={k.moneda} className="text-ink-2"><b className="tabular-nums text-ink">{money(k.monto, k.moneda)}</b> · {k.compromisos} pagos · el próximo vence {dayLabel(k.proximo_vencimiento)}</p>)}</div>)}
        <PartialNote meta={meta} />
      </>)}
      <SourceInfo meta={meta} />
    </section>
  );
}

function C8({ c }: { c: Extract<Card, { id: 8 }> }) {
  const { data, meta } = c.valor;
  return (
    <section className={card} data-testid="card-8">
      <CardHead n={8} title={c.titulo} d={meta.disponibilidad} />
      {meta.disponibilidad === 'FALTA' ? <Missing meta={meta} /> : (<>
        <p className="text-xs text-muted">{monthLabel(data.mes)} · día {data.dias_transcurridos} de {data.dias_del_mes}</p>
        {data.lineas.map((l) => (
          <div key={`${l.mercado}${l.canal}`} className="flex flex-col gap-1">
            <h3 className="text-sm font-medium text-ink">{seg(l.mercado, l.canal)}</h3>
            <dl className="grid grid-cols-2 gap-2 text-sm">
              <div><dt className="text-xs text-muted">Real al día</dt><dd className="tabular-nums text-ink">{money(l.real_al_dia, l.moneda)}</dd></div>
              <div><dt className="text-xs text-muted">Proyección por ritmo (cálculo, no pronóstico)</dt><dd className="tabular-nums text-ink">{money(l.proyeccion_por_ritmo, l.moneda)}</dd></div>
              <div><dt className="text-xs text-muted">Brecha vs meta {l.meta !== null ? `(${money(l.meta, l.moneda)})` : ''}</dt><dd className="tabular-nums text-ink">{l.meta === null ? 'sin meta' : signed(l.brecha_vs_meta, l.moneda)}</dd></div>
              <div><dt className="text-xs text-muted">Brecha vs presupuesto</dt><dd className="tabular-nums text-ink">{l.presupuesto === null ? 'sin presupuesto aprobado' : signed(l.brecha_vs_presupuesto, l.moneda)}</dd></div>
            </dl>
          </div>
        ))}
        {!data.pronostico_formal && <p className="text-xs text-muted">No hay pronóstico formal publicado.</p>}
        <PartialNote meta={meta} />
      </>)}
      <SourceInfo meta={meta} />
    </section>
  );
}

function CardView({ c, mxn }: { c: Card; mxn: boolean }) {
  switch (c.id) {
    case 1: return <C1 c={c} mxn={mxn} />;
    case 2: return <C2 c={c} />;
    case 3: return <C3 c={c} mxn={mxn} />;
    case 4: return <C4 c={c} />;
    case 5: return <C5 c={c} mxn={mxn} />;
    case 6: return <C6 c={c} />;
    case 7: return <C7 c={c} />;
    case 8: return <C8 c={c} />;
  }
}

const fuenteCls = (e: string) => (e === 'DISPONIBLE' ? 'border-success/30 bg-success-soft' : e === 'PARCIAL' ? 'border-amber-300 bg-amber-50' : 'border-danger/30 bg-danger-soft');
const fuenteLabel = (e: string) => (e === 'DISPONIBLE' ? 'completa' : e === 'PARCIAL' ? 'parcial' : 'falta');

export default async function Direccion({ searchParams }: { searchParams: Promise<SP> }) {
  const sp = await searchParams;
  const mxn = sp.moneda === 'mxn';
  const week = sp.semana && ISO.test(sp.semana) ? sp.semana : undefined;
  const r = await getCockpit(week);
  if (!r.ok) return <p role="alert" className="rounded-xl bg-danger-soft px-4 py-3 text-sm text-danger">{r.error}</p>;
  const prev = addDays(r.semana.desde, -7);
  const next = addDays(r.semana.desde, 7);
  const q = (o: { semana?: string; moneda?: 'mxn' | '' }) => {
    const u = new URLSearchParams();
    const s = o.semana ?? week; if (s) u.set('semana', s);
    const m = o.moneda ?? (mxn ? 'mxn' : ''); if (m) u.set('moneda', m);
    const t = u.toString(); return `/direccion${t ? `?${t}` : ''}`;
  };
  const updated = (r.fuentes.meta as Meta).actualizado_al;
  return (
    <div className="flex min-w-0 flex-col gap-5">
      <header className="flex flex-col gap-3">
        <h1 className="font-display text-4xl text-ink sm:text-5xl">Dirección</h1>
        <div className="flex flex-wrap items-center gap-2">
          <Link href={q({ semana: prev })} className="rounded-full border border-line px-3 py-1.5 text-sm text-ink-2" aria-label="Semana anterior">←</Link>
          <span className="text-sm font-medium text-ink" data-testid="semana">Semana {dayLabel(r.semana.desde)} – {dayLabel(r.semana.hasta)}</span>
          {next <= todayMx() && <Link href={q({ semana: next })} className="rounded-full border border-line px-3 py-1.5 text-sm text-ink-2" aria-label="Semana siguiente">→</Link>}
          {week && <Link href={mxn ? '/direccion?moneda=mxn' : '/direccion'} className="text-xs text-muted underline">esta semana</Link>}
        </div>
        <div className="flex flex-wrap items-center justify-between gap-2">
          <div className="inline-flex rounded-full border border-line p-0.5 text-sm" role="group" aria-label="Moneda">
            <Link href={q({ moneda: '' })} aria-current={!mxn ? 'true' : undefined} className={`rounded-full px-3 py-1 ${!mxn ? 'bg-ink text-surface' : 'text-ink-2'}`}>Moneda original</Link>
            <Link href={q({ moneda: 'mxn' })} aria-current={mxn ? 'true' : undefined} className={`rounded-full px-3 py-1 ${mxn ? 'bg-ink text-surface' : 'text-ink-2'}`}>Consolidado MXN</Link>
          </div>
          <span className="text-xs text-muted">Mes: {dayLabel(r.mes.desde)} – {dayLabel(r.mes.hasta)} · actualizado {when(updated)}</span>
        </div>
        {mxn && <p className="text-xs text-muted">El consolidado solo usa tipo de cambio aprobado (o la tasa provisional del mes en curso, marcada). Lo que no tiene tasa no se convierte.</p>}
      </header>

      <div className="grid min-w-0 gap-4 md:grid-cols-2" data-testid="cockpit">
        {r.tarjetas.map((c) => <CardView key={c.id} c={c} mxn={mxn} />)}
      </div>

      <section className="rounded-2xl border border-line bg-surface p-4 sm:p-5" data-testid="fuentes">
        <h2 className="font-semibold text-ink">Fuentes</h2>
        <ul className="mt-3 flex flex-wrap gap-2">
          {r.fuentes.data.fuentes.map((f) => (
            <li key={f.fuente} className={`max-w-full rounded-xl border px-3 py-1.5 text-xs text-ink-2 ${fuenteCls(f.estado)}`}>
              <b className="text-ink">{f.fuente}</b> · {fuenteLabel(f.estado)}{f.falta ? ` · falta ${f.falta}` : ''}{f.quien ? ` · ${f.quien}` : ''}{f.desde ? ` · desde ${dayLabel(f.desde)}` : ''}{f.propuestas_pendientes ? ` · ${f.propuestas_pendientes} tasas por aprobar` : ''}
            </li>
          ))}
        </ul>
        {r.fuentes.meta.faltantes.length > 0 && <div className="mt-3"><MissingList items={r.fuentes.meta.faltantes} /></div>}
      </section>
    </div>
  );
}
