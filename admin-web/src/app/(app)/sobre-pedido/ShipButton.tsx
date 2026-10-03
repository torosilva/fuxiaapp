'use client';
import { useRouter } from 'next/navigation';
import { useTransition } from 'react';
import { markStoreShipmentSentAction } from '../actions';

export function ShipButton({ id }: { id: string }) {
  const router = useRouter();
  const [pending, start] = useTransition();
  return <button type="button" disabled={pending} onClick={() => start(async () => { await markStoreShipmentSentAction(id); router.refresh(); })}
    className="rounded-full bg-ink px-4 py-2 text-sm text-surface disabled:opacity-50">Ya se envió</button>;
}
