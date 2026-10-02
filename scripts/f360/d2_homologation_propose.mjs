// STAGING ONLY — Track D2: load the legacy Woo snapshot into f360.legacy_woo_map and write the SYSTEM PROPOSAL
// (model → colour → size) for Carolina to confirm. Never confirms anything; rows decided by a person are skipped by the DB.
// Inputs (read-only evidence, already in the repo): audit/trackd/d1_catalog_staging4.json, d2_sales_by_variation.json,
// d2_prod_vs_staging4.json (must show 0 legacy differences, otherwise abort).
// Output: audit/trackd/d2_proposal.json (what was proposed and why) + the rows in staging.
// Run: scripts/s00a/run.sh ../f360/d2_homologation_propose.mjs [--dry]
import { readFileSync, writeFileSync } from 'node:fs';
import { loadEnv, psql } from '../s00a/lib.mjs';

loadEnv();
const DRY = process.argv.includes('--dry');
const TARGET = 'woo_staging4';
const dir = 'docs/fuxia360/audit/trackd/';
const catalog = JSON.parse(readFileSync(dir + 'd1_catalog_staging4.json', 'utf8'));
const sales = new Map(JSON.parse(readFileSync(dir + 'd2_sales_by_variation.json', 'utf8')).rows.map((r) => [r.variation_id, r]));
const delta = JSON.parse(readFileSync(dir + 'd2_prod_vs_staging4.json', 'utf8'));
if (delta.only_in_production.length || delta.changed.length) throw new Error('ABORT: production differs from staging4; refresh D1 first');

// ── Woo products F360 already manages (published by F360) are not legacy ──
const q = (sql) => psql(sql, {}, { readOnly: true }).split('\n').filter(Boolean);
const published = new Set(q(`select pl.woo_product_id from f360.woo_product_links pl join f360.sales_targets t on t.id = pl.target_id where t.key = '${TARGET}';`).map(Number));
const f360Products = q(`select id || '|' || name || '|' || (exists (select 1 from f360.woo_product_links pl where pl.product_id = p.id))::text || '|' ||
  coalesce((select sum(b.on_hand) from f360.inventory_balances b join f360.product_variants v on v.id = b.variant_id where v.product_id = p.id), 0)
  from f360.products p where p.status = 'active' and p.name not like 'Demo ·%';`).map((l) => { const [id, name, pub, pairs] = l.split('|'); return { id, name, published: pub === 'true', pairs: Number(pairs) }; });

// ── Colour vocabulary (from pa_color terms and the legacy names). Plurals/feminines → one display name. ──
const strip = (s) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
const COLOR = {
  negro: 'Negro', negra: 'Negro', negros: 'Negro', negras: 'Negro', vino: 'Vino', verde: 'Verde', verdes: 'Verde', taupe: 'Taupe',
  cafe: 'Café', cafes: 'Café', dorado: 'Dorado', dorada: 'Dorado', dorados: 'Dorado', doradas: 'Dorado', plata: 'Plata',
  plateado: 'Plateado', plateada: 'Plateado', nude: 'Nude', talco: 'Talco', beige: 'Beige', azul: 'Azul', miel: 'Miel', denim: 'Denim',
  caramelo: 'Caramelo', chocolate: 'Chocolate', bambi: 'Bambi', leopardo: 'Leopardo', camel: 'Camel', ocre: 'Ocre', blanco: 'Blanco',
  blanca: 'Blanco', rojo: 'Rojo', roja: 'Rojo', rojos: 'Rojo', rojas: 'Rojo', bronce: 'Bronce', champagne: 'Champagne', topo: 'Topo',
  gris: 'Gris', rosa: 'Rosa',
};
const MOD = { marino: 'marino', aceituna: 'aceituna' };
const isColor = (w) => strip(w) in COLOR;
// trailing colour phrase: COLOR [MOD] (con|y COLOR [MOD])*
function trailingColor(tokens) {
  for (let i = 1; i < tokens.length; i++) {
    const rest = tokens.slice(i).map(strip); let j = 0; const out = [];
    const color = () => { if (j < rest.length && rest[j] in COLOR) { out.push(COLOR[rest[j]].toLowerCase()); j++; if (j < rest.length && rest[j] in MOD) out.push(MOD[rest[j++]]); return true; } return false; };
    if (!color()) continue;
    let ok = true;
    while (j < rest.length) { if ((rest[j] === 'con' || rest[j] === 'y') && (out.push(rest[j]), j++, color())) continue; ok = false; break; }
    if (ok) { const c = out.join(' '); return { model: tokens.slice(0, i).join(' '), color: c[0].toUpperCase() + c.slice(1) }; }
  }
  return null;
}
const singular = (w) => (/[^aeiou]es$/.test(w) && w.length > 4 ? w.slice(0, -2) : /s$/.test(w) && w.length > 3 ? w.slice(0, -1) : w);
const modelKey = (m) => strip(m).split(/\s+/).map(singular).join(' ');
const cap = (s) => s[0].toUpperCase() + s.slice(1);

// ── Per Woo product: detect model + colour ──
const legacy = catalog.products.filter((p) => !published.has(p.id) && !(p.sku || '').startsWith('F360-'));
const isSize = (a) => strip(a.name).startsWith('medida');
const parsed = legacy.map((p) => {
  const tokens = p.name.trim().split(/\s+/);
  const multi = p.attributes.some((a) => !isSize(a) && a.options.length > 1);
  const t = trailingColor(tokens);
  let r;
  if (multi) r = { model: t ? t.model : p.name.trim(), color: null, how: 'multicolor', note: `Woo: un producto con varios colores (${p.attributes.filter((a) => !isSize(a)).map((a) => a.options.join('/')).join('; ')})` };
  else if (t) r = { model: t.model, color: t.color, how: 'nombre' };
  else {
    const k = tokens.findIndex((w, i) => i > 0 && isColor(w));
    r = k > 0 ? { model: tokens.filter((_, i) => i !== k).join(' '), color: COLOR[strip(tokens[k])], how: 'color_en_medio' } : { model: p.name.trim(), color: null, how: 'sin_color' };
  }
  return { p, ...r, key: modelKey(r.model) };
});

// ── Group by model key; group-level checks ──
const groups = new Map();
for (const x of parsed) (groups.get(x.key) ?? groups.set(x.key, []).get(x.key)).push(x);
const proposals = []; const snapshot = []; const report = [];
for (const [key, xs] of groups) {
  const names = xs.map((x) => x.model); const display = cap(names.sort((a, b) => names.filter((n) => n === b).length - names.filter((n) => n === a).length)[0]);
  const prices = [...new Set(xs.map((x) => Number(x.p.variations[0]?.regular_price)))];
  const cats = [...new Set(xs.map((x) => x.p.categories.map((c) => c.slug).join('|')))];
  const existing = f360Products.find((f) => modelKey(f.name) === key);
  const groupIssues = [];
  if (prices.length > 1) groupIssues.push(`precios distintos en Woo dentro del modelo (${prices.join(' / ')} MXN); en F360 V1 un modelo tiene un precio por mercado`);
  if (cats.length > 1) groupIssues.push(`categorías distintas en Woo (${cats.join(' / ')})`);
  if (existing) groupIssues.push(`ya existe un modelo F360 "${existing.name}" creado aparte${existing.published ? ' y publicado desde F360' : ''}${existing.pairs ? ` (con ${existing.pairs} pares de prueba en staging)` : ''}: decide si es el mismo`);
  for (const x of xs) {
    const reasons = []; let status = 'propuesto'; let confidence;
    if (x.how === 'nombre') { confidence = xs.length > 1 ? 'alta' : 'media'; reasons.push(xs.length > 1 ? `color al final del nombre; ${xs.length} productos Woo con el mismo modelo` : 'color al final del nombre; único producto Woo de este modelo'); }
    if (x.how === 'color_en_medio') { confidence = 'baja'; status = 'requiere_revision'; reasons.push('el color aparece a mitad del nombre'); }
    if (x.how === 'sin_color') { confidence = 'baja'; status = 'requiere_revision'; reasons.push('no se detectó un color en el nombre'); }
    if (x.how === 'multicolor') { confidence = 'alta'; reasons.push(x.note); }
    if (/(-1)+$/.test(x.p.sku || '')) reasons.push(`SKU legacy "${x.p.sku}" es copia de otro producto: no se usa`);
    if (groupIssues.length) { status = 'requiere_revision'; confidence = confidence === 'alta' ? 'media' : confidence; reasons.push(...groupIssues); }
    for (const v of x.p.variations) {
      const size = (v.attributes.find(isSize) || {}).option || '';
      const vColor = (v.attributes.find((a) => !isSize(a)) || {}).option || '';
      const s = sales.get(v.id);
      snapshot.push({ woo_variation_id: v.id, woo_product_id: x.p.id, woo_product_name: x.p.name.trim(), woo_parent_sku: x.p.sku || '', woo_category: x.p.categories.map((c) => c.slug).join('|'),
        woo_size: size, woo_color: vColor, woo_regular_price: v.regular_price, sold_all: s?.sold_all ?? 0, sold_90d: s?.sold_90d ?? 0, snapshot_at: catalog.read_at });
      let row;
      if (!size) row = { status: 'sin_correspondencia', confidence: 'baja', color: null, reason: 'la variación no tiene talla en Woo' };
      else if (x.how === 'multicolor' && !vColor) row = { status: 'requiere_revision', confidence: 'baja', color: null,
        reason: `Woo vende esta talla como "cualquier color": no se puede saber qué color sale. Si no se determina con certeza, queda bloqueada para cutover. ${x.note}` };
      else if (x.how === 'multicolor') row = { status: groupIssues.length ? 'requiere_revision' : 'propuesto', confidence: groupIssues.length ? 'media' : 'alta', color: vColor, reason: ['color tomado de la variación Woo', ...groupIssues].join('; ') };
      else row = { status, confidence, color: x.color, reason: reasons.join('; ') };
      proposals.push({ woo_variation_id: v.id, model: existing ? null : display, product_id: existing ? existing.id : null, color: row.color, size, confidence: row.confidence, reason: row.reason, status: row.status });
    }
    report.push({ woo_product_id: x.p.id, woo_product: x.p.name.trim(), legacy_sku: x.p.sku || null, model: existing ? existing.name : display, color: x.color, how: x.how, variations: x.p.variations.length });
  }
}

const count = (arr, f) => arr.reduce((m, x) => ((m[f(x)] = (m[f(x)] || 0) + 1), m), {});
const summary = { woo_products: legacy.length, variations: snapshot.length, models_proposed: groups.size, by_status: count(proposals, (p) => p.status), by_confidence: count(proposals, (p) => p.confidence) };
writeFileSync(dir + 'd2_proposal.json', JSON.stringify({ generated_at: new Date().toISOString(), target: TARGET, summary,
  models: [...groups.entries()].map(([k, xs]) => ({ key: k, woo_products: xs.map((x) => `${x.p.id} ${x.p.name.trim()}`) })), products: report }, null, 1));
console.log(JSON.stringify(summary, null, 1));
if (DRY) process.exit(0);

const lit = (o) => `$d2$${JSON.stringify(o)}$d2$::jsonb`;
console.log(psql(`select public.f360_legacy_load_snapshot('${TARGET}', ${lit(snapshot)})::text;`).split('\n').pop().slice(0, 400));
console.log(psql(`select public.f360_legacy_propose('${TARGET}', ${lit(proposals)})::text;`).split('\n').pop());
