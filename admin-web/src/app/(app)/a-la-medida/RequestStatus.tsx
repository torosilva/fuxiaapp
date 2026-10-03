'use client';
import { useRouter } from 'next/navigation';
import { useTransition } from 'react';
import { setCustomRequestStatusAction } from '../actions';

const OPCIONES = [['nueva', 'Nueva'], ['contactada', 'Contactada'], ['cotizada', 'Cotizada'], ['cerrada', 'Vendida'], ['descartada', 'Descartada']] as const;

export function RequestStatus({ id, status }: { id: string; status: (typeof OPCIONES)[number][0] }) {
  const router = useRouter();
  const [pending, start] = useTransition();
  return (
    <select aria-label="Estado" value={status} disabled={pending} className="rounded-full border border-line bg-surface px-3 py-2 text-sm"
      onChange={(e) => { const v = e.target.value as typeof status; start(async () => { await setCustomRequestStatusAction(id, v); router.refresh(); }); }}>
      {OPCIONES.map(([k, l]) => <option key={k} value={k}>{l}</option>)}
    </select>
  );
}
