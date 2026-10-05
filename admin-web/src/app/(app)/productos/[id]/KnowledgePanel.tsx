'use client';
import { useRouter } from 'next/navigation';
import { useState, useTransition } from 'react';
import type { KnowledgeFields, ProductKnowledge } from '@/lib/f360';
import { fecha } from '@/lib/format';
import { saveKnowledgeAction } from '../../actions';

// CRO-3A (Mario 2026-10-05): what Carolina knows about the model, in ONE place. Draft until an owner validates it;
// only validated knowledge reaches the store and Hilo. The preview is exactly the "Ajuste y talla" block of the PDP.
type Key = keyof KnowledgeFields;
const CHOICES: Partial<Record<Key, [string, string][]>> = {
  fit_category: [['true_to_size', 'Talla exacta'], ['runs_small', 'Talla chica'], ['runs_large', 'Talla grande']],
  between_sizes: [['mayor', 'La mayor'], ['menor', 'La menor']],
  last_fit: [['comoda', 'Cómoda'], ['normal', 'Normal'], ['ajustada', 'Ajustada']],
  width_fit: [['angosto', 'Angosto'], ['normal', 'Normal'], ['amplio', 'Amplio']],
  toe_type: [['redonda', 'Redonda'], ['almendrada', 'Almendrada'], ['puntuda', 'Puntuda'], ['cuadrada', 'Cuadrada'], ['abierta', 'Abierta']],
};
const TEXTS: [Key, string, string, number][] = [
  ['recommended_size_note', 'Nota de talla (opcional)', 'Ej. Si tienes pie ancho, pide media talla más', 240],
  ['material_upper', 'Material exterior', 'Ej. Piel de res', 120],
  ['material_lining', 'Forro', 'Ej. Piel suave', 120],
  ['material_sole', 'Suela', 'Ej. Hule antiderrapante', 120],
  ['comfort_notes', 'Comodidad', 'Lo que dirías a una clienta (sin promesas que no podamos sostener)', 400],
  ['care_instructions', 'Cuidados', 'Ej. Limpiar con paño seco; no mojar', 400],
];
const ALL: Key[] = ['fit_category', 'between_sizes', 'recommended_size_note', 'last_fit', 'width_fit', 'material_upper', 'material_lining', 'material_sole', 'heel_height_cm', 'toe_type', 'comfort_notes', 'care_instructions'];

function Pills({ value, options, onChange, disabled, label }: { value: string; options: [string, string][]; onChange: (v: string) => void; disabled: boolean; label: string }) {
  return (
    <div role="radiogroup" aria-label={label} className="mt-2 flex flex-wrap gap-2">
      {options.map(([v, l]) => (
        <button key={v} type="button" role="radio" aria-checked={value === v} disabled={disabled} onClick={() => onChange(value === v ? '' : v)}
          className={`min-h-11 rounded-full px-4 text-[15px] transition ${value === v ? 'bg-ink text-surface' : 'border border-line bg-bg text-ink-2 hover:border-gold'}`}>{l}</button>
      ))}
    </div>
  );
}

export function KnowledgePanel({ productId, data, canEdit }: { productId: string; data: ProductKnowledge; canEdit: boolean }) {
  const router = useRouter();
  const k = data.knowledge;
  const [f, setF] = useState<Record<string, string>>(() => Object.fromEntries(ALL.map((key) => [key, k?.[key] == null ? '' : String(k[key])])));
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);
  const [pending, start] = useTransition();
  const set = (key: Key, v: string) => { setF((x) => ({ ...x, [key]: v })); setMsg(null); };
  const lab = data.labels;

  const save = (validate: boolean) => start(async () => {
    const r = await saveKnowledgeAction(productId, f, validate);
    if (r.ok) { setMsg({ ok: true, text: validate ? 'Validado: ya puede mostrarse en la tienda y en Hilo.' : 'Guardado como borrador.' }); router.refresh(); }
    else setMsg({ ok: false, text: r.error });
  });

  const input = 'mt-1 w-full rounded-xl border border-line bg-bg px-3 py-3 text-[15px] text-ink outline-none focus:border-gold disabled:opacity-60';
  const fit = f.fit_category;
  const status = k?.status ?? 'sin_datos';

  return (
    <section className="mt-10 rounded-3xl border border-line bg-surface p-5 md:p-6" id="ajuste">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h2 className="font-display text-3xl text-ink">Ajuste y talla</h2>
        <span className={`rounded-full px-3 py-1 text-sm ${status === 'validado' ? 'bg-success-soft text-success' : status === 'borrador' ? 'bg-gold-soft text-ink-2' : 'bg-surface-2 text-muted'}`}>
          {status === 'validado' ? `Validado por ${k?.validated_by_name}` : status === 'borrador' ? 'Borrador (no se muestra en la tienda)' : 'Sin información'}
        </span>
      </div>
      <p className="mt-1 text-sm text-muted">Lo que sabes de este modelo, en un solo lugar. Lo usan la tienda en línea, Hilo y la app de vendedoras. Solo se muestra cuando una dueña lo valida.</p>

      <div className="mt-6 grid gap-8 lg:grid-cols-[minmax(0,1fr)_minmax(0,340px)]">
        <div className="flex flex-col gap-5">
          <div><p className="text-ink">¿Cómo queda la talla?</p><Pills label="Talla" value={fit} options={CHOICES.fit_category!} onChange={(v) => set('fit_category', v)} disabled={!canEdit} /></div>
          <div><p className="text-ink">Si está entre dos tallas, que elija…</p><Pills label="Entre dos tallas" value={f.between_sizes} options={CHOICES.between_sizes!} onChange={(v) => set('between_sizes', v)} disabled={!canEdit} /></div>
          <div><p className="text-ink">Horma</p><Pills label="Horma" value={f.last_fit} options={CHOICES.last_fit!} onChange={(v) => set('last_fit', v)} disabled={!canEdit} /></div>
          <div><p className="text-ink">Ancho <span className="text-sm text-muted">(solo si aplica)</span></p><Pills label="Ancho" value={f.width_fit} options={CHOICES.width_fit!} onChange={(v) => set('width_fit', v)} disabled={!canEdit} /></div>
          <div><p className="text-ink">Punta</p><Pills label="Punta" value={f.toe_type} options={CHOICES.toe_type!} onChange={(v) => set('toe_type', v)} disabled={!canEdit} /></div>
          <label className="text-sm text-muted">Altura de tacón o plataforma (cm)
            <input inputMode="decimal" className={`${input} max-w-40 tabular`} value={f.heel_height_cm} disabled={!canEdit} onChange={(e) => set('heel_height_cm', e.target.value.replace(/[^\d.]/g, ''))} placeholder="Ej. 1.5" />
          </label>
          {TEXTS.map(([key, l, ph, max]) => (
            <label key={key} className="text-sm text-muted">{l}
              {max > 150 ? <textarea rows={2} maxLength={max} className={input} value={f[key]} disabled={!canEdit} onChange={(e) => set(key, e.target.value)} placeholder={ph} />
                : <input maxLength={max} className={input} value={f[key]} disabled={!canEdit} onChange={(e) => set(key, e.target.value)} placeholder={ph} />}
            </label>
          ))}
          {canEdit && (
            <div className="flex flex-wrap gap-3">
              <button type="button" disabled={pending} onClick={() => save(false)} className="rounded-full border border-line bg-surface px-5 py-3 text-[15px] text-ink disabled:opacity-50">Guardar borrador</button>
              {data.can_validate && <button type="button" disabled={pending || !fit} onClick={() => save(true)} className="rounded-full bg-ink px-5 py-3 text-[15px] text-surface disabled:opacity-40">Guardar y validar</button>}
            </div>
          )}
          {msg && <p role={msg.ok ? 'status' : 'alert'} className={`rounded-xl px-4 py-3 text-sm ${msg.ok ? 'bg-success-soft text-success' : 'bg-danger-soft text-danger'}`}>{msg.text}</p>}
          {k && <p className="text-xs text-muted">Versión {k.version} · última edición de {k.updated_by_name} {fecha(k.updated_at)}</p>}
        </div>

        <aside aria-label="Vista previa en la tienda" className="h-fit rounded-2xl border border-line bg-bg p-5">
          <p className="text-xs uppercase tracking-[0.2em] text-muted">Así se verá en la tienda</p>
          <p className="font-display mt-3 text-2xl text-ink">Ajuste y talla</p>
          {fit ? (
            <div className="mt-3 flex flex-col gap-2 text-[15px] text-ink-2">
              <p className="text-ink">✓ {lab.fit_category?.[fit]}</p>
              <p>{lab.fit_advice?.[fit]}</p>
              {f.recommended_size_note && <p>{f.recommended_size_note}</p>}
              {f.between_sizes && <p>{lab.between_sizes?.[f.between_sizes]}</p>}
              {(f.last_fit || f.width_fit || f.toe_type || f.heel_height_cm) && (
                <p className="text-sm text-muted">{[f.last_fit && `Horma: ${lab.last_fit?.[f.last_fit]}`, f.width_fit && `Ancho: ${lab.width_fit?.[f.width_fit]}`,
                  f.toe_type && `Punta: ${lab.toe_type?.[f.toe_type]}`, f.heel_height_cm && `Tacón: ${f.heel_height_cm} cm`].filter(Boolean).join(' · ')}</p>
              )}
              {(f.material_upper || f.material_lining || f.material_sole) && (
                <p className="text-sm text-muted">{[f.material_upper && `Exterior: ${f.material_upper}`, f.material_lining && `Forro: ${f.material_lining}`, f.material_sole && `Suela: ${f.material_sole}`].filter(Boolean).join(' · ')}</p>
              )}
              {f.comfort_notes && <p className="text-sm">{f.comfort_notes}</p>}
              {f.care_instructions && <p className="text-sm text-muted">Cuidados: {f.care_instructions}</p>}
            </div>
          ) : <p className="mt-3 text-sm text-muted">Elige cómo queda la talla para ver la vista previa.</p>}
          {status !== 'validado' && <p className="mt-4 rounded-xl bg-gold-soft px-3 py-2 text-xs text-ink-2">Todavía no se muestra: falta validarlo.</p>}
        </aside>
      </div>
    </section>
  );
}
