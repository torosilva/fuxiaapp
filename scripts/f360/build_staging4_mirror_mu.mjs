// Fuxia 360 · genera los mu-plugins ESPEJO de staging4 a partir de los de producción (tools/storefront/mu-plugins/produccion/).
// Staging4 es una copia nocturna de la tienda real (docs/fuxia360/ops/STAGING_REFRESH.md): sus plantillas esperan las mismas piezas.
// Únicos cambios por archivo: el candado de dominio pasa a staging4 y Supabase de producción pasa a Supabase de staging.
// Salida: tools/storefront/mu-plugins/staging4-espejo/ (commitear; woo_refresh.sh la instala junto con la guardia de staging4).
//   node scripts/f360/build_staging4_mirror_mu.mjs
import { readdirSync, readFileSync, writeFileSync, mkdirSync, rmSync } from 'node:fs';

const SRC = 'tools/storefront/mu-plugins/produccion';
const OUT = 'tools/storefront/mu-plugins/staging4-espejo';
const PROD_SUPABASE = 'https://tgzgiwfzddsghnxgkcqd.supabase.co';
const STAGING_SUPABASE = 'https://faltxpkaicwpnlqaxrdu.supabase.co';
// Hilo solo existe en producción (Railway): en staging4 sus chats crearían casos reales en la Bandeja de prod. No se espeja.
const SKIP = new Set(['f360-hilo.php']);
const GUARDS = [
  [`if ($f360_host !== 'fuxiaballerinas.com' && $f360_host !== 'www.fuxiaballerinas.com') return;   // production store only`,
   `if ($f360_host !== 'staging4.fuxiaballerinas.com') return;   // ESPEJO: solo staging4`],
  [`if ( 'fuxiaballerinas.com' !== $host && 'www.fuxiaballerinas.com' !== $host ) { return; }   // production only`,
   `if ( 'staging4.fuxiaballerinas.com' !== $host ) { return; }   // ESPEJO: solo staging4`],
];

rmSync(OUT, { recursive: true, force: true });
mkdirSync(OUT, { recursive: true });
for (const name of readdirSync(SRC).filter((f) => f.endsWith('.php') && !SKIP.has(f)).sort()) {
  let php = readFileSync(`${SRC}/${name}`, 'utf8');
  let guarded = 0;
  for (const [from, to] of GUARDS) if (php.includes(from)) { php = php.split(from).join(to); guarded++; }
  if (guarded !== 1) throw new Error(`${name}: no encontré exactamente un candado de dominio de producción; revisa el archivo.`);
  php = php.split(PROD_SUPABASE).join(STAGING_SUPABASE).replace(/PRODUCCIÓN/g, 'STAGING4 (espejo)');
  php = php.replace(/^<\?php\n/, `<?php\n// GENERADO por scripts/f360/build_staging4_mirror_mu.mjs desde ${SRC}/${name} — no editar a mano.\n`);
  if (/tgzgiwfzddsghnxgkcqd/.test(php)) throw new Error(`${name}: todavía apunta a Supabase de producción.`);
  if (/'(www\.)?fuxiaballerinas\.com' !==|!== '(www\.)?fuxiaballerinas\.com'/.test(php)) throw new Error(`${name}: quedó un candado de producción.`);
  writeFileSync(`${OUT}/${name}`, php);
  console.log(`espejo: ${name}`);
}
