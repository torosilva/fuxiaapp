'use client';
import { useState } from 'react';
import { consolidateFinishAction, consolidateStartAction, consolidationRedirectsAction, runPublishJobAction } from '../actions';

type Row = { model: string; from: string | null; to: string | null };

/** Owner: models the store sells as one product PER COLOUR become one product each (colour + size), like here. */
export function ConsolidatePanel() {
  const [running, setRunning] = useState(false);
  const [log, setLog] = useState<string[]>([]);
  const [msg, setMsg] = useState<string | null>(null);
  const [rows, setRows] = useState<Row[] | null>(null);
  const add = (t: string) => setLog((l) => [...l, t]);

  const redirects = async () => {
    const r = await consolidationRedirectsAction();
    if (r.ok) setRows(r.data.rows); else setMsg(r.error);
  };
  const run = async () => {
    setRunning(true); setLog([]); setRows(null); setMsg('Preparando…');
    const s = await consolidateStartAction();
    if (!s.ok) { setMsg(s.error); setRunning(false); return; }
    for (const k of s.data.skipped) add(`⏸ ${k.name}: falta ${k.missing.join(', ')} (se queda como está)`);
    let n = 0;
    for (const it of s.data.items) {
      n++;
      if (it.status !== 'publicada') {
        setMsg(`Creando en la tienda ${n} de ${s.data.items.length}: ${it.name}…`);
        if (it.job_id) {
          const p = await runPublishJobAction(it.job_id, it.product_id);
          if (!p.ok || (p.data.status !== 'succeeded')) { add(`✗ ${it.name}: ${p.ok ? (p.data.error ?? p.data.status) : p.error}`); continue; }
        }
        const f = await consolidateFinishAction(it.product_id);
        if (!f.ok) { add(`✗ ${it.name}: ${f.error}`); continue; }
      }
      add(`✓ ${it.name}`);
    }
    setMsg('Listo. La tienda muestra los productos nuevos y oculta los anteriores en 1–2 minutos. Purga la caché de SG.');
    await redirects();
    setRunning(false);
  };
  const csv = rows ? 'source,target\n' + rows.filter((r) => r.from && r.to).map((r) => `${r.from},${r.to}`).join('\n') : '';
  return (
    <div className="rounded-2xl border border-line bg-surface p-5" data-testid="consolidate">
      <p className="text-sm text-ink-2">Algunos modelos están en la tienda como <b>un producto por color</b> (por ejemplo “Botas Largas Cafes” y “Botas Largas Negras”). Esto los deja como <b>un solo producto</b> con color y talla, igual que aquí. Los anteriores se ocultan (no se borran) y los pedidos que lleguen con ellos se siguen reconociendo.</p>
      <div className="mt-3 flex flex-wrap gap-2">
        <button type="button" onClick={run} disabled={running} className="rounded-full bg-ink px-5 py-3 text-sm text-surface disabled:opacity-50">{running ? 'Uniendo…' : 'Unir en un solo producto por modelo'}</button>
        <button type="button" onClick={redirects} disabled={running} className="rounded-full px-5 py-3 text-sm text-ink-2 ring-1 ring-line">Ver redirecciones</button>
      </div>
      {msg && <p className="mt-3 text-sm text-ink" role="status">{msg}</p>}
      {log.length > 0 && <ul className="mt-2 space-y-0.5 text-sm text-ink-2">{log.map((l, i) => <li key={i}>{l}</li>)}</ul>}
      {rows && (
        <div className="mt-4">
          <p className="text-sm text-ink">Redirecciones 301 para WordPress (plugin “Redirection” → Importar):</p>
          {rows.length === 0 ? <p className="mt-1 text-sm text-muted">Todavía no hay modelos unidos.</p> : (
            <>
              <table className="mt-2 w-full text-left text-xs"><thead><tr className="text-muted"><th className="py-1">Modelo</th><th>Antes</th><th>Ahora</th></tr></thead>
                <tbody>{rows.map((r, i) => <tr key={i} className="border-t border-line"><td className="py-1 pr-2">{r.model}</td><td className="pr-2 font-mono">{r.from ?? '—'}</td><td className="font-mono">{r.to ?? '—'}</td></tr>)}</tbody></table>
              <a download="redirecciones-fuxia360.csv" href={`data:text/csv;charset=utf-8,${encodeURIComponent(csv)}`} className="mt-3 inline-block rounded-full px-4 py-2 text-sm text-ink ring-1 ring-ink">Descargar CSV</a>
            </>
          )}
        </div>
      )}
    </div>
  );
}
