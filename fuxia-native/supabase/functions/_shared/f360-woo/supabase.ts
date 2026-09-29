// Minimal Supabase REST helpers for the f360 Woo functions (no SDK dependency; works on Deno and Node).
export type SupabaseEnv = { SUPABASE_URL: string; SUPABASE_ANON_KEY?: string; SUPABASE_SERVICE_ROLE_KEY: string };

export function serviceRpc(env: SupabaseEnv) {
  return async <T>(fn: string, args: Record<string, unknown>): Promise<T> => {
    const res = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/${fn}`, {
      method: 'POST',
      headers: { apikey: env.SUPABASE_SERVICE_ROLE_KEY, Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(args),
    });
    const text = await res.text();
    const body = text ? JSON.parse(text) : null;
    if (!res.ok) throw new Error((body && body.message) || `rpc ${fn} → ${res.status}`);
    return body as T;
  };
}

/** Verifies a user's Supabase JWT and returns {id, role, display_name} from f360_me (null if not an f360 user). */
export async function f360User(env: SupabaseEnv, token: string) {
  if (!token || !env.SUPABASE_ANON_KEY) return null;
  const u = await fetch(`${env.SUPABASE_URL}/auth/v1/user`, { headers: { apikey: env.SUPABASE_ANON_KEY, Authorization: `Bearer ${token}` } });
  if (!u.ok) return null;
  const { id } = (await u.json()) as { id: string };
  const me = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/f360_me`, {
    method: 'POST', headers: { apikey: env.SUPABASE_ANON_KEY, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: '{}',
  });
  if (!me.ok) return null;
  const m = (await me.json()) as { role: string; display_name: string };
  return { id, role: m.role, display_name: m.display_name };
}
