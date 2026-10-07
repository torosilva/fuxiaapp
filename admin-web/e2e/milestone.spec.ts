import { expect, test, type Page } from '@playwright/test';

// Product Sprint 1 milestone, exactly as specified:
// login → Inicio → Productos → create Macarena → add Negro → select sizes → Recibir mercancía →
// quantities by size → Bodega CDMX → confirm → success → updated inventory → history.
// STAGING ONLY (demo owner account; password from ~/.fuxia-staging.env).
const EMAIL = 'carolina.demo@staging.invalid';
const PASSWORD = process.env.STAGING_DEMO_CAROLINA_PASSWORD ?? '';
const SHOTS = process.env.F360_SHOTS_DIR ?? 'e2e-screenshots';
const QTY: Record<string, number> = { '35': 2, '36': 3, '37': 4, '38': 2 };   // = 11 pares (Colombian sizes, DW1)

const shot = (page: Page, name: string) => page.screenshot({ path: `${SHOTS}/${name}.png`, fullPage: true });

test('Carolina receives Macarena Negro into Bodega CDMX', async ({ page }) => {
  expect(PASSWORD, 'STAGING_DEMO_CAROLINA_PASSWORD must be set').not.toBe('');
  await page.setViewportSize({ width: 1280, height: 900 });

  // 1 · Login
  await page.goto('/');
  await expect(page).toHaveURL(/\/login/);
  await shot(page, '01-login');
  await page.getByLabel('Correo').fill(EMAIL);
  await page.getByLabel('Contraseña').fill(PASSWORD);
  await page.getByRole('button', { name: 'Entrar', exact: true }).click();

  // 2 · Inicio
  await expect(page.getByRole('heading', { name: /Carolina/ })).toBeVisible();
  await shot(page, '02-inicio');

  // 3 · Productos → Nuevo producto: Macarena, Negro, sizes (default Colombian 35–40)
  await page.getByRole('link', { name: 'Productos', exact: true }).first().click();
  await page.getByRole('link', { name: 'Nuevo modelo' }).click();
  await page.getByPlaceholder('Ej. Macarena').fill('Macarena');
  await page.getByRole('button', { name: 'Negro' }).click();
  for (const s of ['35', '36', '37', '38', '39', '40']) await expect(page.getByRole('button', { name: s, exact: true })).toHaveAttribute('aria-pressed', 'true');
  await shot(page, '03-nuevo-producto');
  await page.getByRole('button', { name: /Guardar producto/ }).click();
  await expect(page.getByText('Producto creado.')).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Macarena' })).toBeVisible();
  await shot(page, '04-producto-creado');

  // 4 · Recibir mercancía (from Inicio)
  await page.goto('/');
  await page.getByRole('link', { name: /Recibir mercancía/ }).click();
  await page.getByRole('button', { name: /Macarena/ }).click();
  for (const [size, n] of Object.entries(QTY)) {
    for (let i = 0; i < n; i++) await page.getByRole('button', { name: `Más talla ${size}`, exact: true }).click();
  }
  await expect(page.getByText('11 pares').first()).toBeVisible();
  await expect(page.getByRole('button', { name: /Bodega CDMX/ })).toHaveAttribute('aria-pressed', 'true');
  await shot(page, '05-recibir-cantidades');
  await page.getByRole('button', { name: /Recibir 11 pares/i }).click();

  // 5 · Success + updated quantities
  await expect(page.getByRole('heading', { name: 'Inventario recibido correctamente' })).toBeVisible();
  await expect(page.getByText('Carolina recibió 11 pares en Bodega CDMX')).toBeVisible();
  await shot(page, '06-recibido');

  // 6 · Product inventory (size × location)
  await page.getByRole('link', { name: 'Ver inventario del producto' }).click();
  const row = page.getByRole('row', { name: /Bodega CDMX/ });
  await expect(row).toContainText('11');
  for (const [, n] of Object.entries(QTY)) await expect(row).toContainText(String(n));
  await shot(page, '07-producto-inventario');

  // 7 · Inventory by location
  await page.getByRole('link', { name: 'Inventario', exact: true }).first().click();
  await expect(page.getByText('Macarena').first()).toBeVisible();
  await shot(page, '08-inventario');

  // 8 · History: the receipt she just created
  await page.getByRole('link', { name: 'Historial' }).click();
  await expect(page.getByText('Carolina recibió 11 pares en Bodega CDMX').first()).toBeVisible();
  await shot(page, '09-historial');
  await page.getByText('Carolina recibió 11 pares en Bodega CDMX').first().click();
  await expect(page.getByText('Este registro es permanente y no se puede modificar.')).toBeVisible();
  await shot(page, '10-movimiento');
});

test('mobile layout (phone) renders the same data', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/login');
  await page.getByLabel('Correo').fill(EMAIL);
  await page.getByLabel('Contraseña').fill(PASSWORD);
  await page.getByRole('button', { name: 'Entrar', exact: true }).click();
  await expect(page.getByRole('heading', { name: /Carolina/ })).toBeVisible();
  await shot(page, 'm1-inicio');
  await page.goto('/recibir');
  await page.getByRole('button', { name: /Macarena/ }).click();
  await expect(page.getByRole('button', { name: 'Más talla 37', exact: true })).toBeVisible();
  await shot(page, 'm2-recibir');
});

test('wrong password is refused', async ({ page }) => {
  await page.goto('/login');
  await page.getByLabel('Correo').fill(EMAIL);
  await page.getByLabel('Contraseña').fill('wrong-password-on-purpose');
  await page.getByRole('button', { name: 'Entrar', exact: true }).click();
  await expect(page.getByText('Correo o contraseña incorrectos.')).toBeVisible();
});

test('a real account WITHOUT a Fuxia 360 role is refused and signed out', async ({ page }) => {
  // Synthetic lab customer C1 (valid login, no f360 role). Same password derivation as whatsapp-otp.
  const salt = process.env.STAGING_OTP_SALT ?? '';
  expect(salt).not.toBe('');
  await page.goto('/login');
  await page.getByLabel('Correo').fill('15550100011@fuxia.app');
  await page.getByLabel('Contraseña').fill(`fuxia_+15550100011_${salt}`);
  await page.getByRole('button', { name: 'Entrar', exact: true }).click();
  await expect(page.getByText('Esta cuenta no tiene acceso a Fuxia 360. Pídele acceso a Mario.')).toBeVisible();
  await page.goto('/');
  await expect(page).toHaveURL(/\/login/);   // session was removed
});
