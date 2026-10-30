'use client';
import { useState, useTransition } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { OUTREACH, type Buyer, type Outreach, type Recuperar } from '@/lib/growth-hoy';
import { markOutreachAction } from './hoy-actions';

// Growth → Clientas a recuperar (Carolina). Steps on top, one card per buyer, one tap to record what happened.
// No personal data lives here: the name and phone are in the WooCommerce order ("Abrir pedido").
const day = (d: string) => new Date(d).toLocaleDateString('es-MX', { day: 'numeric', month: 'short', year: 'numeric', timeZone: 'America/Mexico_City' });
const money = (v: number, mk: string) => `${mk === 'CO' ? 'COP ' : ''}$${Math.round(v).toLocaleString('es-MX')}`;
const what = (b: Buyer) => b.items.map((i) => `${i.product}${i.color ? ` ${i.color}` : ''}${i.size ? `, talla ${i.size}` : ''}`).join(' · ') || 'sin detalle de producto';
const DONE: Outreach['status'][] = ['compro', 'no_interesa', 'sin_datos'];

export function Clientas({ data }: { data: Recuperar }) {
  const [filter, setFilter] = useState<'pendientes' | 'seguimiento' | 'cerradas'>('pendientes');
  const groups = {
    pendientes: data.buyers.filter((b) => !b.outreach),
    seguimiento: data.buyers.filter((b) => b.outreach && !DONE.includes(b.outreach.status)),
    cerradas: data.buyers.filter((b) => b.outreach && DONE.includes(b.outreach.status)),
  };
  const tab = (k: typeof filter, label: string) => (
    <button type="button" onClick={() => setFilter(k)} className={`rounded-full px-4 py-2 text-sm ${filter === k ? 'bg-ink text-surface' : 'border border-line bg-surface text-ink-2'}`}>{label} ({groups[k].length})</button>
  );
  return (
    <div className="mt-6" data-testid="growth-clientas">
      <div className="flex flex-wrap gap-2">
        <Link href="/growth?vista=clientas&mercado=MX" className={`rounded-full px-4 py-2 text-sm ${data.market === 'MX' ? 'bg-gold-soft font-semibold text-gold-strong' : 'text-ink-2 underline'}`}>México</Link>
        <Link href="/growth?vista=clientas&mercado=CO" className={`rounded-full px-4 py-2 text-sm ${data.market === 'CO' ? 'bg-gold-soft font-semibold text-gold-strong' : 'text-ink-2 underline'}`}>Colombia</Link>
      </div>

      <div className="atelier-card mt-4 rounded-[20px] p-5">
        <h2 className="text-lg font-semibold text-ink">Cómo se usa</h2>
        <ol className="mt-2 flex list-decimal flex-col gap-1 pl-5 text-sm text-ink-2">
          <li>Empieza por las de arriba: son las que compraron más recientemente.</li>
          <li>Toca <b>Abrir pedido</b>: ahí está su nombre, WhatsApp y correo.</li>
          <li>Escríbele por WhatsApp. Puedes copiar el mensaje sugerido.</li>
          <li>Regresa y toca lo que pasó: <b>Le escribí</b>, <b>Respondió</b>, <b>Volvió a comprar</b>… Así sabemos a quién falta.</li>
        </ol>
        <p className="mt-2 text-xs text-muted">{data.rule}</p>
      </div>

      <div className="mt-6 flex flex-wrap gap-2">{tab('pendientes', 'Sin contactar')}{tab('seguimiento', 'En seguimiento')}{tab('cerradas', 'Cerradas')}</div>
      <div className="mt-4 flex flex-col gap-3">
        {groups[filter].length === 0 ? <p className="text-sm text-muted">No hay clientas en este grupo.</p> : groups[filter].map((b) => <BuyerCard key={b.buyer} b={b} market={data.market} />)}
      </div>
    </div>
  );
}

function BuyerCard({ b, market }: { b: Buyer; market: string }) {
  const [note, setNote] = useState('');
  const [err, setErr] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);
  const [pending, start] = useTransition();
  const router = useRouter();
  const first = b.items[0];
  const msg = `Hola, soy Carolina de Fuxia Ballerinas. Queríamos saber cómo te han quedado tus ${first ? first.product : 'Fuxia'}${first?.color ? ` ${first.color}` : ''}. Si buscas otro par, con gusto te ayudo a elegir modelo y talla por aquí.`;
  const mark = (status: string) => start(async () => {
    setErr(null);
    const r = await markOutreachAction(market, b.buyer, status, note);
    if (r.ok) { setNote(''); router.refresh(); } else setErr(r.error);
  });
  return (
    <div className="rounded-[18px] border border-line bg-surface p-4" data-testid="clienta-card">
      <div className="flex flex-wrap items-baseline gap-2">
        <span className="font-semibold text-ink">Pedido #{b.last_order}</span>
        <span className="text-sm text-ink-2">· {day(b.last_at)} ({b.days_since === 0 ? 'hoy' : b.days_since === 1 ? 'ayer' : `hace ${b.days_since} días`})</span>
        <span className="text-sm text-ink-2">· {money(b.spent, market)}{b.orders > 1 ? ` en ${b.orders} pedidos` : ''}</span>
        {b.in_club && <span className="rounded-full bg-gold-soft px-2 py-0.5 text-[11px] text-gold-strong">Club Fuxia</span>}
        {b.outreach && <span className="rounded-full bg-surface-2 px-2 py-0.5 text-[11px] text-ink-2">{OUTREACH[b.outreach.status]} · {b.outreach.by} · {day(b.outreach.at)}</span>}
      </div>
      <p className="mt-1 text-sm text-ink">Compró: {what(b)}</p>
      {b.outreach?.note && <p className="mt-1 text-xs text-muted">Nota: {b.outreach.note}</p>}
      <div className="mt-3 flex flex-wrap items-center gap-2">
        {b.order_url && <a href={b.order_url} target="_blank" rel="noreferrer" className="rounded-full bg-ink px-4 py-2 text-sm text-surface">Abrir pedido</a>}
        <button type="button" className="rounded-full border border-line px-4 py-2 text-sm text-ink" onClick={() => { navigator.clipboard?.writeText(msg).then(() => setCopied(true)).catch(() => undefined); }}>
          {copied ? 'Mensaje copiado' : 'Copiar mensaje sugerido'}</button>
      </div>
      <div className="mt-3 flex flex-col gap-2 sm:flex-row sm:items-center">
        <input value={note} onChange={(e) => setNote(e.target.value)} maxLength={300} placeholder="Nota (opcional): qué dijo, qué busca…" className="min-w-0 flex-1 rounded-xl border border-line bg-bg px-3 py-2 text-base outline-none focus:border-gold" />
        <div className="flex flex-wrap gap-1.5">{(Object.keys(OUTREACH) as Outreach['status'][]).map((s) => (
          <button key={s} type="button" disabled={pending} onClick={() => mark(s)} className="rounded-full border border-line bg-surface px-3 py-1.5 text-xs text-ink disabled:opacity-40">{OUTREACH[s]}</button>))}</div>
      </div>
      {err && <p className="mt-2 text-sm text-danger">{err}</p>}
    </div>
  );
}
