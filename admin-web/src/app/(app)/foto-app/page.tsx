import { createClient } from '@/lib/supabase/server';
import { canWrite, getMe } from '@/lib/f360';
import { FotoAppClient, type WelcomeAdmin } from './FotoAppClient';

// The photo behind the mobile app's welcome screen and Home hero. Changing it never needs a new app version.
export default async function FotoApp() {
  const supabase = await createClient();
  const [me, { data, error }] = await Promise.all([getMe(), supabase.rpc('f360_app_welcome_admin')]);
  return (
    <div>
      <h1 className="font-display text-5xl text-ink">Foto de la app</h1>
      <p className="mt-2 max-w-2xl text-ink-2">
        La foto que ven las clientas al abrir la app de Fuxia (bienvenida y portada del inicio). Se cambia aquí y les llega sola,
        sin descargar nada nuevo. Si no eliges ninguna, la app usa el producto marcado como Destacado en la tienda, o el más nuevo.
      </p>
      {error ? (
        <p role="alert" className="mt-6 rounded-xl bg-danger-soft px-4 py-3 text-sm text-danger">No se pudo cargar: {error.message}</p>
      ) : (
        <FotoAppClient data={data as WelcomeAdmin} canEdit={canWrite(me.role)} />
      )}
    </div>
  );
}
