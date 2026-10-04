import Link from 'next/link';
import { listInbox } from '@/lib/f360';
import { fecha } from '@/lib/format';
import { CaseStatus } from './CaseStatus';

const ORIGEN: Record<string, string> = { hilo_web: 'Hilo · web', hilo_app: 'Hilo · app', hilo_whatsapp: 'Hilo · WhatsApp', hilo_voice: 'Hilo · teléfono', web_pdp: 'Tienda en línea' };
const MOTIVO: Record<string, string> = { requested: 'Pidió hablar con alguien', complaint: 'Queja', high_intent: 'Quiere comprar', out_of_scope: 'Fuera de lo que sabe Hilo', low_confidence: 'Hilo no estaba seguro' };

// Everything a customer asked the team for, from any channel (Hilo app/web/WhatsApp, "a la medida").
export default async function Bandeja({ searchParams }: { searchParams: Promise<{ ver?: string }> }) {
  const { ver } = await searchParams;
  const all = await listInbox();
  const abiertos = all.filter((c) => c.status === 'nueva' || c.status === 'en_atencion');
  const rows = ver === 'todos' ? all : abiertos;
  const wa = (c: (typeof all)[number]) => c.phone && !c.phone.startsWith('···')
    ? `https://wa.me/${c.phone.replace(/\D/g, '')}?text=${encodeURIComponent(`¡Hola${c.name ? ', ' + c.name : ''}! Soy de Fuxia Ballerinas.${c.product ? ` Vimos tu mensaje sobre ${c.product}${c.color ? ' ' + c.color : ''}.` : ''}`)}` : null;
  return (
    <div className="mx-auto max-w-5xl">
      <h1 className="font-display text-5xl text-ink">Bandeja de clientas</h1>
      <p className="mt-2 text-ink-2">Todo lo que una clienta le pide al equipo: cuando <b>Hilo</b> necesita a una persona (app, web o WhatsApp) y los pedidos <b>a la medida</b>. Cada caso nuevo también llega por correo a info@fuxiaballerinas.com.</p>
      <nav className="mt-5 flex gap-2">
        <Link href="/bandeja" className={`rounded-full px-4 py-2 text-sm ${ver !== 'todos' ? 'bg-ink text-surface' : 'bg-surface text-ink-2 ring-1 ring-line'}`}>Por atender <span className="opacity-70">{abiertos.length}</span></Link>
        <Link href="/bandeja?ver=todos" className={`rounded-full px-4 py-2 text-sm ${ver === 'todos' ? 'bg-ink text-surface' : 'bg-surface text-ink-2 ring-1 ring-line'}`}>Todos <span className="opacity-70">{all.length}</span></Link>
      </nav>
      {rows.length === 0 ? <p className="mt-8 rounded-2xl border border-dashed border-line bg-surface p-8 text-center text-ink-2">Nada por atender. 💛</p> : (
        <ul className="mt-6 space-y-3">
          {rows.map((c) => (
            <li key={c.id} className={`rounded-2xl border bg-surface p-4 ${c.status === 'nueva' ? 'border-gold' : 'border-line'}`}>
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div className="min-w-0 flex-1">
                  <p className="text-xs uppercase tracking-[0.14em] text-muted">{c.kind === 'a_la_medida' ? 'A la medida' : (MOTIVO[c.reason ?? ''] ?? 'Hilo pide ayuda')} · {ORIGEN[c.source] ?? c.source} · {fecha(c.created_at)}</p>
                  <p className="mt-1 text-ink">{c.name ? <b>{c.name}</b> : <span className="text-muted">Sin nombre todavía</span>}{c.phone && <> · {c.phone}</>}{c.email && <> · {c.email}</>}</p>
                  {c.product && <p className="mt-1 text-sm text-ink-2">{c.product}{c.color && <> · {c.color}</>}{c.size && <> · talla {c.size}</>}{c.country && <> · {c.country.toUpperCase()}</>}</p>}
                  {c.summary && <p className="mt-2 text-sm text-ink-2">“{c.summary}”</p>}
                  {c.transcript.length > 0 && (
                    <details className="mt-2 text-sm"><summary className="cursor-pointer text-muted">Ver conversación ({c.transcript.length})</summary>
                      <ul className="mt-2 space-y-1">{c.transcript.map((m, i) => <li key={i} className={m.role === 'user' ? 'text-ink' : 'text-ink-2'}><b>{m.role === 'user' ? 'Clienta' : 'Hilo'}:</b> {m.content}</li>)}</ul>
                    </details>
                  )}
                  {c.updated_by && <p className="mt-1 text-xs text-muted">{c.status} · {c.updated_by}</p>}
                </div>
                <div className="flex flex-col items-end gap-2">
                  {wa(c) ? <a href={wa(c)!} target="_blank" rel="noreferrer" className="rounded-full bg-success px-4 py-2 text-sm text-surface">WhatsApp</a>
                    : <span className="text-xs text-muted">Sin teléfono todavía</span>}
                  <CaseStatus id={c.id} status={c.status} />
                </div>
              </div>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
