'use client';
import { useRouter } from 'next/navigation';
import { useTransition } from 'react';
import { setCaseStatusAction } from '../actions';

const OPC = [['nueva', 'Nueva'], ['en_atencion', 'En atención'], ['resuelta', 'Resuelta'], ['descartada', 'Descartada']] as const;
export function CaseStatus({ id, status }: { id: string; status: (typeof OPC)[number][0] }) {
  const router = useRouter();
  const [pending, start] = useTransition();
  return (
    <select aria-label="Estado" value={status} disabled={pending} className="rounded-full border border-line bg-surface px-3 py-2 text-sm"
      onChange={(e) => { const v = e.target.value as typeof status; start(async () => { await setCaseStatusAction(id, v); router.refresh(); }); }}>
      {OPC.map(([k, l]) => <option key={k} value={k}>{l}</option>)}
    </select>
  );
}
