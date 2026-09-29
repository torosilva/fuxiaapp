import { NextResponse, type NextRequest } from 'next/server';
import { createClient } from '@/lib/supabase/server';

// Signs out (e.g. an account without Fuxia 360 access) and returns to the login screen with the reason.
export async function GET(request: NextRequest) {
  const supabase = await createClient();
  await supabase.auth.signOut();
  const url = request.nextUrl.clone();
  url.pathname = '/login';
  const motivo = request.nextUrl.searchParams.get('motivo');
  url.search = motivo ? `?motivo=${encodeURIComponent(motivo)}` : '';
  return NextResponse.redirect(url);
}
