// Run: node --test admin-web/test/spend-csv.test.ts
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseCsv, spendRowsFromCsv } from '../src/lib/spend-csv.ts';

test('template CSV maps 1:1, keeps raw values, summarises per currency', () => {
  const csv = 'date,market,platform,account_id,campaign_id,campaign_name,adset_id,adset_name,ad_id,ad_name,creative_id,currency,spend,impressions,clicks\n' +
    '2026-10-01,MX,meta,act_1,120,"Lanzamiento, Paula",220,MX,320,Video 1,420,MXN,1000.50,1200,30\r\n2026-10-02,MX,meta,act_1,120,,,,,,,MXN,0,0,0\n';
  const r = spendRowsFromCsv(csv, { platform: 'meta' });
  assert.deepEqual(r.errors, []);
  assert.equal(r.rows.length, 2);
  assert.equal(r.rows[0].campaign_name, 'Lanzamiento, Paula');
  assert.equal(r.rows[1].adset_id, null, 'empty optional cell → null, not invented');
  assert.equal(r.rows[1].spend, '0', 'a 0-spend day stays an explicit 0');
  assert.deepEqual(r.summary, { from: '2026-10-01', to: '2026-10-02', spend: { MXN: 1000.5 } });
});

test('Meta Ads Manager export (Spanish headers, currency in the spend header, semicolons)', () => {
  const csv = '﻿Día;Identificador de la campaña;Nombre de la campaña;Identificador del anuncio;Importe gastado (MXN);Impresiones;Clics en el enlace\n2026-10-03;120;Paula;320;250.75;900;12\n';
  const r = spendRowsFromCsv(csv, { platform: 'meta', account_id: 'act_9', market: 'MX' });
  assert.deepEqual(r.errors, []);
  assert.deepEqual(r.rows[0], { date: '2026-10-03', market: 'MX', platform: 'meta', account_id: 'act_9', campaign_id: '120', campaign_name: 'Paula',
    adset_id: null, adset_name: null, ad_id: '320', ad_name: null, creative_id: null, currency: 'MXN', spend: '250.75', impressions: '900', clicks: '12' });
});

test('never guesses: missing account / currency / market without a declared value is an error; bad numbers are reported, not fixed', () => {
  assert.ok(spendRowsFromCsv('date,campaign_id,spend\n2026-10-01,1,5\n', { platform: 'meta' }).errors.length >= 3);
  const r = spendRowsFromCsv('date,campaign_id,spend,currency,market,account_id\n01/10/2026,1,"1,200.50",MXN,MX,act_1\n', { platform: 'meta' });
  assert.equal(r.rows[0].spend, '1,200.50', 'raw value kept for the server to reject');
  assert.equal(r.errors.length, 2);
});

test('parseCsv handles quotes, escaped quotes, CRLF and trailing blank lines', () => {
  assert.deepEqual(parseCsv('a,b\r\n"x ""y""",2\r\n\r\n'), [['a', 'b'], ['x "y"', '2']]);
});
