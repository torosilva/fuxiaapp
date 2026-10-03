'use client';
import { useRouter } from 'next/navigation';
import { useTransition } from 'react';
import { setMadeToOrderStatusAction } from '../actions';

const NEXT = { pendiente: ['en_proceso', 'En proceso'], en_proceso: ['enviado', 'Ya se envió'] } as const;

export function StatusButtons({ id, status }: { id: string; status: 'pendiente' | 'en_proceso' | 'enviado' | 'cancelado' }) {
  const router = useRouter();
  const [pending, start] = useTransition();
  const set = (s: 'pendiente' | 'en_proceso' | 'enviado' | 'cancelado') => start(async () => { await setMadeToOrderStatusAction(id, s); router.refresh(); });
  if (status === 'enviado' || status === 'cancelado') return <span className="rounded-full bg-surface-2 px-3 py-1 text-sm text-ink-2">{status === 'enviado' ? 'Enviado' : 'Cancelado'}</span>;
  const [next, label] = NEXT[status];
  return (
    <div className="flex gap-2">
      <button type="button" disabled={pending} onClick={() => set(next)} className="rounded-full bg-ink px-4 py-2 text-sm text-surface disabled:opacity-50">{label}</button>
      <button type="button" disabled={pending} onClick={() => set('cancelado')} className="rounded-full px-4 py-2 text-sm text-ink-2 ring-1 ring-line disabled:opacity-50">Cancelar</button>
    </div>
  );
}
