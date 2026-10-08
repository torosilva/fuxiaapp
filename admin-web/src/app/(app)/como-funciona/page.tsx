import { redirect } from 'next/navigation';
import { canWrite, getMe } from '@/lib/f360';
import { FlowMap } from './FlowMap';

export default async function ComoFunciona() {
  if (!canWrite((await getMe()).role)) redirect('/');
  return (
    <div>
      <p className="kicker text-gold-strong">Fuxia 360</p>
      <h1 className="font-display mt-1 text-5xl text-ink">Cómo funciona</h1>
      <p className="mt-2 max-w-2xl text-ink-2">Todo el negocio, conectado. Lo que entra por la izquierda llega a Fuxia 360, y Fuxia 360 mantiene al día lo de la derecha. Toca cualquier parte para abrirla.</p>
      <div className="mt-6"><FlowMap /></div>
    </div>
  );
}
