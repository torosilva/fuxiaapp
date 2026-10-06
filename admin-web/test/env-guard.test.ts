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
