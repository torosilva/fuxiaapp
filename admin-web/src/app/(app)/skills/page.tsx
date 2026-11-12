import Link from 'next/link';
import { rpc } from '@/lib/f360';
import { AREA, STATUS } from './labels';

// Fuxia Skills · biblioteca (Fase 2, Mario 2026-11-12). Who sees it is decided in the database (Dirección, Operación, Marketing).
type Item = { key: string; name: string; purpose: string; area: string; status: string; status_note: string | null; version: number | null; updated_at: string | null; updated_by: string | null };
export default async function Skills() {
  const data = await rpc<{ can_edit: boolean; skills: Item[] }>('f360_skills');
  return (
    <div className="mx-auto max-w-5xl">
      <p className="kicker text-gold-strong">Marketing</p>
      <h1 className="font-display mt-1 text-5xl text-ink">Fuxia Skills</h1>
      <p className="mt-2 max-w-2xl text-ink-2">
        Las instrucciones con las que Claude trabaja para Fuxia: copy, pricing, retención, pauta, contenido y más. Cada cambio crea una
        versión nueva y las anteriores se conservan.
      </p>
      <div className="mt-8 grid gap-4 sm:grid-cols-2" data-testid="skills">
        {data.skills.map((s) => (
          <Link key={s.key} href={`/skills/${s.key}`} className={`rounded-3xl border bg-surface p-5 transition hover:border-gold/50 ${s.status === 'actualizar' ? 'border-gold/60' : 'border-line'}`}>
            <div className="flex items-start justify-between gap-3">
              <div>
                <p className="text-xs text-muted">{AREA[s.area] ?? s.area}</p>
                <p className="mt-1 text-xl text-ink">{s.name}</p>
              </div>
              <span className={`shrink-0 rounded-full px-2.5 py-1 text-xs ${STATUS[s.status]?.cls ?? ''}`}>{STATUS[s.status]?.label ?? s.status}</span>
            </div>
            <p className="mt-2 text-sm text-ink-2">{s.purpose}</p>
            {s.status_note && <p className="mt-2 text-sm text-ink">{s.status_note}</p>}
            <p className="mt-3 text-xs text-muted">
              {s.version ? `Versión ${s.version} · ${s.updated_by ?? ''} · ${new Date(s.updated_at!).toLocaleDateString('es-MX', { timeZone: 'America/Mexico_City' })}` : 'Sin versión'}
            </p>
          </Link>
        ))}
      </div>
    </div>
  );
}
