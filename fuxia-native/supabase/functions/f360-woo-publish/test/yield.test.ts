// A job that runs out of time hands its turn back to the queue (Edge invocations stop at 150 s; Cucarron 2026-10-07).
// Run: node --test fuxia-native/supabase/functions/f360-woo-publish/test/yield.test.ts
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { handle } from '../handler.ts';
import { mockAdapter, mockStore } from '../../_shared/f360-woo/mock.ts';
import { FakeDb, macarena } from '../../_shared/f360-woo/test/fakedb.ts';

const env = { SUPABASE_URL: 'https://p.supabase.co', SUPABASE_ANON_KEY: 'anon', SUPABASE_SERVICE_ROLE_KEY: 'svc', WOO_TARGET_KEY: 'woo_local',
  WOO_BASE_URL: 'http://localhost:8080', WOO_USER: 'ck_x', WOO_SECRET: 'cs_x', STORAGE_PUBLIC_BASE: '' } as const;
const req = () => new Request('https://f/x', { method: 'POST', headers: { Authorization: 'Bearer svc', 'Content-Type': 'application/json' }, body: JSON.stringify({ action: 'run_queue' }) });

function db(attempt: number) {
  const snap = new FakeDb(macarena()).claim();
  (snap.job as { attempt: number }).attempt = attempt;
  const calls: { fn: string; body: Record<string, unknown> }[] = [];
  globalThis.fetch = (async (url: string, init?: RequestInit) => {
    const fn = String(url).split('/rpc/')[1];
    calls.push({ fn, body: JSON.parse(String(init?.body ?? '{}')) });
    if (fn === 'f360_pub_next_job') return new Response(JSON.stringify({ job_id: 'job-1', requested_by: 'owner-1' }));
    if (fn === 'f360_pub_claim') return new Response(JSON.stringify(snap));
    return new Response('null');
  }) as typeof fetch;
  return calls;
}
const opts = (kicks: { n: number }) => ({ budgetMs: -1, storeHome: async () => 'http://localhost:8080', wrapAdapter: () => mockAdapter(mockStore()),
  kick: async () => { kicks.n++; } });

test('out of time → the job goes back to the queue (f360_pub_yield, never finished) and the queue calls itself to continue', async () => {
  const calls = db(1); const kicks = { n: 0 };
  await handle(req(), env, opts(kicks));
  const fns = calls.map((c) => c.fn);
  assert.ok(fns.includes('f360_pub_yield'), fns.join(','));
  assert.ok(!fns.includes('f360_pub_finish'), 'a yielded job is not closed');
  assert.equal(kicks.n, 1, 'next invocation continues it');
});

test('a job that keeps running out of time stops after the round limit with a clear error (never loops forever)', async () => {
  const calls = db(40); const kicks = { n: 0 };
  await handle(req(), env, opts(kicks));
  const fin = calls.find((c) => c.fn === 'f360_pub_finish');
  assert.equal(fin?.body.p_status, 'failed');
  assert.match(String(fin?.body.p_error), /40 vueltas/);
  assert.ok(!calls.some((c) => c.fn === 'f360_pub_yield'));
});
