import { notFound, redirect } from 'next/navigation';
import { canWrite, getAdminCustomer, getCrmAccess, getMe } from '@/lib/f360';
import { ClientaView } from './ClientaView';

// Ficha completa de clienta (CRM C4). Only customer_pii_viewers; the database refuses others and logs the view.
export default async function Clienta({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!canWrite((await getMe()).role)) redirect('/');
  if (!(await getCrmAccess()).pii_viewer) redirect('/clientes');
  const r = await getAdminCustomer(id);
  if (!r.ok || !r.customer) notFound();
  const c = r.customer;

  return <ClientaView c={c} />;
}
