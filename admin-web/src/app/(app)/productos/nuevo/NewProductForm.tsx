'use client';
import { useState, useTransition } from 'react';
import { useRouter } from 'next/navigation';
import { ColorDot } from '@/components/ProductImage';
import { IconCheck, IconPlus, IconX } from '@/components/icons';
import { DEFAULT_SIZES, SWATCHES } from '@/lib/format';
import { createProductAction } from '../../actions';

type NewColor = { name: string; hex: string | null };

const card = 'rounded-3xl border border-line bg-surface p-5 md:p-7';
const label = 'font-display text-2xl text-ink';

export function NewProductForm() {
  const router = useRouter();
  const [name, setName] = useState('');
  const [colors, setColors] = useState<NewColor[]>([]);
  const [customColor, setCustomColor] = useState('');
  const [sizes, setSizes] = useState<string[]>(DEFAULT_SIZES);
  const [allSizes, setAllSizes] = useState<string[]>(DEFAULT_SIZES);
  const [extraSize, setExtraSize] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();

  const addColor = (c: NewColor) => {
    if (!c.name.trim() || colors.some((x) => x.name.toLowerCase() === c.name.trim().toLowerCase())) return;
    setColors([...colors, { name: c.name.trim(), hex: c.hex }]);
  };
  const toggleSize = (s: string) => setSizes(sizes.includes(s) ? sizes.filter((x) => x !== s) : allSizes.filter((x) => x === s || sizes.includes(x)));
  const addExtraSize = () => {
    const s = extraSize.trim().replace(',', '.');
    if (!s || allSizes.includes(s)) return;
    const next = [...allSizes, s].sort((a, b) => (parseFloat(a) || 0) - (parseFloat(b) || 0));
    setAllSizes(next);
    setSizes(next.filter((x) => x === s || sizes.includes(x)));
    setExtraSize('');
  };

  const submit = () => {
    setError(null);
    if (!name.trim()) return setError('Escribe el nombre del producto.');
    if (!colors.length) return setError('Agrega al menos un color.');
    if (!sizes.length) return setError('Elige al menos una talla.');
    start(async () => {
      const r = await createProductAction({ name, sizes, colors });
      if (!r.ok) { setError(r.error); return; }
      router.push(`/productos/${r.data.id}?creado=1`);
    });
  };

  return (
    <div className="mt-8 space-y-5 pb-10">
      <section className={card}>
        <h2 className={label}>Nombre</h2>
        <input value={name} onChange={(e) => setName(e.target.value)} placeholder="Ej. Macarena" autoFocus
          className="mt-3 w-full rounded-xl border border-line bg-bg px-4 py-4 text-xl outline-none focus:border-gold" />
      </section>

      <section className={card}>
        <h2 className={label}>Colores</h2>
        {colors.length > 0 && (
          <div className="mt-3 flex flex-wrap gap-2">
            {colors.map((c) => (
              <span key={c.name} className="flex items-center gap-2 rounded-full bg-ink py-2 pl-3 pr-2 text-surface">
                <ColorDot hex={c.hex} className="size-4 ring-1 ring-white/60" />{c.name}
                <button type="button" aria-label={`Quitar ${c.name}`} onClick={() => setColors(colors.filter((x) => x !== c))} className="rounded-full p-1 hover:bg-white/10"><IconX className="size-4" /></button>
              </span>
            ))}
          </div>
        )}
        <p className="mt-4 text-sm text-muted">Toca para agregar</p>
        <div className="mt-2 flex flex-wrap gap-2">
          {SWATCHES.filter((s) => !colors.some((c) => c.name.toLowerCase() === s.name.toLowerCase())).map((s) => (
            <button key={s.name} type="button" onClick={() => addColor(s)} className="flex items-center gap-2 rounded-full border border-line bg-bg px-4 py-2.5 text-[15px] text-ink-2 hover:border-gold/50">
              <ColorDot hex={s.hex} />{s.name}
            </button>
          ))}
        </div>
        <div className="mt-3 flex gap-2">
          <input value={customColor} onChange={(e) => setCustomColor(e.target.value)} placeholder="Otro color"
            onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); addColor({ name: customColor, hex: null }); setCustomColor(''); } }}
            className="flex-1 rounded-xl border border-line bg-bg px-4 py-3 outline-none focus:border-gold" />
          <button type="button" onClick={() => { addColor({ name: customColor, hex: null }); setCustomColor(''); }} className="flex items-center gap-1 rounded-xl border border-line px-4 text-ink-2"><IconPlus className="size-4" />Agregar</button>
        </div>
      </section>

      <section className={card}>
        <div className="flex items-baseline justify-between">
          <h2 className={label}>Tallas <span className="text-base text-muted">(colombianas)</span></h2>
          <span className="text-sm text-muted">{sizes.length} elegidas</span>
        </div>
        <div className="mt-3 grid grid-cols-4 gap-2 sm:grid-cols-6">
          {allSizes.map((s) => {
            const on = sizes.includes(s);
            return (
              <button key={s} type="button" onClick={() => toggleSize(s)} aria-pressed={on}
                className={`tabular rounded-xl border py-3.5 text-lg transition ${on ? 'border-ink bg-ink text-surface' : 'border-line bg-bg text-muted'}`}>{s}</button>
            );
          })}
        </div>
        <div className="mt-3 flex gap-2">
          <input value={extraSize} onChange={(e) => setExtraSize(e.target.value)} placeholder="Otra talla" inputMode="decimal"
            className="w-36 rounded-xl border border-line bg-bg px-4 py-3 outline-none focus:border-gold" />
          <button type="button" onClick={addExtraSize} className="flex items-center gap-1 rounded-xl border border-line px-4 text-ink-2"><IconPlus className="size-4" />Agregar</button>
        </div>
      </section>

      {error && <p role="alert" className="rounded-xl bg-danger-soft px-4 py-3 text-danger">{error}</p>}

      <button type="button" onClick={submit} disabled={pending}
        className="flex w-full items-center justify-center gap-2 rounded-2xl bg-ink py-5 text-lg font-medium text-surface transition hover:bg-ink-2 disabled:opacity-60">
        <IconCheck />{pending ? 'Guardando…' : 'Guardar producto'}
      </button>
      <p className="text-center text-sm text-muted">Después agregas las fotos de cada color, el precio y la descripción.</p>
    </div>
  );
}
