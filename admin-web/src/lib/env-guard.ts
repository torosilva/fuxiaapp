// Deployment guard. Runs at `next build` / `next start` (next.config.ts) and on every request (proxy.ts).
// A deployment marked as staging REFUSES to build/run if anything points at the production Supabase project,
// if it isn't the approved staging project, or if a server secret is present in its environment.
// Messages name the offending VARIABLE only — never its value.
export const PRODUCTION_REF = 'tgzgiwfzddsghnxgkcqd';
export const STAGING_REF = 'faltxpkaicwpnlqaxrdu';

// Secrets that must never be given to the admin web app (browser-facing deployment).
const FORBIDDEN = /SERVICE_ROLE|SERVICE_KEY|DB_URL|DATABASE_URL|DB_PASSWORD|POSTGRES|WC_CONSUMER|WOO_SECRET|WOO_USER|OTP_SALT|WEBHOOK_SECRET|SB_SECRET/i;

function jwtRef(token: string): { ref?: string; role?: string } | null {
  const part = token.split('.')[1];
  if (!part) return null;
  try { return JSON.parse(Buffer.from(part.replace(/-/g, '+').replace(/_/g, '/'), 'base64').toString('utf8')); } catch { return null; }
}

export function environmentProblems(env: Record<string, string | undefined> = process.env): string[] {
  const problems: string[] = [];
  const f360 = env.NEXT_PUBLIC_F360_ENV;
  const onVercel = !!env.VERCEL;

  if (onVercel && f360 !== 'staging') problems.push('En Vercel solo se permite el ambiente de pruebas: NEXT_PUBLIC_F360_ENV debe ser "staging".');

  for (const [k, v] of Object.entries(env)) {
    if (!v) continue;
    if ((k.startsWith('NEXT_PUBLIC_') || k.includes('SUPABASE') || k.startsWith('F360_')) && v.includes(PRODUCTION_REF)) {
      problems.push(`${k} apunta al proyecto de PRODUCCIÓN.`);
    }
    if (f360 === 'staging' && FORBIDDEN.test(k)) problems.push(`${k} es un secreto de servidor y no debe existir en este despliegue.`);
  }

  if (f360 === 'staging') {
    const url = env.NEXT_PUBLIC_SUPABASE_URL ?? '';
    if (!url.includes(STAGING_REF)) problems.push('NEXT_PUBLIC_SUPABASE_URL no es el proyecto de staging aprobado.');
    const key = env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? '';
    if (!key) problems.push('Falta NEXT_PUBLIC_SUPABASE_ANON_KEY.');
    else if (key.startsWith('sb_secret_')) problems.push('NEXT_PUBLIC_SUPABASE_ANON_KEY es una llave SECRETA.');
    else if (key.split('.').length === 3) {
      const claims = jwtRef(key);
      if (claims?.ref !== STAGING_REF) problems.push('NEXT_PUBLIC_SUPABASE_ANON_KEY no pertenece al proyecto de staging.');
      if (claims?.role !== 'anon') problems.push('NEXT_PUBLIC_SUPABASE_ANON_KEY no es una llave pública (anon).');
    }
    const pub = env.F360_PUBLISHER_URL;
    if (onVercel && pub && /\/\/(localhost|127\.|0\.0\.0\.0|\[::1\])/i.test(pub)) problems.push('F360_PUBLISHER_URL apunta a localhost; no se permite en un despliegue remoto.');
  }
  return problems;
}

export function assertEnvironment(env: Record<string, string | undefined> = process.env) {
  const problems = environmentProblems(env);
  if (problems.length) throw new Error(`Fuxia 360 — despliegue bloqueado por seguridad:\n- ${problems.join('\n- ')}`);
}

/** Woo publishing is only offered where a real publisher is configured (never a loopback URL on a remote deployment). */
export function publisherAvailable(env: Record<string, string | undefined> = process.env) {
  const url = env.F360_PUBLISHER_URL;
  if (!url) return false;
  if (env.VERCEL && /\/\/(localhost|127\.|0\.0\.0\.0|\[::1\])/i.test(url)) return false;
  return true;
}
