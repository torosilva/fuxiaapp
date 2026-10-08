import { test } from 'node:test';
import assert from 'node:assert/strict';
import { handleWhatsApp, waTo } from '../handler.ts';

const env = { SUPABASE_URL: 'http://db', SUPABASE_SERVICE_ROLE_KEY: 'k', TWILIO_ACCOUNT_SID: 'AC1', TWILIO_AUTH_TOKEN: 't',
  TWILIO_WHATSAPP_FROM: '+5215500000000', TWILIO_THANKS_CONTENT_SID: 'HX7c' };
const post = () => new Request('http://x', { method: 'POST', body: '{}' });

function fake(twilio: (body: URLSearchParams) => Response) {
  const calls: { url: string; body: string }[] = [];
  const f = (async (url: string, init: RequestInit) => {
    calls.push({ url: String(url), body: String(init.body) });
    if (String(url).endsWith('/rpc/f360_whatsapp_claim')) {
      return new Response(JSON.stringify([{ id: 'm1', kind: 'thanks', phone: '+528110240698', variables: { 1: 'Polanco', 2: 'Mariana', 3: '100' } },
        { id: 'm2', kind: 'thanks', phone: '+573001234567', variables: { 1: 'en línea', 2: 'Ana', 3: '200' } }]), { status: 200 });
    }
    if (String(url).endsWith('/rpc/f360_whatsapp_result')) return new Response(null, { status: 204 });
    return twilio(new URLSearchParams(String(init.body)));
  }) as typeof fetch;
  return { f, calls };
}

test('waTo: México gets the +521 Twilio form, other countries unchanged', () => {
  assert.equal(waTo('+528110240698'), 'whatsapp:+5218110240698');
  assert.equal(waTo('+5218110240698'), 'whatsapp:+5218110240698');
  assert.equal(waTo('+573001234567'), 'whatsapp:+573001234567');
});

test('sends each claimed message with the approved template and reports the result', async () => {
  const { f, calls } = fake((b) => new Response(JSON.stringify(b.get('To')!.endsWith('4567') ? { code: 63016, message: 'outside window' } : { sid: 'SM1' }),
    { status: b.get('To')!.endsWith('4567') ? 400 : 201 }));
  const out = await (await handleWhatsApp(post(), env, f)).json();
  assert.deepEqual(out, { ok: true, claimed: 2, sent: 1, failed: 1 });
  const tw = calls.filter((c) => c.url.includes('twilio'));
  assert.equal(tw.length, 2);
  const first = new URLSearchParams(tw[0].body);
  assert.equal(first.get('ContentSid'), 'HX7c'); assert.equal(first.get('To'), 'whatsapp:+5218110240698'); assert.equal(first.get('From'), 'whatsapp:+5215500000000');
  assert.deepEqual(JSON.parse(first.get('ContentVariables')!), { 1: 'Polanco', 2: 'Mariana', 3: '100' });
  const results = calls.filter((c) => c.url.endsWith('f360_whatsapp_result')).map((c) => JSON.parse(c.body));
  assert.deepEqual(results.map((r) => [r.p_id, r.p_ok]), [['m1', true], ['m2', false]]);
  assert.match(results[1].p_result, /63016/);
});

test('without the approved template SID nothing is claimed or sent', async () => {
  const { f, calls } = fake(() => new Response('{}'));
  const out = await (await handleWhatsApp(post(), { ...env, TWILIO_THANKS_CONTENT_SID: '' }, f)).json();
  assert.equal(out.skipped, 'sin plantilla aprobada'); assert.equal(calls.length, 0);
});
