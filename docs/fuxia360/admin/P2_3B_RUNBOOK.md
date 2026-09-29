# P2.3B runbook — validate Fuxia 360 against the SiteGround staging store

**Status: BLOCKED.** Nothing here has been run. It starts the day Adrián delivers the SiteGround staging copy.

Every step names its command. Steps marked ✋ need Mario's explicit approval of that exact command, because they deploy or write outside local and staging Supabase.

## 0 · What Adrián must deliver

- **The store:** a SiteGround **staging** URL of the real store (same Bricks theme and plugins, not indexed), over HTTPS.
- **Configuration on that staging copy:**
  - customer emails OFF;
  - payment gateway in **test mode**;
  - **Facebook for WooCommerce / Meta catalog sync deactivated** (DW6).
- **Access:**
  - a **dedicated Woo REST key** (Read/Write), user "Fuxia 360 publisher", for staging only;
  - a wp-admin user for Mario/Carolina, for visual checks.
- **Confirmation** of the production store host(s), so the tooling can refuse them.

Create `tools/siteground-staging.env` (gitignored, never pasted in chat):
```
WOO_BASE_URL=https://<staging-host>
WOO_USER=ck_…
WOO_SECRET=cs_…
STAGING_WOO_HOST=<staging-host>
PRODUCTION_WOO_HOSTS=<real-store-host>,www.<real-store-host>
```

## 1 · Preflight (read-only) — REST API, auth header, Meta off, attributes, categories, stock settings, cron

```
node scripts/f360/p23b_preflight.mjs tools/siteground-staging.env
```

It refuses HTTP and production hosts, and writes nothing. **Every FAIL must be fixed before continuing.** Record the 4 category IDs it prints.

## 2 · Register the target in Fuxia 360 staging ✋ (staging DB write)

1. Add a `sales_targets` row `woo_siteground` → the staging URL, Bodega CDMX, `is_production=false`.
2. Add the 4 `woo_category_links` using the IDs from step 1. The `woo_local` target is deactivated, since only one active target is allowed per environment.

This is done by a script modeled on `scripts/f360/woo_local_target.mjs`, reviewed before running.

## 3 · Deploy the three functions to Supabase STAGING ✋

- **Commands:**
  ```
  supabase functions deploy f360-woo-publish f360-woo-sync --project-ref faltxpkaicwpnlqaxrdu
  supabase functions deploy f360-woo-orders --no-verify-jwt --project-ref faltxpkaicwpnlqaxrdu
  ```
- **Secrets** (staging only, set by Mario): `WOO_TARGET_KEY=woo_siteground`, `WOO_BASE_URL`, `WOO_USER`, `WOO_SECRET`, `WOO_WEBHOOK_SECRET`, `F360_SYNC_SECRET`.
- **Scheduler:** every minute, `f360-woo-sync {action:"push"}`; reconciliation per decision SY1.
- **Remote admin:** Vercel staging gets `F360_PUBLISHER_URL=https://faltxpkaicwpnlqaxrdu.supabase.co/functions/v1/f360-woo-publish`. This is not localhost, so the guard allows it.

## 4 · Webhooks over HTTPS ✋ (writes to the staging store)

- Create `order.created` and `order.updated` → `https://faltxpkaicwpnlqaxrdu.supabase.co/functions/v1/f360-woo-orders`, with the `WOO_WEBHOOK_SECRET`.
- Re-run step 1: "Fuxia 360 order webhooks" must be PASS / https.

## 5 · Real publication from Fuxia 360

- **Publish:** in Fuxia 360 staging, open a test model with 3 colors × 35–40, photos, price and category, then **Publicar en tienda online**. Expected: "Publicado en <tienda>, oculto — 18 variaciones".
- **Verify in wp-admin:** 1 draft product, 18 variations, SKUs `F360-…`, the category, the photos. Nothing is public.
- **Publish again** → still 1 product and 18 variations.

## 6 · PDP on Bricks (visual, desktop + phone; Carolina validates)

Preview the draft as admin, or make it visible only in staging.

- [ ] One product page with a **color selector** and a **size selector**; never navigates to another product.
- [ ] Selecting a color swaps the **main photo** to that color. Decide the full per-color gallery (DW7).
- [ ] **Sold-out sizes cannot be selected** (not just "agotado" after choosing). If they can: enable a Bricks swatch setting, a plugin, or the hide-out-of-stock behavior (L2).
- [ ] Color order is acceptable (the `pa_color` term order, L1).
- [ ] Price shows as whole pesos, as in the live store (L6).

## 7 · Cache

- [ ] Change stock in Fuxia 360: Recibir 1 pair. Within 1 minute the push log shows the change, **and the PDP shows it after reload**. If not: purge rules or exclude F360 pages from SiteGround Dynamic Cache / CDN.

## 8 · Test order → inventory → reconciliation

- **Setup:** Macarena / Negro / 37 = 2 in Fuxia and in the store.
- **Order:** a checkout in **test mode** for 1 pair.
- **Expected:** Fuxia 1, store 1, one SALE "Tienda en línea vendió 1 par · Pedido en línea #N".
- **Resend the webhook:** from wp-admin, or by re-saving the order. Nothing changes.
- **Revisar ahora:** "Todo coincide".
- **Measure** the delay from payment to the Fuxia history entry (async delivery by Action Scheduler / cron).

## 9 · Plugins and Meta in the order path

- [ ] Meta sync still OFF after the publish; the catalog did not receive the product.
- [ ] The loyalty webhook still works as before for the same test order (points), with no double stock effect.
- [ ] WCPBC / Discount Rules don't break the F360 product or the order.

## 10 · Exit

- **Record everything:** all results, screenshots, and any new L-findings in `P2_3_STATUS.md`.
- **What stays gated behind P2.4** (separate approval): production publishing, production webhooks, and the storefront changes applied to production by Adrián.
