import Link from 'next/link';
import { redirect } from 'next/navigation';
import { canWrite, getMe, getOpeningSheet, getOpeningState, type OpeningView } from '@/lib/f360';
import { fecha } from '@/lib/format';
import { CountControls, CountSheet, StartCount, Unlisted } from './ConteoClient';

// Track D · D3 — physical opening count of Bodega CDMX (Model → Color → Size). Double count, blind count 2, recount,
// pairs without a model, freeze window, reconciliation, Mario's approval. Nothing here writes inventory.
const VIEWS: { key: OpeningView | 'sinficha'; label: string }[] = [
  { key: 'conteo1', label: '1 · Conteo' }, { key: 'conteo2', label: '2 · Segundo conteo (a ciegas)' }, { key: 'reconteo', label: 'Reconteo' },
  { key: 'sinficha', label: 'Pares sin ficha' }, { key: 'reporte', label: 'Reporte' },
];
const STATUS: Record<string, string> = { preliminar: 'Conteo preliminar', congelado: 'Bodega congelada', aprobado: 'Aprobado por Mario', cargado: 'Inventario inicial cargado', cancelado: 'Cancelado' };

export default async function Conteo({ searchParams }: { searchParams: Promise<{ vista?: string }> }) {
  const me = await getMe();
  if (!canWrite(me.role)) redirect('/');
  const owner = me.role === 'owner';
  const state = await getOpeningState();
  const c = state.count;
  if (!c || c.status === 'cancelado') {
    return (
      <div className="mx-auto max-w-3xl">
        <h1 className="font-display text-5xl text-ink">Conteo de apertura</h1>
        <p className="mt-3 text-ink-2">Aquí se cuentan los pares que hay físicamente en <b>Bodega CDMX</b>, por modelo → color → talla. Ese conteo, aprobado por Mario, será el inventario inicial de Fuxia 360 para la tienda en línea. <b>Woo no se usa como inventario.</b></p>
        {c?.status === 'cancelado' && <p className="mt-3 text-sm text-muted">El último conteo se canceló: “{c.cancel_reason}”.</p>}
        {owner ? <StartCount /> : <p className="mt-8 rounded-2xl border border-line bg-surface p-5 text-ink-2">Todavía no hay un conteo abierto. Lo inicia una dueña.</p>}
      </div>
    );
  }
  const sp = await searchParams;
  const vista = (VIEWS.some((v) => v.key === sp.vista) ? sp.vista : c.status === 'preliminar' ? 'conteo1' : 'reporte') as OpeningView | 'sinficha';
  const sheet = await getOpeningSheet(c.id, vista === 'sinficha' ? 'reporte' : vista);
  const s = state.summary!;
  const done = s.doble_ok + s.recontado;
  const pct = s.lines ? Math.round((100 * done) / s.lines) : 0;
  const open = c.status === 'preliminar' || c.status === 'congelado';

  return (
    <div>
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="font-display text-5xl text-ink">Conteo de apertura</h1>
          <p className="mt-1 text-sm text-muted">{c.location} · canal {c.target.name} · lo inició {c.started_by} el {fecha(c.started_at)}</p>
        </div>
        <span data-testid="count-status" className={`rounded-full px-4 py-2 text-sm ${c.status === 'aprobado' ? 'bg-success-soft text-success' : c.status === 'congelado' ? 'bg-danger-soft text-danger' : 'bg-gold-soft text-ink-2'}`}>{STATUS[c.status]}</span>
      </div>
      {c.status === 'congelado' && <p className="mt-4 rounded-2xl bg-danger-soft px-5 py-3 text-sm text-danger">Bodega CDMX está congelada desde {c.frozen_at ? fecha(c.frozen_at) : ''}: no se puede recibir, mover ni ajustar mercancía ahí hasta aprobar o cancelar el conteo. Mantén esta ventana corta.</p>}
      {c.status === 'aprobado' && <p className="mt-4 rounded-2xl bg-success-soft px-5 py-3 text-sm text-success">Aprobado por {c.approved_by}: “{c.approval_note}”. El inventario todavía no se carga: eso es un paso aparte que Mario autoriza.</p>}
      {c.status === 'cargado' && <p className="mt-4 rounded-2xl bg-success-soft px-5 py-3 text-sm text-success">El conteo aprobado ya es el inventario inicial de {c.location}. La bodega ya no está congelada. Falta ligar la tienda para que muestre estas cantidades.</p>}

      <div className="mt-6" data-testid="count-progress">
        <div className="flex items-baseline justify-between text-sm"><span className="text-ink">Tallas con conteo final: <b className="tabular">{done}</b> de <span className="tabular">{s.lines}</span> · <b className="tabular">{s.final_pairs}</b> pares</span><span className="tabular text-muted">{pct}%</span></div>
        <div className="mt-1.5 h-2 overflow-hidden rounded-full bg-surface-2"><div className="h-full rounded-full bg-success" style={{ width: `${pct}%` }} /></div>
        <div className="mt-2 flex flex-wrap gap-2 text-xs text-ink-2">
          <span className="rounded-full bg-surface-2 px-2.5 py-1">Sin contar {s.pendiente}</span>
          <span className="rounded-full bg-surface-2 px-2.5 py-1">Falta 2º conteo {s.contado_1}</span>
          <span className="rounded-full bg-danger-soft px-2.5 py-1 text-danger">Diferencias {s.diferencia}</span>
          <span className="rounded-full bg-danger-soft px-2.5 py-1 text-danger">Recontar por ventas/movimientos {s.recontar}</span>
          <span className="rounded-full bg-gold-soft px-2.5 py-1">Pares sin ficha {s.unlisted_open}</span>
        </div>
      </div>

      <CountControls id={c.id} status={c.status} owner={owner} blockers={state.blockers ?? []} />

      <nav className="mt-8 flex flex-wrap gap-2">
        {VIEWS.map((v) => (
          <Link key={v.key} href={`/conteo?vista=${v.key}`} data-testid={`vista-${v.key}`}
            className={`rounded-full px-4 py-2 text-sm ${vista === v.key ? 'bg-ink text-surface' : 'bg-surface text-ink-2 ring-1 ring-line'}`}>{v.label}</Link>
        ))}
        <Link href="/conteo/hoja" className="ml-auto rounded-full px-4 py-2 text-sm text-ink-2 ring-1 ring-line">Imprimir hoja de conteo</Link>
      </nav>

      {vista === 'sinficha'
        ? <Unlisted id={c.id} open={open} owner={owner} items={sheet.unlisted} />
        : <CountSheet id={c.id} view={vista} open={open} sheet={sheet} />}
    </div>
  );
}
