import Link from 'next/link';
import { rpc } from '@/lib/f360';
import { AREA, STATUS } from '../labels';
import { SkillEditor, type SkillDetail } from './SkillEditor';

// Fuxia Skills · una skill: contenido vigente, historial de versiones y, para Dirección, el editor (Fase 2, Mario 2026-11-12).
export default async function Skill({ params, searchParams }: { params: Promise<{ key: string }>; searchParams: Promise<{ v?: string }> }) {
  const { key } = await params;
  const { v } = await searchParams;
  const d = await rpc<SkillDetail>('f360_skill', { p_key: key, p_version: v ? Number(v) : null });
  const latest = d.versions[0]?.version;
  const old = d.shown && latest && d.shown.version !== latest;
  return (
    <div className="mx-auto max-w-4xl">
      <Link href="/skills" className="text-sm text-gold-strong hover:underline">← Fuxia Skills</Link>
      <p className="mt-4 text-xs text-muted">{AREA[d.skill.area] ?? d.skill.area}</p>
      <div className="flex flex-wrap items-center gap-3">
        <h1 className="font-display text-5xl text-ink">{d.skill.name}</h1>
        <span className={`rounded-full px-2.5 py-1 text-xs ${STATUS[d.skill.status]?.cls ?? ''}`}>{STATUS[d.skill.status]?.label ?? d.skill.status}</span>
      </div>
      <p className="mt-2 text-ink-2">{d.skill.purpose}</p>
      {d.skill.status_note && <p className="mt-2 rounded-xl bg-gold-soft px-4 py-3 text-sm text-ink">{d.skill.status_note}</p>}

      {old && <p className="mt-6 rounded-xl border border-gold/50 px-4 py-3 text-sm text-ink">Estás viendo la versión {d.shown!.version}. <Link href={`/skills/${key}`} className="underline">Ver la vigente (v{latest})</Link></p>}

      <SkillEditor d={d} readOnly={!d.can_edit || !!old} />

      <section className="mt-10">
        <h2 className="font-display text-3xl text-ink">Versiones</h2>
        <ul className="mt-3 divide-y divide-line rounded-3xl border border-line bg-surface text-sm">
          {d.versions.map((x) => (
            <li key={x.version} className="px-5 py-3">
              <Link href={`/skills/${key}?v=${x.version}`} className="text-ink underline-offset-2 hover:underline">Versión {x.version}</Link>
              <span className="text-ink-2"> · {x.note}</span>
              <span className="block text-xs text-muted">{x.by} · {new Date(x.at).toLocaleString('es-MX', { timeZone: 'America/Mexico_City' })}</span>
            </li>
          ))}
        </ul>
      </section>
    </div>
  );
}
