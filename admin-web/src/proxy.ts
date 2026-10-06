import { createServerClient } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';
import { environmentProblems } from '@/lib/env-guard';

// Refreshes the Supabase session cookie on every request and sends signed-out
// visitors to /login. (Authorization itself is enforced by the f360 RPCs.)
export async function proxy(request: NextRequest) {
  // Runtime half of the deployment guard (the build half is in next.config.ts).
  const guard = environmentProblems({
    VERCEL: process.env.VERCEL, NEXT_PUBLIC_F360_ENV: process.env.NEXT_PUBLIC_F360_ENV, F360_PUBLISHER_URL: process.env.F360_PUBLISHER_URL,
    NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL, NEXT_PUBLIC_SUPABASE_ANON_KEY: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
    NEXT_PUBLIC_F360_STORE_KEY: process.env.NEXT_PUBLIC_F360_STORE_KEY,
  });
  if (guard.length) return new NextResponse('Fuxia 360: configuración bloqueada por seguridad.', { status: 503 });
  let response = NextResponse.next({ request });
  const supabase = createServerClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!, {
    cookies: {
      getAll() {
        return request.cookies.getAll();
      },
      setAll(cookiesToSet) {
        cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
        response = NextResponse.next({ request });
        cookiesToSet.forEach(({ name, value, options }) => response.cookies.set(name, value, options));
      },
    },
  });

  const { data } = await supabase.auth.getUser();
  const isLogin = request.nextUrl.pathname.startsWith('/login');
  if (request.nextUrl.pathname.startsWith('/salir')) return response;
  if (!data.user && !isLogin) {
    const url = request.nextUrl.clone();
    url.pathname = '/login';
    url.search = '';
    return NextResponse.redirect(url);
  }
  if (data.user && isLogin) {
    const url = request.nextUrl.clone();
    url.pathname = '/';
    url.search = '';
    return NextResponse.redirect(url);
  }
  return response;
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|webp)$).*)'],
};
