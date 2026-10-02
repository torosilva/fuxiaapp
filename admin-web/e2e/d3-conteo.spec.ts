import { expect, test, type Browser, type Page } from '@playwright/test';

// Track D · D3 — opening count walkthrough (STAGING) with two real people: Carolina counts (1), Mario counts blind (2).
// Uses the real staging homologation (Paula) and Bodega CDMX but writes ONLY count rows — never inventory. The count is
// cancelled at the end; the session is then removed with scripts/f360/d3_test_session_cleanup.mjs (screen test only).
const SHOTS = 'e2e-screenshots/d3-conteo';
const PEOPLE = {
  carolina: { email: 'carolina.demo@staging.invalid', password: process.env.STAGING_DEMO_CAROLINA_PASSWORD ?? '', name: /Carolina/ },
  mario: { email: 'mario.demo@staging.invalid', password: process.env.STAGING_DEMO_MARIO_PASSWORD ?? '', name: /Mario/ },
};

async function login(browser: Browser, who: keyof typeof PEOPLE): Promise<Page> {
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 1000 }, locale: 'es-MX' });
  const page = await ctx.newPage();
  await page.goto('/login');
  await page.getByLabel('Correo').fill(PEOPLE[who].email);
  await page.getByLabel('Contraseña').fill(PEOPLE[who].password);
  await page.getByRole('button', { name: 'Entrar', exact: true }).click();
  await expect(page.getByRole('heading', { name: PEOPLE[who].name })).toBeVisible();
  return page;
}
const fill = async (page: Page, color: string, values: Record<string, number>) => {
  const row = page.getByTestId(`count-color-${color}`).first();
  for (const [size, n] of Object.entries(values)) await row.getByLabel(`${color} talla ${size}`).fill(String(n));
  await row.getByRole('button', { name: `Guardar ${color}` }).click();
  await expect(row.getByText(`${color}: guardado.`)).toBeVisible();
};

test('D3 · conteo de apertura: doble conteo, reconteo, sin ficha, congelar, reconciliar, reporte', async ({ browser }) => {
  test.setTimeout(240_000);
  const car = await login(browser, 'carolina');
  const errors: string[] = [];
  car.on('pageerror', (e) => errors.push(e.message));

  await car.goto('/conteo');
  await car.getByLabel('Nota').fill('Prueba de pantalla (se cancela al final)');
  await car.getByRole('button', { name: 'Iniciar conteo' }).click();
  await expect(car.getByTestId('count-status')).toHaveText('Conteo preliminar');
  await car.screenshot({ path: `${SHOTS}/01-inicio.png` });

  // count 1 — Carolina
  await fill(car, 'Azul marino', { 35: 2, 36: 1, 37: 0, 38: 3, 39: 1, 40: 0 });
  await fill(car, 'Bambi', { 35: 1, 36: 1, 37: 1, 38: 0, 39: 0, 40: 0 });
  await car.getByTestId('count-model-Paula').screenshot({ path: `${SHOTS}/02-conteo-1.png` });

  // count 2 — Mario, blind
  const mar = await login(browser, 'mario');
  await mar.goto('/conteo?vista=conteo2');
  const blind = mar.getByTestId('count-color-Azul marino').first();
  await expect(blind.getByLabel('Azul marino talla 38')).toHaveValue('');           // count 1 is not shown
  await expect(blind.getByText('Conteo 1 hecho').first()).toBeVisible();
  await fill(mar, 'Azul marino', { 35: 2, 36: 1, 37: 0, 38: 2, 39: 1, 40: 0 });      // 38 differs (3 vs 2)
  await fill(mar, 'Bambi', { 35: 1, 36: 1, 37: 1, 38: 0, 39: 0, 40: 0 });
  await mar.getByTestId('count-model-Paula').screenshot({ path: `${SHOTS}/03-conteo-2-a-ciegas.png` });

  // recount the difference — Carolina
  await car.goto('/conteo?vista=reconteo');
  const rec = car.getByTestId('count-color-Azul marino').first();
  await expect(rec.getByText('C1 3 · C2 2')).toBeVisible();
  await rec.screenshot({ path: `${SHOTS}/04-reconteo.png` });
  await fill(car, 'Azul marino', { 38: 2 });

  // pairs without a model
  await car.goto('/conteo?vista=sinficha');
  await car.getByLabel('Descripción').fill('Mule beige sin etiqueta');
  await car.getByLabel('Talla sin ficha').fill('37');
  await car.getByLabel('Pares sin ficha').fill('1');
  await car.getByRole('button', { name: 'Anotar' }).click();
  await expect(car.getByText('Mule beige sin etiqueta · talla 37')).toBeVisible();
  await car.getByTestId('unlisted').screenshot({ path: `${SHOTS}/05-sin-ficha.png` });

  // freeze + reconcile: approval stays blocked and says why
  await car.getByRole('button', { name: /Congelar bodega/ }).click();
  await expect(car.getByTestId('count-status')).toHaveText('Bodega congelada');
  await car.getByRole('button', { name: 'Reconciliar ventas y movimientos' }).click();
  await expect(car.getByText(/Reconciliado/)).toBeVisible();
  await expect(car.getByTestId('blockers')).toContainText('sin doble conteo');
  await expect(car.getByRole('button', { name: 'Aprobar conteo' })).toBeDisabled();
  await car.screenshot({ path: `${SHOTS}/06-congelado-bloqueos.png` });

  // report
  await car.goto('/conteo?vista=reporte');
  await expect(car.getByTestId('count-report')).toContainText('Opening balance propuesto');
  await car.getByTestId('count-report').screenshot({ path: `${SHOTS}/07-reporte.png` });
  await car.goto('/conteo/hoja');
  await car.screenshot({ path: `${SHOTS}/08-hoja-imprimible.png` });

  // cancel (screen test only) — the freeze is released
  await car.goto('/conteo');
  await car.getByRole('button', { name: 'Cancelar conteo' }).click();
  await car.getByLabel('Motivo de cancelación').fill('Prueba de pantalla terminada');
  await car.getByRole('button', { name: 'Cancelar conteo' }).last().click();
  await expect(car.getByRole('button', { name: 'Iniciar conteo' })).toBeVisible();
  expect(errors).toEqual([]);
});
