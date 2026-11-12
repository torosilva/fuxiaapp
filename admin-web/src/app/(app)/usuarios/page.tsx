import { redirect } from 'next/navigation';
import { getMe, rpc } from '@/lib/f360';
import { UsersPanel, type AdminUsers } from './UsersPanel';

// Configuración → Usuarios (Fase 1, Mario 2026-11-12): who can do what, in one place. Dirección only; the database re-checks.
export default async function Usuarios() {
  const me = await getMe();
  if (me.role !== 'owner') redirect('/');
  const data = await rpc<AdminUsers>('f360_admin_users');
  return (
    <div className="mx-auto max-w-4xl">
      <h1 className="font-display text-5xl text-ink">Usuarios</h1>
      <p className="mt-2 text-ink-2">
        Quién entra a Fuxia 360 y qué puede hacer. Cada cambio pide un motivo y queda en la bitácora. Los datos de clientas, el Board y las
        aprobaciones de montos solo se cambian con un pase revisado; aquí se ven, no se editan.
      </p>
      <UsersPanel data={data} />
    </div>
  );
}
