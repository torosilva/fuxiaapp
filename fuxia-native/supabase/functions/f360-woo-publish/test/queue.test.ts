// Server-side publishing queue (independent of the browser). Run: node --test fuxia-native/supabase/functions/f360-woo-publish/test/
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { handle } from '../handler.ts';

const env = { SUPABASE_URL: 'https://p.supabase.co', SUPABASE_ANON_KEY: 'anon', SUPABASE_SERVICE_ROLE_KEY: 'svc', WOO_TARGET_KEY: 'woo_production',
  WOO_BASE_URL: 'https://fuxiaballerinas.com', WOO_USER: 'ck_x', WOO_SECRET: 'cs_x', STORAGE_PUBLIC_BASE: '' } as const;
const req = (token: string) => new Request('https://f/x', { method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ action: 'run_queue' }) });

function db(next: unknown) {
  const calls: string[] = [];
  globalThis.fetch = (async (url: string) => {
    const u = String(url);
    if (u.endsWith('/auth/v1/user')) return new Response(JSON.stringify({ id: 'owner-1' }));
    const fn = u.split('/rpc/')[1]; calls.push(fn);
    if (fn === 'f360_me') return new Response(JSON.stringify({ role: 'owner' }));
    if (fn === 'f360_pub_next_job') return new Response(JSON.stringify(next));
    if (fn === 'f360_pub_claim') return new Response(JSON.stringify({ message: 'Esta publicación ya terminó.' }), { status: 400 });
    return new Response('null');
  }) as typeof fetch;
  return calls;
}

test('the publisher itself (service role) runs the next queued job and calls itself for the following one', async () => {
  const calls = db({ job_id: '11111111-2222-3333-4444-555555555555', requested_by: 'owner-1' });
  let kicks = 0;
  const r = await handle(req('svc'), env, { kick: async () => { kicks++; } });
  assert.equal(r.status, 200);
  assert.ok(calls.includes('f360_pub_next_job') && calls.includes('f360_pub_claim'), calls.join(','));
  assert.equal(kicks, 1, 'chains to the next job');
});
test('empty queue → stops (no self-call)', async () => {
  db(null);
  let kicks = 0;
  await handle(req('svc'), env, { kick: async () => { kicks++; } });
  assert.equal(kicks, 0);
});
test('an owner can start the queue; it answers at once in the edge runtime (waitUntil) and keeps working', async () => {
  db({ job_id: '11111111-2222-3333-4444-555555555555', requested_by: 'owner-1' });
  const pending: Promise<unknown>[] = [];
  const r = await handle(req('user-token'), env, { waitUntil: (p) => { pending.push(p); }, kick: async () => {} });
  assert.equal(r.status, 202);
  assert.equal(pending.length, 1);
  await Promise.all(pending);
});
test('without a session the queue cannot be started', async () => {
  db(null);
  const r = await handle(new Request('https://f/x', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ action: 'run_queue' }) }), env, {});
  assert.equal(r.status, 401);
});
