import { TRANSFER_STATUS } from '@/lib/format';

export function TransferStatus({ status }: { status: string }) {
  const tone = status === 'with_difference' ? 'bg-danger-soft text-danger' : status === 'in_transit' ? 'bg-gold-soft text-ink' : status === 'requested' ? 'bg-surface-2 text-ink-2'
    : status === 'cancelled' ? 'bg-surface-2 text-muted line-through' : 'bg-success-soft text-success';
  return <span className={`rounded-full px-3 py-1 text-xs font-medium ${tone}`}>{TRANSFER_STATUS[status] ?? status}</span>;
}
