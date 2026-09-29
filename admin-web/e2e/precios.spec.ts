import { expect, test } from '@playwright/test';

// Prices per currency (staging): Carolina sets Macarena's COP price from the suggestion in the product screen.
// Writes ONE staging price (Macarena, COP). USD is left empty until Mario provides the amount.
const EMAIL = 'carolina.demo@staging.invalid';
const PASSWORD = process.env.STAGING_DEMO_CAROLINA_PASSWORD ?? '';
const SHOTS = 'e2e-screenshots/precios';

test('precio COP de Macarena desde la sugerencia', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.goto('/login');
  await page.getByLabel('Correo').fill(EMAIL);
  await page.getByLabel('Contraseña').fill(PASSWORD);
  await page.getByRole('button', { name: 'Entrar', exact: true }).click();
  await expect(page.getByRole('heading', { name: /Carolina/ })).toBeVisible();
  await page.goto('/productos');
  await page.getByRole('link', { name: /Macarena/ }).first().click();
  const cop = page.getByTestId('price-COP');
  await cop.scrollIntoViewIfNeeded();
  await page.screenshot({ path: `${SHOTS}/01-antes.png`, fullPage: true });
  await cop.getByRole('button', { name: /Usar sugerido/ }).click();
  await expect(cop.getByLabel('Precio en COP')).toHaveValue('420000');
  await cop.getByRole('button', { name: 'Guardar' }).click();
  await expect(cop.getByText('Guardado')).toBeVisible();
  await expect(page.getByText(/Cambios pendientes|cambios/i).first()).toBeVisible();
  await page.screenshot({ path: `${SHOTS}/02-cop-guardado.png`, fullPage: true });
  await page.goto('/monedas');
  await expect(page.getByTestId('currency-COP')).toContainText('_price_cop');
  await page.screenshot({ path: `${SHOTS}/03-monedas.png`, fullPage: true });
});
