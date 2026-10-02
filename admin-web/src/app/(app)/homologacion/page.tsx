import { redirect } from 'next/navigation';
import { canWrite, getHomologation, getMe } from '@/lib/f360';
import { HomologationClient } from './HomologationClient';

// Track D · D2 — Carolina tells Fuxia 360 which model / colour / size each existing Woo variation is.
// Read and decided in the database (f360_legacy_*). Nothing here moves inventory or touches Woo.
// ?canal= selects another non-production channel (e.g. the "demo_d2" practice copy); the database refuses production.
export default async function Homologacion({ searchParams }: { searchParams: Promise<{ canal?: string }> }) {
  const me = await getMe();
  if (!canWrite(me.role)) redirect('/');
  const { canal } = await searchParams;
  const data = await getHomologation(canal && /^[a-z0-9_]+$/.test(canal) ? canal : undefined);
  return <HomologationClient data={data} />;
}
