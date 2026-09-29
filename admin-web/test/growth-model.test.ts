// Run: node --test admin-web/test/growth-model.test.ts
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { computeGrowth } from '../src/lib/growth-model.ts';

test('empty assumptions → only the target math, nothing invented', () => {
  const r = computeGrowth(15_000_000, {});
  assert.equal(r.monthlyTarget, 1_250_000);
  for (const k of ['modeledRevenue', 'gap', 'reachesTarget', 'ordersNeeded', 'customersNeeded', 'aovRequired', 'frequencyRequired'] as const) assert.equal(r[k], null, k);
  assert.ok(r.channel.every((s) => s.amount === null));
  assert.equal(r.regions.length, 0);
});

test('customers × frequency × AOV and the gap to the North Star', () => {
  const r = computeGrowth(15_000_000, { active_customers: 3000, orders_per_customer: 1.5, aov: 2800 });
  assert.equal(r.modeledRevenue, 12_600_000);
  assert.equal(r.gap, 2_400_000);
  assert.equal(r.reachesTarget, false);
  assert.ok(Math.abs(r.ordersNeeded! - 5357.142857) < 1e-3);
  assert.ok(Math.abs(r.customersNeeded! - 3571.428571) < 1e-3);
  assert.ok(Math.abs(r.aovRequired! - 3333.333333) < 1e-3);
  assert.ok(Math.abs(r.frequencyRequired! - 1.785714) < 1e-5);
});

test('each "required" value needs its own inputs only', () => {
  const r = computeGrowth(12_000_000, { aov: 3000 });
  assert.equal(r.ordersNeeded, 4000);
  assert.equal(r.customersNeeded, null);
  assert.equal(r.aovRequired, null);
});

test('mix breakdowns split the target; unassigned remainder is shown, not hidden', () => {
  const r = computeGrowth(10_000_000, { ecommerce_pct: 60, new_pct: 30, returning_pct: 70, regions: [{ name: 'CDMX', pct: 40 }, { name: 'Jalisco', pct: 10 }] });
  assert.deepEqual(r.channel.map((s) => [s.label, s.amount]), [['Ecommerce', 6_000_000], ['Tiendas físicas', null], ['Sin asignar', 4_000_000]]);
  assert.deepEqual(r.customerType.map((s) => s.amount), [3_000_000, 7_000_000]);
  assert.deepEqual(r.regions.map((s) => [s.label, s.amount]), [['CDMX', 4_000_000], ['Jalisco', 1_000_000], ['Sin asignar', 5_000_000]]);
});

test('zero or negative inputs never produce numbers', () => {
  const r = computeGrowth(15_000_000, { active_customers: 0, orders_per_customer: 2, aov: 2800 });
  assert.equal(r.modeledRevenue, null);
  assert.equal(r.aovRequired, null);
});
