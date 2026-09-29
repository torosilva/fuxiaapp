import { defineConfig } from '@playwright/test';

// E2E against a running admin-web (default http://localhost:3000) connected to STAGING.
export default defineConfig({
  testDir: './e2e',
  timeout: 90_000,
  workers: 1,
  reporter: [['list']],
  use: { baseURL: process.env.F360_BASE_URL ?? 'http://localhost:3000', locale: 'es-MX', timezoneId: 'America/Mexico_City' },
});
