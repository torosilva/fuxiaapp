import { analystHistory, analystUsage, PREGUNTAS } from '@/lib/analyst';
import { Analyst } from './Analyst';

export const dynamic = 'force-dynamic';

export default async function Inteligencia() {
  const [history, usage] = await Promise.all([analystHistory(), analystUsage()]);
  return (
    <div className="mx-auto w-full max-w-5xl">
      <h1 className="font-display text-4xl text-ink md:text-5xl">Inteligencia</h1>
      <p className="mt-2 max-w-3xl text-sm text-muted">
        Pregúntale al analista sobre ventas, países, inventario, marketing y metas. Solo lee datos de Fuxia 360: separa lo que es un
        <b className="text-ink"> hecho</b> (con su fuente), un <b className="text-ink">cálculo</b> (con su fórmula) y una
        <b className="text-ink"> recomendación</b> (su opinión). Si un dato no existe, te dice qué falta.
      </p>
      <Analyst preguntas={PREGUNTAS} history={history} usage={usage} />
    </div>
  );
}
