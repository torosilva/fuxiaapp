import { redirect } from 'next/navigation';
import { canWrite, getMe } from '@/lib/f360';
import { flowStats } from '@/lib/flow-stats';
import { FlowMap } from './FlowMap';

// Mapa del negocio (was "Cómo funciona", renamed by Mario 2026-10-08). Same live numbers as Inicio (lib/flow-stats).
export default async function MapaDelNegocio() {
  if (!canWrite((await getMe()).role)) redirect('/');
  const stats = await flowStats();
  return (
    <div>
      <p className="kicker text-gold-strong">Fuxia 360</p>
      <h1 className="font-display mt-1 text-5xl text-ink">Mapa del negocio</h1>
      <p className="mt-2 max-w-2xl text-ink-2">Todo el negocio, conectado. Lo que entra por la izquierda llega a Fuxia 360, y Fuxia 360 mantiene al día lo de la derecha. Toca cualquier parte para abrirla.</p>
      <div className="mt-6"><FlowMap stats={stats} /></div>
    </div>
  );
}
