'use client';
import { useState, useTransition } from 'react';
import { useRouter } from 'next/navigation';
import type { Brand, Competencia as Data } from '@/lib/growth-hoy-labels';
import { observeCompetitorAction } from './hoy-actions';

// Growth → Competencia. The table first (Fuxia highlighted), then how each brand advertises, then "what they do that Fuxia doesn't".
// Each observation is dated with its source; a new weekly check is a new row, so the arrows show the change.
const n = (v: number | null | undefined) => (v == null ? '—' : v >= 1_000_000 ? `${(v / 1_000_000).toLocaleString('es-MX', { maximumFractionDigits: 1 })} M` : v >= 1000 ? `${Math.round(v / 1000)} mil` : String(v));
const day = (d: string) => new Date(`${d}T12:00:00`).toLocaleDateString('es-MX', { day: 'numeric', month: 'short', year: 'numeric' });
function change(now: number | null | undefined, before: number | null | undefined) {
  if (now == null || before == null || now === before) return null;
  const d = now - before;
  return <span className={`ml-1 text-[11px] ${d > 0 ? 'text-success' : 'text-danger'}`}>{d > 0 ? '▲' : '▼'} {n(Math.abs(d))}</span>;
}

// From the 2026-10-27 analysis (Meta Ad Library + sites). Kept as text: it is a reading, not a metric.
const GAPS = [
  ['Tienen muchas más piezas al aire', 'Entre 30 y 110 anuncios activos contra unos 5 de Fuxia, y estrenan creatividades cada semana (Dione lanzó más de 20 entre el 21 y el 26 de octubre).'],
  ['Mandan directo a comprar', 'Sus anuncios llevan a la página del producto, con precio u oferta. Fuxia manda a Instagram o a mensajes, lo que agrega un paso.'],
  ['Le quitan el miedo a comprar', 'Repiten meses sin intereses, envío gratis desde un monto, primer cambio de talla gratis, 10% en la primera compra y reseñas de clientas.'],
  ['Tienen eventos con fecha límite', '“The Final Edit” (Regina Romero), “1,000 pares a $1,000” (Bala Di Gala), lanzamiento de temporada (Dione).'],
  ['Están en tiendas departamentales', 'Regina Romero en Palacio de Hierro y Liverpool, con boutiques; Bala Di Gala en Palacio.'],
  ['Trabajan con creadoras', 'Bala Di Gala x MITS; Dione con una creadora como coanunciante.'],
];

export function Competencia({ data }: { data: Data }) {
  const [open, setOpen] = useState<string | null>(null);
  const ads = data.brands.filter((b) => b.latest?.how_they_advertise);
  const last = data.brands.map((b) => b.latest?.observed_on).filter(Boolean).sort().pop();
  return (
    <div className="mt-6" data-testid="growth-competencia">
      <p className="max-w-3xl text-sm text-ink-2">Las marcas con las que te comparan las clientas. Última revisión: {last ? day(last) : '—'}. Para medir el avance, se vuelve a revisar cada semana{data.can_record ? ' con el botón “Actualizar”' : ''}.</p>

      <div className="mt-4 overflow-x-auto"><table className="w-full min-w-[760px] text-sm" data-testid="competencia-tabla">
        <thead className="text-xs text-muted"><tr>
          <th className="py-2 text-left font-normal">Marca</th><th className="py-2 pl-3 text-right font-normal">Seguidores en Instagram</th>
          <th className="py-2 pl-3 text-right font-normal">Anuncios activos en Meta</th><th className="py-2 pl-3 text-left font-normal">Precio</th>
          <th className="py-2 pl-3 text-left font-normal">Dónde vende</th>{data.can_record && <th />}</tr></thead>
        <tbody>{data.brands.map((b) => (
          <tr key={b.key} className={`border-t border-line align-top ${b.is_self ? 'bg-gold-soft/50 font-semibold' : ''}`}>
            <td className="py-2.5 pr-2 text-ink">{b.url ? <a href={b.url} target="_blank" rel="noreferrer" className="hover:underline">{b.name}</a> : b.name}
              {b.origin && <span className="block text-[11px] font-normal text-muted">{b.origin}</span>}</td>
            <td className="tabular py-2.5 pl-3 text-right">{n(b.latest?.followers_ig)}{change(b.latest?.followers_ig, b.previous?.followers_ig)}</td>
            <td className="tabular py-2.5 pl-3 text-right">{b.latest?.active_ads_meta == null ? '—' : `~${b.latest.active_ads_meta}`}{change(b.latest?.active_ads_meta, b.previous?.active_ads_meta)}</td>
            <td className="py-2.5 pl-3 font-normal text-ink-2">{b.latest?.price_text ?? '—'}</td>
            <td className="py-2.5 pl-3 font-normal text-ink-2">{b.latest?.channels ?? '—'}</td>
            {data.can_record && <td className="py-2.5 pl-3"><button type="button" className="text-xs text-ink-2 underline" onClick={() => setOpen(open === b.key ? null : b.key)}>Actualizar</button></td>}
          </tr>))}</tbody>
      </table></div>
      {open && <ObserveForm brand={data.brands.find((b) => b.key === open)!} onDone={() => setOpen(null)} />}
      <ul className="mt-2 flex flex-col gap-0.5 text-xs text-muted">{data.notes.map((x) => <li key={x}>{x}</li>)}</ul>

      <h2 className="font-display mt-10 text-3xl text-ink">Lo que hacen ellas que Fuxia no</h2>
      <div className="mt-4 grid gap-3 md:grid-cols-2">{GAPS.map(([t, d]) => (
        <div key={t} className="rounded-[18px] border border-line bg-surface p-4"><p className="font-semibold text-ink">{t}</p><p className="mt-1 text-sm text-ink-2">{d}</p></div>))}</div>
      <p className="mt-2 text-xs text-muted">Lectura del análisis del 27 oct 2026. Que lo hagan ellas no prueba que sea la causa de sus ventas: son ideas para probar como experimento.</p>

      <h2 className="font-display mt-10 text-3xl text-ink">Cómo anuncia cada una</h2>
      <div className="mt-4 flex flex-col gap-3">{ads.map((b) => (
        <div key={b.key} className={`rounded-[18px] border p-4 ${b.is_self ? 'border-gold/50 bg-gold-soft/30' : 'border-line bg-surface'}`}>
          <p className="font-semibold text-ink">{b.name} {b.latest?.active_ads_meta != null && <span className="text-sm font-normal text-ink-2">· ~{b.latest.active_ads_meta} anuncios</span>}</p>
          <p className="mt-1 text-sm text-ink-2">{b.latest?.how_they_advertise}</p>
          <p className="mt-1 text-[11px] text-muted">{b.latest?.source}</p>
        </div>))}</div>
      <p className="mt-4 text-sm text-ink-2">Para ver sus anuncios hoy: <a className="underline" target="_blank" rel="noreferrer" href="https://www.facebook.com/ads/library/?active_status=active&ad_type=all&country=MX&media_type=all">Biblioteca de anuncios de Meta (México)</a>.</p>
    </div>
  );
}

function ObserveForm({ brand, onDone }: { brand: Brand; onDone: () => void }) {
  const [err, setErr] = useState<string | null>(null);
  const [pending, start] = useTransition();
  const router = useRouter();
  const field = 'mt-1 w-full rounded-xl border border-line bg-bg px-3 py-2 text-base outline-none focus:border-gold';
  return (
    <form className="atelier-card mt-4 grid gap-3 rounded-[20px] p-5 md:grid-cols-2" data-testid="competencia-form" onSubmit={(ev) => {
      ev.preventDefault();
      const f = new FormData(ev.currentTarget); const s = (k: string) => String(f.get(k) ?? '').trim();
      const payload: Record<string, unknown> = { competitor_key: brand.key, followers_ig: s('followers_ig').replace(/[^\d]/g, ''), active_ads_meta: s('active_ads_meta').replace(/[^\d]/g, ''),
        price_text: s('price_text'), how_they_advertise: s('how_they_advertise'), source: s('source') || 'Revisión manual: perfil de Instagram y Biblioteca de anuncios de Meta' };
      start(async () => { setErr(null); const r = await observeCompetitorAction(payload); if (r.ok) { onDone(); router.refresh(); } else setErr(r.error); });
    }}>
      <p className="font-semibold text-ink md:col-span-2">Revisión de hoy: {brand.name}</p>
      <label><span className="text-xs font-semibold text-ink-2">Seguidores en Instagram (número completo)</span><input name="followers_ig" inputMode="numeric" className={field} placeholder={brand.latest?.followers_ig ? String(brand.latest.followers_ig) : ''} /></label>
      <label><span className="text-xs font-semibold text-ink-2">Anuncios activos en la Biblioteca de Meta (México)</span><input name="active_ads_meta" inputMode="numeric" className={field} /></label>
      <label className="md:col-span-2"><span className="text-xs font-semibold text-ink-2">Precio (opcional; si no cambia, déjalo vacío)</span><input name="price_text" className={field} /></label>
      <label className="md:col-span-2"><span className="text-xs font-semibold text-ink-2">Qué están anunciando (opcional)</span><textarea name="how_they_advertise" rows={2} className={field} placeholder="Promoción, mensaje, formato, a dónde llevan…" /></label>
      <label className="md:col-span-2"><span className="text-xs font-semibold text-ink-2">Fuente (opcional)</span><input name="source" className={field} /></label>
      <div className="flex gap-3 md:col-span-2"><button disabled={pending} className="rounded-full bg-ink px-5 py-2.5 text-sm text-surface disabled:opacity-40">{pending ? 'Guardando…' : 'Guardar'}</button>
        <button type="button" className="text-sm text-muted underline" onClick={onDone}>Cancelar</button></div>
      {err && <p className="text-sm text-danger md:col-span-2">{err}</p>}
    </form>
  );
}
