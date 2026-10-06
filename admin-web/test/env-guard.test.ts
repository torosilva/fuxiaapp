// Run: node --test admin-web/test/env-guard.test.ts
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { environmentProblems } from '../src/lib/env-guard.ts';

const staging = { NEXT_PUBLIC_F360_ENV: 'staging', NEXT_PUBLIC_SUPABASE_URL: 'https://faltxpkaicwpnlqaxrdu.supabase.co', NEXT_PUBLIC_SUPABASE_ANON_KEY: 'sb_publishable_x' };

test('staging deployment without a store key is fine (defaults to staging4)', () => {
  assert.deepEqual(environmentProblems(staging), []);
});
test('staging deployment refuses the production store key', () => {
  assert.ok(environmentProblems({ ...staging, NEXT_PUBLIC_F360_STORE_KEY: 'woo_production' }).some((p) => p.includes('PRODUCCIÓN')));
});
test('store key must look like a channel key', () => {
  assert.ok(environmentProblems({ ...staging, NEXT_PUBLIC_F360_STORE_KEY: 'woo staging; drop' }).some((p) => p.includes('no es una clave')));
  assert.deepEqual(environmentProblems({ ...staging, NEXT_PUBLIC_F360_STORE_KEY: 'woo_staging4' }), []);
});

const prodKey = (ref: string, role = 'anon') => `x.${Buffer.from(JSON.stringify({ ref, role })).toString('base64url')}.y`;
const production = { VERCEL: '1', NEXT_PUBLIC_F360_ENV: 'production', NEXT_PUBLIC_SUPABASE_URL: 'https://tgzgiwfzddsghnxgkcqd.supabase.co',
  NEXT_PUBLIC_SUPABASE_ANON_KEY: prodKey('tgzgiwfzddsghnxgkcqd'), NEXT_PUBLIC_F360_STORE_KEY: 'woo_production' };

test('production deployment: prod URL + prod anon key + woo_production → allowed', () => {
  assert.deepEqual(environmentProblems(production), []);
});
test('production deployment refuses staging pieces, secrets, wrong store and the publisher', () => {
  assert.ok(environmentProblems({ ...production, NEXT_PUBLIC_SUPABASE_URL: 'https://faltxpkaicwpnlqaxrdu.supabase.co' }).length > 0);
  assert.ok(environmentProblems({ ...production, NEXT_PUBLIC_SUPABASE_ANON_KEY: prodKey('faltxpkaicwpnlqaxrdu') }).length > 0);
  assert.ok(environmentProblems({ ...production, NEXT_PUBLIC_SUPABASE_ANON_KEY: prodKey('tgzgiwfzddsghnxgkcqd', 'service_role') }).length > 0);
  assert.ok(environmentProblems({ ...production, SUPABASE_SERVICE_ROLE_KEY: 'x' }).length > 0);
  assert.ok(environmentProblems({ ...production, NEXT_PUBLIC_F360_STORE_KEY: 'woo_staging4' }).length > 0);
  assert.ok(environmentProblems({ ...production, F360_PUBLISHER_URL: 'https://publisher.example' }).length > 0);
  assert.ok(environmentProblems({ ...production, F360_PUBLISHER_URL: 'https://faltxpkaicwpnlqaxrdu.supabase.co/functions/v1/f360-woo-publish' }).length > 0);
  assert.deepEqual(environmentProblems({ ...production, F360_PUBLISHER_URL: 'https://tgzgiwfzddsghnxgkcqd.supabase.co/functions/v1/f360-woo-publish' }), []);
});
test('a staging deployment still may NOT point at production; unknown env names are refused on Vercel', () => {
  assert.ok(environmentProblems({ ...staging, VERCEL: '1', NEXT_PUBLIC_SUPABASE_URL: 'https://tgzgiwfzddsghnxgkcqd.supabase.co' }).length > 0);
  assert.ok(environmentProblems({ ...production, NEXT_PUBLIC_F360_ENV: 'prod' }).length > 0);
});
