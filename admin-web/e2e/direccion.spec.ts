import { createHmac } from 'node:crypto';
import { expect, test, type Page } from '@playwright/test';

// I2 · Centro de Inteligencia screens E2E (STAGING ONLY). Demo accounts only, identified by e-mail (never by name):
// mario.demo / carolina.demo (board) and contadora.demo (viewer + finance preparer). The board and the contadora need the
// second factor: each test enrolls a TOTP factor through the real screen (secret read from the page, never printed),
// and afterAll removes the demo accounts' factors with the staging Auth admin API, so they end as they started.
// Writes: only the contadora's own capture (then voided) and a commitment (then cancelled), both labelled "E2E". No FX
// approval is clicked (the button is only asserted).
// Run: set -a; . ~/.fuxia-staging.env; set +a; F360_BASE_URL=https://fuxia360-staging.vercel.app npx playwright test e2e/direccion.spec.ts
const SHOTS = process.env.F360_SHOTS_DIR ?? 'e2e-screenshots/inteligencia';
const API = process.env.STAGING_API_URL ?? '';
const SERVICE = process.env.STAGING_SERVICE_JWT ?? '';
const USERS = {
  mario: { email: 'mario.demo@staging.invalid', pw: process.env.STAGING_DEMO_MARIO_PASSWORD ?? '' },
  carolina: { email: 'carolina.demo@staging.invalid', pw: process.env.STAGING_DEMO_CAROLINA_PASSWORD ?? '' },
  contadora: { email: 'contadora.demo@staging.invalid', pw: process.env.STAGING_DEMO_CONTADORA_PASSWORD ?? '' },
};
if (!/staging|faltxpkaicwpnlqaxrdu/.test(API) && API) throw new Error('Not a staging API: refusing.');

const b32 = (s: string) => { const a = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'; let bits = ''; for (const c of s.replace(/=+$/, '').toUpperCase()) bits += a.indexOf(c).toString(2).padStart(5, '0');
  const out: number[] = []; for (let i = 0; i + 8 <= bits.length; i += 8) out.push(parseInt(bits.slice(i, i + 8), 2)); return Buffer.from(out); };
const totp = (secret: string) => { const ctr = Buffer.alloc(8); ctr.writeBigUInt64BE(BigInt(Math.floor(Date.now() / 30000)));
  const h = createHmac('sha1', b32(secret)).update(ctr).digest(); const o = h[h.length - 1] & 15;
  return String(((h.readUInt32BE(o) & 0x7fffffff) % 1e6)).padStart(6, '0'); };
const shot = (page: Page, name: string) => page.screenshot({ path: `${SHOTS}/${name}.png`, fullPage: true });
const noOverflow = async (page: Page) => expect(await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth)).toBeLessThanOrEqual(1);

// Staging Auth admin API: remove every MFA factor of a DEMO account (cleanup before and after).
async function adminUserId(email: string): Promise<string | null> {
  for (let p = 1; p <= 10; p++) {
    const r = await fetch(`${API}/auth/v1/admin/users?page=${p}&per_page=200`, { headers: { apikey: SERVICE, Authorization: `Bearer ${SERVICE}` } });
    const j = (await r.json()) as { users?: { id: string; email: string }[] };
    const u = j.users?.find((x) => x.email === email);
    if (u) return u.id;
    if (!j.users?.length) return null;
  }
  return null;
}
async function clearFactors(email: string) {
  if (!email.endsWith('@staging.invalid')) throw new Error('demo accounts only');
  const id = await adminUserId(email);
  if (!id) return;
  const r = await fetch(`${API}/auth/v1/admin/users/${id}/factors`, { headers: { apikey: SERVICE, Authorization: `Bearer ${SERVICE}` } });
  const factors = (await r.json()) as { id: string }[];
  for (const f of Array.isArray(factors) ? factors : []) {
    await fetch(`${API}/auth/v1/admin/users/${id}/factors/${f.id}`, { method: 'DELETE', headers: { apikey: SERVICE, Authorization: `Bearer ${SERVICE}` } });
  }
}

async function login(page: Page, who: keyof typeof USERS) {
  await page.addInitScript(() => { try { sessionStorage.setItem('f360-staging-notice', '1'); } catch { /* notice stays */ } });
  await page.goto('/login');
  await page.getByLabel('Correo').fill(USERS[who].email);
  await page.getByLabel('Contraseña').fill(USERS[who].pw);
  await page.getByRole('button', { name: 'Entrar', exact: true }).click();
  await page.waitForURL((u) => !u.pathname.startsWith('/login'));
}
// Enroll a TOTP factor through the real second-factor screen and verify it (lands on the page given by `next`).
async function secondFactor(page: Page) {
  await expect(page.getByTestId('mfa-screen')).toBeVisible();
  await page.getByRole('button', { name: 'Configurar' }).click();
  const secret = ((await page.getByTestId('totp-secret').textContent()) ?? '').trim();
  expect(secret.length).toBeGreaterThan(10);
  await page.getByLabel('Código de 6 dígitos').fill(totp(secret));
  await page.getByRole('button', { name: 'Activar y entrar' }).click();
  await expect(page.getByTestId('mfa-screen')).toHaveCount(0, { timeout: 30_000 });
}

test.beforeAll(async () => { for (const u of Object.values(USERS)) await clearFactors(u.email); });
test.afterAll(async () => { for (const u of Object.values(USERS)) await clearFactors(u.email); });

test('Mario · cockpit (8 cards, seals, FALTA without figures), FX approve button, budget — desktop + mobile', async ({ page }) => {
  test.setTimeout(240_000);
  await page.setViewportSize({ width: 1440, height: 900 });
  await login(page, 'mario');
  await page.goto('/direccion');
  await shot(page, '00-segundo-factor-desktop');
  await secondFactor(page);
  await page.goto('/direccion');

  for (let n = 1; n <= 8; n++) {
    await expect(page.getByTestId(`card-${n}`)).toBeVisible();
    await expect(page.getByTestId(`seal-${n}`)).toHaveText(/Completo|Parcial|Falta fuente/);
  }
  await expect(page.getByTestId('goal-300k')).toContainText('300,000');
  await expect(page.getByTestId('card-2')).toContainText('cálculo, no pronóstico');
  await expect(page.getByTestId('card-2')).toContainText('Mejor mes de los últimos 12');
  // every card sealed FALTA shows no figure (no money amount), only the missing list
  for (let n = 2; n <= 8; n++) {
    const seal = await page.getByTestId(`seal-${n}`).getAttribute('data-seal');
    if (seal !== 'FALTA') continue;
    const card = page.getByTestId(`card-${n}`);
    await expect(card.getByTestId('falta')).toBeVisible();
    const body = (await card.innerText()).split('\n').filter((l) => !/Falta:|actualizado|Fuente/.test(l)).join('\n');
    expect(body, `card ${n} is FALTA but shows a figure`).not.toMatch(/\$\d/);
  }
  await expect(page.getByTestId('fuentes')).toBeVisible();
  await noOverflow(page);
  await shot(page, '01-direccion-desktop');
  await page.goto('/direccion?moneda=mxn');
  await expect(page.getByTestId('consolidado').first()).toBeVisible();
  await shot(page, '02-direccion-consolidado-mxn-desktop');

  await page.goto('/direccion/tipo-de-cambio');
  for (const m of ['2026-05', '2026-06', '2026-07', '2026-08', '2026-09']) {
    await expect(page.getByTestId(`fx-month-${m}-USD`)).toBeVisible();
    await expect(page.getByTestId(`fx-month-${m}-COP`)).toBeVisible();
  }
  await expect(page.getByTestId('fx-month-2026-09-USD').getByRole('button', { name: /^Aprobar/ })).toBeVisible();   // asserted, never clicked
  await expect(page.getByTestId('fx-latest')).toContainText('1 USD =');
  await noOverflow(page);
  await shot(page, '03-tipo-de-cambio-desktop');

  await page.goto('/direccion/presupuesto');
  await expect(page.getByTestId('goals')).toContainText('300,000');
  await expect(page.getByTestId('budgets')).toBeVisible();
  await noOverflow(page);
  await shot(page, '04-presupuesto-desktop');

  await page.goto('/cierre-contable');
  await expect(page.getByTestId('months')).toBeVisible();
  await shot(page, '05-cierre-contable-consejo-desktop');

  await page.setViewportSize({ width: 390, height: 844 });
  for (const [path, name] of [['/direccion', '11-direccion-mobile'], ['/direccion/tipo-de-cambio', '13-tipo-de-cambio-mobile'], ['/direccion/presupuesto', '14-presupuesto-mobile'], ['/cierre-contable', '15-cierre-contable-consejo-mobile']]) {
    await page.goto(path);
    await noOverflow(page);
    await shot(page, name);
  }
});

test('Carolina · cockpit renders; FX page without approve button', async ({ page }) => {
  test.setTimeout(180_000);
  await page.setViewportSize({ width: 1440, height: 900 });
  await login(page, 'carolina');
  await page.goto('/direccion');
  await secondFactor(page);
  await page.goto('/direccion');
  await expect(page.getByTestId('card-8')).toBeVisible();
  await page.goto('/direccion/tipo-de-cambio');
  await expect(page.getByTestId('fx-month-2026-09-USD')).toBeVisible();
  await expect(page.getByTestId('fx-proposed').getByRole('button', { name: /^Aprobar/ })).toHaveCount(0);
  await shot(page, '06-tipo-de-cambio-carolina-desktop');
});

test('Contadora · only Cierre contable, redirected from everything else; capture + void, commitment + cancel', async ({ page }) => {
  test.skip(!USERS.contadora.pw, 'STAGING_DEMO_CONTADORA_PASSWORD missing');
  test.setTimeout(240_000);
  await page.setViewportSize({ width: 1440, height: 900 });
  await login(page, 'contadora');
  await expect(page).toHaveURL(/\/cierre-contable/);
  await secondFactor(page);
  await expect(page.getByRole('heading', { name: 'Cierre contable', level: 1 })).toBeVisible();
  // menu: only Cierre contable
  const nav = page.locator('aside nav');
  await expect(nav.getByRole('link')).toHaveCount(1);
  await expect(nav.getByRole('link', { name: 'Cierre contable' })).toBeVisible();
  // server-side redirect from any other admin page (strategy, customers, users, cockpit, home)
  for (const path of ['/', '/estrategia', '/direccion', '/clientes', '/vendedoras', '/inventario', '/growth']) {
    await page.goto(path);
    await expect(page, `${path} must redirect`).toHaveURL(/\/cierre-contable/);
  }
  await shot(page, '07-cierre-contable-contadora-desktop');

  // capture an amount in the open month, then void it (append-only: both stay in the history)
  const form = page.getByTestId('entry-form');
  await form.locator('select[name=account]').selectOption('opex_other');
  await form.locator('input[name=amount]').fill('1.23');
  await form.locator('input[name=source]').fill('E2E demo staging (no es un dato real)');
  await form.getByRole('button', { name: 'Guardar monto' }).click();
  await expect(page.getByText('Monto guardado')).toBeVisible({ timeout: 30_000 });
  const entry = page.getByTestId('entry').filter({ hasText: 'E2E demo staging' }).filter({ hasText: 'Por aprobar' }).first();
  await expect(entry).toBeVisible();
  await entry.getByText('Anular esta captura').click();
  await entry.getByPlaceholder(/Por qué se anula/).fill('Prueba E2E: se anula');
  await entry.getByRole('button', { name: 'Anular' }).click();
  await expect(page.getByText('Captura anulada')).toBeVisible({ timeout: 30_000 });

  // a commitment, then cancelled with a reason
  await page.getByText('Agregar un compromiso').click();
  const cf = page.getByTestId('commitment-form');
  await cf.locator('input[name=counterparty]').fill('E2E proveedor demo');
  await cf.locator('input[name=due_date]').fill('2026-12-15');
  await cf.locator('input[name=amount]').fill('10');
  await cf.locator('input[name=source]').fill('E2E demo staging');
  await cf.getByRole('button', { name: 'Guardar compromiso' }).click();
  await expect(page.getByText('Compromiso guardado')).toBeVisible({ timeout: 30_000 });
  const c = page.getByTestId('commitment').filter({ hasText: 'E2E proveedor demo' }).first();
  await expect(c.getByRole('button', { name: 'Aprobar' })).toHaveCount(0);   // the contadora never approves
  await shot(page, '08-cierre-contable-con-compromiso-desktop');
  await c.getByText(/Marcar pagado · cancelar/).click();
  await c.getByPlaceholder(/Motivo o referencia/).fill('Prueba E2E: se cancela');
  await c.getByRole('button', { name: 'Cancelar' }).click();
  await expect(page.getByText('Compromiso cancelado')).toBeVisible({ timeout: 30_000 });

  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/cierre-contable');
  await noOverflow(page);
  await shot(page, '17-cierre-contable-contadora-mobile');
});
