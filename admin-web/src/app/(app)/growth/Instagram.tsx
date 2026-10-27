import Link from 'next/link';
import type { GrowthInstagram, IgKind } from '@/lib/growth-p0';

// Growth → Instagram (P0-A). What the Instagram API returns, next to the paid orders whose last touch was Instagram without an ad.
// A sale is tied to a post only when the order's own link names it; nothing is modelled.
const KIND: Record<IgKind, string> = { post: 'Publicación', carousel: 'Carrusel', reel: 'Reel', story: 'Historia' };
const n = (v: number | null | undefined) => (v == null ? '—' : v.toLocaleString('es-MX'));
const day = (d: string) => new Date(`${d.slice(0, 10)}T12:00:00`).toLocaleDateString('es-MX', { day: 'numeric', month: 'short' });
const shift = (d: string, k: number) => { const x = new Date(`${d}T12:00:00Z`); x.setUTCDate(x.getUTCDate() + k); return x.toISOString().slice(0, 10); };
const money = (v: number, c: string) => `${c === 'MXN' ? '' : `${c} `}$${Math.round(v).toLocaleString('es-MX')}`;

export function Instagram({ data, today }: { data: GrowthInstagram; today: string }) {
  const s = data.source;
  const noData = data.daily.every((d) => d.reach == null) && data.media.length === 0;
  const preset = (label: string, from: string, to = today) => {
    const active = data.from === from && data.to === to;
    return <Link key={label} href={`/growth?vista=instagram&desde=${from}&hasta=${to}`}
      className={`rounded-full px-4 py-1.5 text-sm ${active ? 'bg-ink text-surface' : 'border border-line bg-surface text-ink-2'}`}>{label}</Link>;
  };
  const sum = (k: 'reach' | 'profile_views' | 'website_clicks') => { const v = data.daily.map((d) => d[k]).filter((x): x is number => x != null); return v.length ? v.reduce((a, b) => a + b, 0) : null; };
  return (
    <div className="mt-8" data-testid="growth-instagram">
      <div className="flex flex-wrap items-center gap-2">
        {preset('30 días', shift(today, -29))}{preset('90 días', shift(today, -89))}{preset('Julio (Summer Sale)', '2026-07-20', '2026-08-05')}
        <span className="text-sm text-muted">{day(data.from)} – {day(data.to)}</span>
      </div>

      {s.config_status !== 'CONFIGURED' ? (
        <div className="mt-4 rounded-xl bg-gold-soft p-4 text-sm text-ink" data-testid="ig-not-configured">
          <p className="font-semibold">Instagram todavía no está conectado.</p>
          <p className="mt-1 text-ink-2">{s.notes}</p>
          {s.last_error && <p className="mt-1 text-xs text-muted">Último intento{s.last_try_at ? ` (${new Date(s.last_try_at).toLocaleString('es-MX', { timeZone: 'America/Mexico_City' })})` : ''}: {s.last_error}</p>}
          <p className="mt-2 text-ink-2">Mientras tanto, abajo sí aparecen las ventas pagadas que llegaron desde Instagram: salen de WooCommerce, no de Instagram.</p>
        </div>
      ) : s.last_error ? (
        <p className="mt-4 rounded-xl bg-danger-soft p-3 text-sm text-danger">La última lectura falló: {s.last_error}</p>
      ) : null}

      <div className="mt-5 grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Card label="Ventas pagadas desde Instagram" value={`${data.sales.paid_orders}`}
          note={data.sales.by_market.map((m) => `${m.market} ${m.paid_orders} · ${money(m.revenue, m.currency)}`).join(' · ') || 'Último clic en Instagram sin anuncio'} />
        <Card label="Alcance (suma diaria)" value={n(sum('reach'))} note="Cuentas alcanzadas por día, según Instagram" />
        <Card label="Visitas al perfil" value={n(sum('profile_views'))} note="Según Instagram" />
        <Card label="Clics al sitio" value={n(sum('website_clicks'))} note="Enlace de la bio, según Instagram" />
      </div>
      <p className="mt-2 text-xs text-muted">{data.sales.rule} Con publicación identificada: {data.sales.with_post_evidence} · sin publicación identificable: {data.sales.without_post}.</p>

      <h2 className="font-display mt-10 text-3xl text-ink">Qué se publicó</h2>
      {noData ? <p className="mt-2 text-sm text-muted">Sin datos de Instagram en este periodo.</p> : (
        <table className="mt-4 w-full text-sm">
          <thead className="text-xs text-muted"><tr><th className="py-1.5 text-left font-normal">Tipo</th><th className="py-1.5 pl-3 text-right font-normal">Piezas</th>
            <th className="py-1.5 pl-3 text-right font-normal">Alcance promedio</th><th className="py-1.5 pl-3 text-right font-normal">Vistas promedio</th>
            <th className="py-1.5 pl-3 text-right font-normal">Guardados</th><th className="py-1.5 pl-3 text-right font-normal">Compartidos</th></tr></thead>
          <tbody>{data.by_kind.map((k) => (
            <tr key={k.kind} className="border-t border-line"><td className="py-2">{KIND[k.kind]}</td><td className="tabular py-2 pl-3 text-right">{k.count}</td>
              <td className="tabular py-2 pl-3 text-right">{n(k.reach_avg)}</td><td className="tabular py-2 pl-3 text-right">{n(k.views_avg)}</td>
              <td className="tabular py-2 pl-3 text-right">{n(k.saves)}</td><td className="tabular py-2 pl-3 text-right">{n(k.shares)}</td></tr>))}</tbody>
        </table>
      )}

      <h2 className="font-display mt-10 text-3xl text-ink">Día por día</h2>
      <p className="mt-1 text-sm text-ink-2">Lo publicado y lo vendido el mismo día aparecen juntos para verlos, no porque uno cause lo otro.</p>
      <div className="mt-4 overflow-x-auto">
        <table className="w-full min-w-[720px] text-sm">
          <thead className="text-xs text-muted"><tr><th className="py-1.5 text-left font-normal">Día</th><th className="py-1.5 pl-3 text-left font-normal">Publicado</th>
            <th className="py-1.5 pl-3 text-right font-normal">Alcance</th><th className="py-1.5 pl-3 text-right font-normal">Perfil</th>
            <th className="py-1.5 pl-3 text-right font-normal">Clics al sitio</th><th className="py-1.5 pl-3 text-right font-normal">Ventas pagadas desde IG</th></tr></thead>
          <tbody>{[...data.daily].reverse().map((d) => {
            const pub = (Object.keys(KIND) as IgKind[]).filter((k) => d.published[k] > 0).map((k) => `${d.published[k]} ${KIND[k].toLowerCase()}`).join(' · ');
            return (
              <tr key={d.date} className="border-t border-line" data-testid="ig-day">
                <td className="py-1.5 text-ink">{day(d.date)}</td><td className="py-1.5 pl-3 text-ink-2">{pub || '—'}</td>
                <td className="tabular py-1.5 pl-3 text-right">{n(d.reach)}</td><td className="tabular py-1.5 pl-3 text-right">{n(d.profile_views)}</td>
                <td className="tabular py-1.5 pl-3 text-right">{n(d.website_clicks)}</td><td className="tabular py-1.5 pl-3 text-right font-semibold">{d.ig_paid_orders || '—'}</td>
              </tr>);
          })}</tbody>
        </table>
      </div>

      {data.media.length > 0 && <>
        <h2 className="font-display mt-10 text-3xl text-ink">Cada pieza</h2>
        <div className="mt-4 overflow-x-auto">
          <table className="w-full min-w-[800px] text-sm">
            <thead className="text-xs text-muted"><tr><th className="py-1.5 text-left font-normal">Pieza</th><th className="py-1.5 pl-3 text-right font-normal">Alcance</th>
              <th className="py-1.5 pl-3 text-right font-normal">Vistas</th><th className="py-1.5 pl-3 text-right font-normal">Me gusta</th>
              <th className="py-1.5 pl-3 text-right font-normal">Guardados</th><th className="py-1.5 pl-3 text-right font-normal">Compartidos</th>
              <th className="py-1.5 pl-3 text-right font-normal">Ventas con evidencia</th></tr></thead>
            <tbody>{data.media.map((m) => (
              <tr key={m.media_id} className="border-t border-line align-top">
                <td className="py-2 pr-2"><span className="text-ink">{KIND[m.kind]} · {day(m.posted_at)}</span>
                  {m.permalink ? <a href={m.permalink} target="_blank" rel="noreferrer" className="ml-2 text-xs text-gold-strong underline">ver</a> : null}
                  {m.caption && <span className="block text-[11px] text-muted">{m.caption}</span>}</td>
                <td className="tabular py-2 pl-3 text-right">{n(m.reach)}</td><td className="tabular py-2 pl-3 text-right">{n(m.views)}</td>
                <td className="tabular py-2 pl-3 text-right">{n(m.likes)}</td><td className="tabular py-2 pl-3 text-right">{n(m.saves)}</td>
                <td className="tabular py-2 pl-3 text-right">{n(m.shares)}</td><td className="tabular py-2 pl-3 text-right">{m.paid_orders_with_evidence || '—'}</td>
              </tr>))}</tbody>
          </table>
        </div>
      </>}

      <h2 className="font-display mt-10 text-2xl text-ink">Lo que Instagram no deja saber</h2>
      <ul className="mt-2 list-disc pl-5 text-sm text-ink-2">{data.limitations.map((l) => <li key={l}>{l}</li>)}</ul>
    </div>
  );
}

function Card({ label, value, note }: { label: string; value: string; note?: string }) {
  return (
    <div className="atelier-card flex min-h-28 min-w-0 flex-col gap-1.5 rounded-[20px] p-4">
      <span className="kicker text-ink-2">{label}</span>
      <span className="tabular text-2xl font-semibold text-ink">{value}</span>
      {note && <span className="mt-auto text-[11px] leading-snug text-muted">{note}</span>}
    </div>
  );
}
