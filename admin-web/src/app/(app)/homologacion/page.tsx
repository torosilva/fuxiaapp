import { redirect } from 'next/navigation';
import { canWrite, getChannelState, getHomologation, getMe } from '@/lib/f360';
import { STORE_KEY } from '@/lib/store';
import { HomologationClient } from './HomologationClient';

// Track D · D2 — Carolina tells Fuxia 360 which model / colour / size each existing Woo variation is.
// Read and decided in the database (f360_legacy_*). Nothing here moves inventory or touches Woo.
// ?canal= selects another non-production channel (e.g. the "demo_d2" practice copy); the database refuses production.
export default async function Homologacion({ searchParams }: { searchParams: Promise<{ canal?: string }> }) {
  const me = await getMe();
  if (!canWrite(me.role)) redirect('/');
  const { canal } = await searchParams;
  const key = canal && /^[a-z0-9_]+$/.test(canal) ? canal : undefined;
  // The homologation functions still refuse the real store (designed for staging; Carolina's decisions were copied to production
  // at the pase, C3). Until they are enabled there, say so instead of a blank error page (Mario 2026-10-07).
  if ((key ?? STORE_KEY) === 'woo_production') {
    return (
      <div>
        <h1 className="font-display text-5xl text-ink">Homologación</h1>
        <div className="mt-6 max-w-3xl rounded-2xl bg-surface-2 px-5 py-4 text-ink-2" data-testid="homologation-not-yet">
          <p className="text-ink">Todavía no se puede homologar en la tienda real.</p>
          <p className="mt-2">Tus decisiones ya están en el sistema: se copiaron de la tienda de pruebas el 6 de octubre y son las que usa
            “Publicar en vivo” para ocultar los productos viejos. Si un producto viejo está mal ligado (por ejemplo, uno marcado
            “No existe” que sí es un modelo), pídele el cambio a Mario mientras habilitamos esta pantalla.</p>
        </div>
      </div>
    );
  }
  const [data, channel] = await Promise.all([getHomologation(key), getChannelState(key)]);
  return <HomologationClient data={data} visibility={channel.visibility} />;
}
