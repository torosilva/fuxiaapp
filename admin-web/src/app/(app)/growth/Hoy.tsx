import Link from 'next/link';
import { CHANNEL, STEPS, type Hoy as HoyData, type HoyFunnelRow } from '@/lib/growth-hoy';
import { PARTY } from '@/lib/growth-p0-labels';

// Growth → Hoy: what Mario or Carolina need when they open Growth. Sentences first, then the numbers behind them.
// Order: how we are doing → what to do now → ads → the customer path → Instagram → experiments. Rules at the bottom.
const MK: Record<string, string> = { MX: 'México', CO: 'Colombia', ROW: 'Resto del mundo' };
const money = (v: number | null | undefined, cur = 'MXN') => (v == null ? '—' : `${cur === 'COP' ? 'COP ' : ''}$${Math.round(v).toLocaleString('es-MX')}`);
const n = (v: number | null | undefined) => (v == null ? '—' : v.toLocaleString('es-MX'));
const day = (d: string) => new Date(`${d.slice(0, 10)}T12:00:00`).toLocaleDateString('es-MX', { day: 'numeric', month: 'short' });
const ago = (d: number | null) => (d == null ? 'sin ventas registradas' : d === 0 ? 'hoy' : d === 1 ? 'ayer' : `hace ${d} días`);

function Section({ title, sub, children, id }: { title: string; sub?: string; children: React.ReactNode; id?: string }) {
  return (
    <section className="mt-10" id={id}>
      <h2 className="font-display text-3xl text-ink">{title}</h2>
      {sub && <p className="mt-1 max-w-3xl text-sm text-ink-2">{sub}</p>}
      <div className="mt-4">{children}</div>
    </section>
  );
}

type Todo = { who: string; what: string; why: string; href?: string; cta?: string; level: 'alta' | 'media' };

export function Hoy({ data, pendingBuyers }: { data: HoyData; pendingBuyers: number | null }) {
  // "Qué hacer ahora": the database alerts plus pending steps of the open experiments and the follow-up list.
  const todos: Todo[] = data.alerts.map((a) => ({ who: a.title.includes('anuncios') ? 'Mario + agencia' : 'Mario', what: a.title, why: a.action, level: a.level,
    href: a.title.includes('anuncios') ? '/growth?vista=experimentos' : a.title.includes('Analytics') ? '/growth?vista=medicion' : undefined,
    cta: a.title.includes('anuncios') ? 'Ver experimentos' : a.title.includes('Analytics') ? 'Ver Medición' : undefined }));
  for (const e of data.experiments) {
    if (e.status === 'DRAFT' && e.campaign_ids.length === 0) todos.push({ who: 'Agencia', what: `Mandar el ID de la campaña de ${e.code}`, why: `“${e.name}” no puede empezar sin el ID: con él Fuxia 360 mide gasto y ventas solo.`, level: 'media', href: '/growth?vista=experimentos', cta: 'Abrir experimento' });
    else if (e.status === 'DRAFT') todos.push({ who: 'Mario', what: `Aprobar ${e.code}`, why: `“${e.name}”. Al aprobarlo quedan fijos presupuesto, meta y fecha de revisión.`, level: 'media', href: '/growth?vista=experimentos', cta: 'Aprobar' });
    else if (e.status === 'APPROVED') todos.push({ who: PARTY[e.responsible as keyof typeof PARTY] ?? e.responsible, what: `Arrancar ${e.code}`, why: `Empieza el ${e.start_date ? day(e.start_date) : '—'}. Márcalo como “Empezar” ese día.`, level: 'media', href: '/growth?vista=experimentos', cta: 'Abrir' });
    else if (e.live?.kill_met) todos.push({ who: 'Mario', what: `Apagar ${e.code}: llegó al criterio para cancelar`, why: `“${e.name}”. Cerrarlo como “perdió” y escribir qué aprendimos.`, level: 'alta', href: '/growth?vista=experimentos', cta: 'Cerrar' });
  }
  if (pendingBuyers) todos.push({ who: 'Carolina', what: `Escribir a ${pendingBuyers} clientas que ya compraron`, why: 'Son las que más fácil vuelven a comprar. La lista dice qué compró cada una y su talla.', level: 'media', href: '/growth?vista=clientas', cta: 'Abrir lista' });

  return (
    <div data-testid="growth-hoy">
      <p className="mt-6 text-sm text-ink-2">Últimos 14 días ({day(data.window.from)} – {day(data.window.to)}) contra los 14 anteriores. Venta = pedido pagado en la tienda.</p>

      {/* 1. Cómo vamos */}
      <div className="mt-4 grid gap-4 md:grid-cols-2">
        {data.markets.map((m) => {
          const bad = m.days_since_last == null || m.days_since_last >= 7;
          const warn = !bad && (m.days_since_last ?? 0) >= 3;
          const diff = m.paid_14 - m.paid_prev_14;
          return (
            <div key={m.market} className={`rounded-[20px] border p-5 ${bad ? 'border-danger/40 bg-danger-soft/40' : warn ? 'border-gold/40 bg-gold-soft/40' : 'border-line bg-surface'}`} data-testid={`hoy-market-${m.market}`}>
              <p className="kicker text-ink-2">{MK[m.market]}</p>
              <p className="mt-1 text-4xl font-semibold text-ink"><span className="tabular">{m.paid_14}</span> <span className="text-xl font-normal text-ink-2">{m.paid_14 === 1 ? 'venta' : 'ventas'}</span></p>
              <p className="mt-1 text-sm text-ink-2">{diff === 0 ? 'Igual que' : diff > 0 ? `${diff} más que` : `${-diff} menos que`} los 14 días anteriores ({m.paid_prev_14}) · {money(m.revenue_14, m.currency)} {m.currency}</p>
              <p className={`mt-3 text-sm font-semibold ${bad ? 'text-danger' : warn ? 'text-gold-strong' : 'text-success'}`}>Última venta: {ago(m.days_since_last)}</p>
              {m.created_14 > m.paid_14 && <p className="mt-1 text-xs text-muted">{m.created_14 - m.paid_14} pedidos se crearon y no se pagaron.</p>}
            </div>
          );
        })}
      </div>

      {/* 2. Qué hacer ahora */}
      <Section title="Qué hacer ahora" sub="Cada punto dice quién lo hace y por qué. Cuando se resuelve, desaparece solo.">
        {todos.length === 0 ? <p className="text-sm text-ink-2">Nada urgente.</p> : (
          <ol className="flex flex-col gap-3" data-testid="hoy-todos">
            {todos.map((t, i) => (
              <li key={i} className={`flex flex-col gap-2 rounded-[18px] border p-4 sm:flex-row sm:items-center ${t.level === 'alta' ? 'border-danger/40' : 'border-line'} bg-surface`}>
                <span className={`w-fit shrink-0 rounded-full px-3 py-1 text-xs font-semibold ${t.level === 'alta' ? 'bg-danger-soft text-danger' : 'bg-gold-soft text-gold-strong'}`}>{t.who}</span>
                <div className="min-w-0 flex-1"><p className="font-semibold text-ink">{t.what}</p><p className="text-sm text-ink-2">{t.why}</p></div>
                {t.href && <Link href={t.href} className="w-fit shrink-0 rounded-full bg-ink px-4 py-2 text-sm text-surface">{t.cta}</Link>}
              </li>
            ))}
          </ol>
        )}
      </Section>

      {/* 3. Publicidad */}
      <Section title="La publicidad" sub="“Llegaron por un anuncio” = el último clic antes de pagar fue un anuncio. Meta también cuenta a quien solo vio el anuncio y compró después, por eso su número suele ser mayor.">
        <div className="grid gap-4 md:grid-cols-2">
          {data.ads.filter((a) => a.market !== 'ROW').map((a) => (
            <div key={a.market} className="rounded-[20px] border border-line bg-surface p-5">
              <p className="kicker text-ink-2">{MK[a.market] ?? a.market}</p>
              <p className="mt-2 text-ink">Gastamos <b className="tabular">{money(a.spend_mxn)} MXN</b> y <b className="tabular">{a.ads_paid_orders}</b> {a.ads_paid_orders === 1 ? 'venta llegó' : 'ventas llegaron'} por un anuncio.</p>
              <p className="mt-1 text-sm text-ink-2">{a.cost_per_sale != null ? <>Cada venta costó <b>{money(a.cost_per_sale)} MXN</b>. </> : 'Todavía no se puede calcular cuánto cuesta cada venta. '}Meta dice {a.meta_purchases} compras · {n(a.clicks)} clics.</p>
            </div>
          ))}
        </div>
        <div className="mt-4 overflow-x-auto"><table className="w-full min-w-[640px] text-sm" data-testid="hoy-campaigns">
          <thead className="text-xs text-muted"><tr><th className="py-1.5 text-left font-normal">Campaña</th><th className="py-1.5 pl-3 text-left font-normal">Mercado</th>
            <th className="py-1.5 pl-3 text-right font-normal">Gasto 14 días</th><th className="py-1.5 pl-3 text-right font-normal">Clics</th>
            <th className="py-1.5 pl-3 text-right font-normal">Ventas por el anuncio</th><th className="py-1.5 pl-3 text-right font-normal">Meta dice</th><th className="py-1.5 pl-3 text-left font-normal">Cómo va</th></tr></thead>
          <tbody>{data.campaigns.map((c) => (
            <tr key={c.campaign_id} className="border-t border-line">
              <td className="py-2 text-ink">{c.name}{!c.active && <span className="ml-2 text-xs text-muted">(apagada)</span>}</td>
              <td className="py-2 pl-3 text-ink-2">{MK[c.market] ?? c.market}</td>
              <td className="tabular py-2 pl-3 text-right">{money(c.spend_mxn)}</td><td className="tabular py-2 pl-3 text-right">{n(c.clicks)}</td>
              <td className="tabular py-2 pl-3 text-right font-semibold">{c.ads_paid_orders}</td><td className="tabular py-2 pl-3 text-right text-ink-2">{c.meta_purchases}</td>
              <td className="py-2 pl-3">{c.ads_paid_orders > 0 ? <span className="rounded-full bg-success-soft px-2 py-0.5 text-xs text-success">Vende</span>
                : c.spend_mxn >= 1000 ? <span className="rounded-full bg-danger-soft px-2 py-0.5 text-xs text-danger">Gasta sin vender</span>
                : <span className="rounded-full bg-surface-2 px-2 py-0.5 text-xs text-ink-2">Poco gasto aún</span>}</td>
            </tr>))}</tbody>
        </table></div>
        <p className="mt-2 text-xs text-muted">Para que una venta cuente en su campaña, el anuncio necesita el UTM con el ID de la campaña (utm_id). El detalle por anuncio está en <Link href="/growth?vista=campanas" className="underline">Campañas</Link>.</p>
      </Section>

      {/* 4. Camino de la clienta */}
      <Section title="El camino de la clienta" sub="Personas distintas en Google Analytics, últimos 14 días cerrados. Donde más gente se cae es donde hay que trabajar.">
        {data.funnel.rows.length === 0 ? <p className="text-sm text-muted">Todavía no hay datos de Google Analytics. Se cargan cada noche.</p> : (
          <div className="grid gap-6 lg:grid-cols-2">{(['MX', 'CO'] as const).map((mk) => <Funnel key={mk} market={mk} rows={data.funnel.rows} />)}</div>
        )}
        {data.funnel.captured_on && <p className="mt-2 text-xs text-muted">Actualizado el {day(data.funnel.captured_on)}. Google Analytics no ve a quien bloquea cookies, así que puede marcar menos compras que la tienda.</p>}
      </Section>

      {/* 5. Instagram */}
      <Section title="Instagram">
        <div className="grid gap-4 sm:grid-cols-3">
          <Stat label="Seguidores" value={n(data.instagram.followers)} />
          <Stat label="Ganancia neta, últimos 7 días" value={data.instagram.follows_7 == null ? '—' : `${(data.instagram.follows_7 - (data.instagram.unfollows_7 ?? 0)) >= 0 ? '+' : ''}${n(data.instagram.follows_7 - (data.instagram.unfollows_7 ?? 0))}`}
            note={data.instagram.follows_prev_7 == null ? undefined : `Los 7 días anteriores: ${n(data.instagram.follows_prev_7 - (data.instagram.unfollows_prev_7 ?? 0))}${data.instagram.days_7 < 7 ? ` · ${data.instagram.days_7} de 7 días con dato` : ''}`} />
          <Stat label="Clics al enlace de la bio, 7 días" value={n(data.instagram.website_clicks_7)} note={`Alcance: ${n(data.instagram.reach_7)} cuentas`} />
        </div>
        <p className="mt-2 text-xs text-muted">Detalle por publicación en <Link href="/growth?vista=instagram" className="underline">Instagram</Link>. Comparación con otras marcas en <Link href="/growth?vista=competencia" className="underline">Competencia</Link>.</p>
      </Section>

      {/* 6. Experimentos */}
      <Section title="Experimentos abiertos" sub="Toda idea que pide dinero se registra antes de gastar. Fuxia 360 mide el resultado con ventas pagadas.">
        {data.experiments.length === 0 ? <p className="text-sm text-ink-2">No hay experimentos abiertos.</p> : (
          <ul className="flex flex-col gap-2">{data.experiments.map((e) => (
            <li key={e.id} className="flex flex-wrap items-center gap-2 rounded-[16px] border border-line bg-surface px-4 py-3 text-sm">
              <span className="text-xs text-muted">{e.code}</span><span className="font-semibold text-ink">{e.name}</span>
              <span className="text-ink-2">· {e.status === 'DRAFT' ? 'borrador' : e.status === 'APPROVED' ? 'aprobado, por empezar' : 'corriendo'}{e.live?.status === 'OK' ? ` · ${e.live.sample} ventas${e.live.spend_mxn != null ? `, ${money(e.live.spend_mxn)} gastados` : ''}` : ''}</span>
              <Link href="/growth?vista=experimentos" className="ml-auto text-xs underline">Abrir</Link>
            </li>))}</ul>
        )}
      </Section>

      <details className="mt-10 text-xs text-muted"><summary className="cursor-pointer">Cómo se cuenta cada número</summary>
        <ul className="mt-2 flex list-disc flex-col gap-1 pl-5">{data.rules.map((r) => <li key={r}>{r}</li>)}
          {data.sources.map((s) => <li key={s.key}>{s.label}: {s.config_status === 'CONFIGURED' ? `última carga ${s.last_success_at ? new Date(s.last_success_at).toLocaleString('es-MX', { timeZone: 'America/Mexico_City' }) : '—'}` : 'no configurado'}</li>)}</ul>
      </details>
    </div>
  );
}

function Stat({ label, value, note }: { label: string; value: string; note?: string }) {
  return (
    <div className="rounded-[20px] border border-line bg-surface p-4">
      <p className="kicker text-ink-2">{label}</p><p className="tabular mt-1 text-2xl font-semibold text-ink">{value}</p>{note && <p className="mt-1 text-xs text-muted">{note}</p>}
    </div>
  );
}

function Funnel({ market, rows }: { market: 'MX' | 'CO'; rows: HoyFunnelRow[] }) {
  const get = (period: string, channel: string, step: string) => rows.find((r) => r.market === market && r.period === period && r.channel === channel && r.step === step)?.users ?? 0;
  const top = get('actual', 'TODOS', 'session_start') || 1;
  // Biggest drop between consecutive steps (people lost), shown as the sentence on top.
  let worst = { i: -1, lost: 0 };
  STEPS.forEach((s, i) => { if (i > 0) { const lost = get('actual', 'TODOS', STEPS[i - 1].key) - get('actual', 'TODOS', s.key); if (lost > worst.lost && i > 1) worst = { i, lost }; } });
  const channels = [...new Set(rows.filter((r) => r.market === market && r.period === 'actual' && r.channel !== 'TODOS').map((r) => r.channel))]
    .sort((a, b) => get('actual', b, 'session_start') - get('actual', a, 'session_start'));
  return (
    <div className="rounded-[20px] border border-line bg-surface p-5" data-testid={`hoy-funnel-${market}`}>
      <p className="kicker text-ink-2">{MK[market]}</p>
      {worst.i > 0 && <p className="mt-1 text-sm text-ink">Donde más gente se pierde: de “{STEPS[worst.i - 1].label.toLowerCase()}” a “{STEPS[worst.i].label.toLowerCase()}”.</p>}
      <div className="mt-3 flex flex-col gap-2">
        {STEPS.map((s, i) => {
          const v = get('actual', 'TODOS', s.key); const p = get('anterior', 'TODOS', s.key);
          const prevStep = i > 0 ? get('actual', 'TODOS', STEPS[i - 1].key) : 0;
          return (
            <div key={s.key}>
              <div className="flex items-baseline justify-between gap-2 text-sm"><span className="text-ink">{s.label}</span>
                <span className="tabular text-ink"><b>{n(v)}</b> <span className="text-xs text-muted">antes {n(p)}{i > 0 && prevStep > 0 ? ` · ${Math.round((v / prevStep) * 100)}% del paso anterior` : ''}</span></span></div>
              <div className="mt-1 h-2 rounded-full bg-surface-2"><div className={`h-2 rounded-full ${worst.i === i ? 'bg-danger' : 'bg-gold'}`} style={{ width: `${Math.max(1, Math.min(100, (v / top) * 100))}%` }} /></div>
            </div>
          );
        })}
      </div>
      <details className="mt-4 text-sm"><summary className="cursor-pointer text-ink-2">Por origen</summary>
        <div className="mt-2 overflow-x-auto"><table className="w-full min-w-[420px] text-xs">
          <thead className="text-muted"><tr><th className="py-1 text-left font-normal">De dónde llegó</th>{STEPS.map((s) => <th key={s.key} className="py-1 pl-2 text-right font-normal">{s.label.split(' ')[0]}</th>)}</tr></thead>
          <tbody>{channels.map((c) => (
            <tr key={c} className="border-t border-line"><td className="py-1.5 text-ink">{CHANNEL[c] ?? c}</td>{STEPS.map((s) => <td key={s.key} className="tabular py-1.5 pl-2 text-right">{n(get('actual', c, s.key))}</td>)}</tr>))}</tbody>
        </table></div>
        <p className="mt-1 text-[11px] text-muted">Una persona que llegó por dos caminos aparece en los dos; el total de arriba no repite personas.</p>
      </details>
    </div>
  );
}
