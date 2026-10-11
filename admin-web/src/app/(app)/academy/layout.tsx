import { notFound } from 'next/navigation';
import { academyEnabled } from '@/lib/academy';

// Fuxia Academy — A1, STAGING ONLY (Mario 2026-10-11). Hiding pages is never the security: every RPC decides in the database.
export const dynamic = 'force-dynamic';

export default function AcademyLayout({ children }: { children: React.ReactNode }) {
  if (!academyEnabled()) notFound();
  return <div className="mx-auto flex w-full max-w-2xl flex-col gap-5">{children}</div>;
}
