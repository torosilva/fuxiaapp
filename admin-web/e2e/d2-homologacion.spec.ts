import { expect, test } from '@playwright/test';

// Track D · D2 — Carolina's homologation flow (STAGING).
// 1) The REAL woo_staging4 homologation is only LOOKED AT (no decision is written there: those are Carolina's to make).
// 2) The decisions are practised on the separate channel "demo_d2" (scripts/f360/d2_demo_seed.mjs), models named "Demo · …".
// Writes catalog rows only (Demo models/colours/variants + demo homologation rows). No inventory, no Woo link, no Woo call.
// Runs once per fresh demo channel (confirmations are final for the machine by design).
const EMAIL = 'carolina.demo@staging.invalid';
const PASSWORD = process.env.STAGING_DEMO_CAROLINA_PASSWORD ?? '';
const SHOTS = 'e2e-screenshots/d2-homologacion';

async function login(page: import('@playwright/test').Page) {
  await page.setViewportSize({ width: 1440, height: 1000 });
  await page.goto('/login');
  await page.getByLabel('Correo').fill(EMAIL);
  await page.getByLabel('Contraseña').fill(PASSWORD);
  await page.getByRole('button', { name: 'Entrar', exact: true }).click();
  await expect(page.getByRole('heading', { name: /Carolina/ })).toBeVisible();
}

test('D2 · homologación real (woo_staging4): solo lectura', async ({ page }) => {
  const errors: string[] = [];
  page.on('pageerror', (e) => errors.push(e.message));
  const shot = (n: string, full = true) => page.screenshot({ path: `${SHOTS}/${n}.png`, fullPage: full });
  await login(page);
  await test.step('1 · Homologación real (woo_staging4): solo lectura', async () => {
    await page.getByRole('link', { name: 'Homologación' }).first().click();
    await expect(page.getByRole('heading', { name: 'Homologación' })).toBeVisible();
    const summary = page.getByTestId('homologation-summary');
    await expect(summary).toContainText('792');
    await expect(summary).toContainText('129 productos Woo');
    await expect(page.getByTestId('how-to')).toBeVisible();
    await shot('01-resumen-real', false);
    const paula = page.getByTestId('group-paula');
    await expect(paula).toContainText('Propuesto 90');
    await expect(paula.getByRole('button', { name: 'Revisar y confirmar' })).toBeVisible();
    await paula.getByRole('button', { name: 'Revisar y confirmar' }).click();
    await expect(paula.getByTestId('confirm-panel')).toBeVisible();
    await paula.screenshot({ path: `${SHOTS}/01b-paula-lista-para-confirmar.png` });
    await paula.getByRole('button', { name: 'Cerrar' }).click();   // look only: no decision is written in the real homologation
    const suecos = page.getByTestId('group-suecos cucarrones');
    await suecos.scrollIntoViewIfNeeded();
    await suecos.getByRole('button', { name: /Ver detalle/ }).first().click();
    await expect(suecos.getByTestId(/^variations-/).first()).toBeVisible();
    await suecos.screenshot({ path: `${SHOTS}/02-modelo-propuesto-suecos.png` });
    await page.getByTestId('filter-requiere_revision').click();
    const mules = page.getByTestId('group-mules colectiva');
    await mules.scrollIntoViewIfNeeded();
    await mules.screenshot({ path: `${SHOTS}/03-requiere-revision-cualquier-color.png` });
  });

  expect(errors).toEqual([]);
});

test('D2 · práctica: Carolina agrupa productos Woo por color bajo un modelo F360', async ({ page }) => {
  test.setTimeout(240_000);
  const errors: string[] = [];
  page.on('pageerror', (e) => errors.push(e.message));
  const shot = (n: string, full = true) => page.screenshot({ path: `${SHOTS}/${n}.png`, fullPage: full });
  await login(page);

  await test.step('2 · Canal de práctica: confirmar 3 productos Woo como UN modelo F360', async () => {
    await page.goto('/homologacion?canal=demo_d2');
    await expect(page.getByText(/Demo · homologación/)).toBeVisible();
    await shot('04-practica-antes');
    const g = page.getByTestId('group-cucarron');
    await g.getByRole('button', { name: /Revisar y confirmar|Decidir/ }).click();
    const panel = g.getByTestId('confirm-panel');
    await panel.getByLabel('Nombre del modelo').fill('Demo · Cucarron');
    await expect(panel.getByLabel(/Color F360 de Cucarron nude/)).toHaveValue('Nude');
    await expect(panel.getByLabel(/Color F360 de Cucarron negro/)).toHaveValue('Negro');
    await g.screenshot({ path: `${SHOTS}/05-confirmar-modelo-cucarron.png` });
    await panel.getByRole('button', { name: /Confirmar 3 productos Woo como Demo · Cucarron/ }).click();
    await expect(page.getByTestId('flash')).toHaveText('3 productos Woo confirmados en Demo · Cucarron.');
    await expect(page.getByTestId('group-demo · cucarron')).toContainText('Confirmado 18');
    await page.getByTestId('group-demo · cucarron').screenshot({ path: `${SHOTS}/06-confirmado-un-modelo-tres-colores.png` });
  });

  await test.step('3 · Variaciones "cualquier color": requiere revisión (bloqueadas para cutover)', async () => {
    const g = page.getByTestId('group-mules colectiva');
    const anyRow = g.getByRole('row').filter({ hasText: 'color sin definir' });
    await anyRow.getByLabel(/Marcar Mules Colectiva/).selectOption('requiere_revision');
    await g.getByLabel('Motivo').fill('Woo vende "cualquier color": no sé qué color sale. Bloqueada para cutover hasta corregir Woo.');
    await g.getByRole('button', { name: 'Guardar' }).click();
    await expect(page.getByTestId('flash')).toContainText('marcado “Requiere revisión”');
    await g.getByRole('button', { name: /Revisar y confirmar|Decidir/ }).click();
    const panel = g.getByTestId('confirm-panel');
    await panel.getByLabel('Nombre del modelo').fill('Demo · Mules Colectiva');
    await expect(panel.getByLabel(/Incluir Mules Colectiva$/)).not.toBeChecked();   // any-colour unit never preselected
    await g.screenshot({ path: `${SHOTS}/07-mules-colores-de-la-variacion.png` });
    await panel.getByRole('button', { name: /Confirmar 3 productos Woo como Demo · Mules Colectiva/ }).click();
    await expect(page.getByTestId('flash')).toHaveText('3 productos Woo confirmados en Demo · Mules Colectiva.');
    await page.getByTestId('group-demo · mules colectiva').screenshot({ path: `${SHOTS}/08-mules-confirmado-y-bloqueado.png` });
  });

  await test.step('4 · Conflicto: dos productos Woo no pueden caer en el mismo modelo + color + talla', async () => {
    const g = page.getByTestId('group-croc');
    await g.getByRole('button', { name: /Revisar y confirmar|Decidir/ }).click();
    const panel = g.getByTestId('confirm-panel');
    await panel.getByLabel('Un modelo F360 que ya existe (agrupar)').check();
    const sel = panel.getByLabel('Modelo existente');
    const label = (await sel.locator('option').allTextContents()).find((t) => t.startsWith('Demo · Cucarron —'))!;
    await sel.selectOption({ label });
    await panel.getByLabel(/Color F360 de Croc/).fill('Nude');
    await panel.getByRole('button', { name: /Confirmar 1 producto Woo como Demo · Cucarron/ }).click();
    await expect(panel.getByText(/Conflicto: Demo · Cucarron \/ Nude \/ talla 35 ya está confirmada para "Cucarron nude"/)).toBeVisible();
    await g.screenshot({ path: `${SHOTS}/09-conflicto-rechazado.png` });
  });

  await test.step('5 · Reabrir una confirmación (con motivo)', async () => {
    const g = page.getByTestId('group-demo · cucarron');
    await g.getByRole('row').filter({ hasText: 'Cucarron vino' }).getByRole('button', { name: 'Reabrir' }).click();
    await g.getByLabel('Motivo').fill('Práctica: revisar si el vino es el mismo tono');
    await g.getByRole('button', { name: 'Guardar' }).click();
    await expect(page.getByTestId('flash')).toHaveText('Cucarron vino: reabierto.');
    await expect(page.getByTestId('group-cucarron')).toContainText('Requiere revisión 6');
    await page.reload();
    await shot('10-practica-despues');
  });

  expect(errors).toEqual([]);
});
