# P2.3B preflight: staging4.fuxiaballerinas.com (real WooCommerce staging), READ-ONLY

**Date:** 2026-09-28.

**Method:**
- Public, unauthenticated GET requests only: REST index, Store API, public HTML (≈20 requests, user agent `Fuxia360-preflight-readonly`).
- No login and no WordPress admin session.
- No REST key, no POST, no form, no cart item, no order.
- Nothing was changed.

**Raw evidence** (public data only, no secrets) is in `docs/fuxia360/audit/live/staging4/`.

**Limit:** everything that needs the WordPress admin or a Woo REST key is marked **UNVERIFIED**. It is not assumed PASS.

## 1. Matrix

| # | Check | Expected | staging4 actual | Status | Action |
|---|---|---|---|---|---|
| E1 | It is staging, not production | Staging host; noindex | `url`/`home` = `https://staging4.fuxiaballerinas.com`; header `x-robots-tag: noindex`; `<meta robots noindex>`; `robots.txt` → `Disallow: /` | PASS | — |
| E2 | HTTPS | HTTPS | HTTP/2 over TLS, valid | PASS | — |
| E3 | REST API and permalinks | `/wp-json` pretty permalinks | `/wp-json/` 200; namespaces `wc/v3`, `wc/store/v1` present | PASS | — |
| E4 | WordPress version | 6.x+ | **7.1.2** (from the `wp-util` asset version; the generator tag is hidden) | PASS (informational) | Confirm in Site Health |
| E5 | WooCommerce version | Compatible with `wc/v3` | **11.1.2** (plugin asset versions) | PASS (informational) | Confirm in admin |
| E6 | Bricks version | Known | Theme Bricks confirmed. The asset `ver=` is a cache-buster (`1790106574`), not a version | UNVERIFIED | Adrián/Mario: Bricks → Settings / Appearance → Themes |
| E7 | Hosting / cache | Known | SiteGround: nginx, `x-httpd`, `x-proxy-cache`. Plugin **sg-cachepress** (SiteGround Optimizer); `sg-security` | WARN | Before P2.3B stock tests, exclude product pages from Dynamic Cache or confirm Woo purges it on a stock change (L8) |
| E8 | Other relevant plugins | — | Seen: `customer-reviews-woocommerce` (**ivole**: sends review emails), `woo-discount-rules`, `nextend-social-login`, **Jetpack** (`jetpack/v4`), WooCommerce.com connection (`wccom-site`), mobile push (`wc-push-notifications`), `sg-ai-studio`. Geo-redirect cookie `fuxia_geo_*` → `/mx/` and `/co/` subfolders (custom code) | WARN | Full plugin list from admin (Plugins page, or the key's `system_status`) |
| E9 | `pa_medida` | Global, terms 35–40 | Global id **1**, terms 35, 36, 37, 38, 39, 40 (128 products each), custom order (`menu_order`) | PASS | — |
| E10 | `pa_color` | Global | Global id **2**, custom order (`menu_order`). Terms: Café, Dorado, Negro, Taupe, Verde, Vino. **No Nude, no Rojo** | WARN | The first publish of Macarena **creates** the terms `Nude` and `Rojo` in the global `pa_color`. That is a store configuration change: **Mario's explicit OK required** (§3) |
| E11 | Categories (ids / slugs) | The 4 real ones | 18 `ballerinas` (75), 19 `botas` (5), 20 `sandalia-alta` (22), 21 `sandalia-plana` (19) | PASS | Map the F360 categories to these **ids** in `woo_category_links` for target `woo_staging4` |
| E12 | Current product structure | Same as the observed live store | 129 variable products. 125 with `pa_medida` only (one product per color); 2 with `pa_color` × `pa_medida`; 1 with local "Colores" × `pa_medida`; 1 with local "medidas". 128 have 6 variations, 1 has 24 | PASS | No "Macarena" and no `F360-*` SKU exist: no collision |
| E13 | Stock management | — | Variations: `max_qty` empty, always `is_in_stock`, `low_stock_remaining` null → Woo does **not** manage stock today. Variation SKU empty (inherits the parent's) | INFO | Our products set `manage_stock` per variation. Legacy products are unaffected |
| E14 | Sold-out behavior | Sold-out sizes not selectable | Cannot be observed: nothing is sold out. The settings "Hide out of stock" / "Out of stock threshold" are not public | UNVERIFIED | Admin: WooCommerce → Settings → Products → Inventory (L2) |
| E15 | Images per variation / gallery | Per-color image | All variations share one image (1 distinct); gallery of 9 images; dropdown selectors (`<select>`), no swatch plugin detected | INFO | Same as the live store; L3 / DW7 storefront work stays out of this step |
| E16 | Price format MXN | Whole pesos | `MXN`, `currency_minor_unit: 0`, "$2,800" | PASS | L6 resolved |
| E17 | Colombia / WCPBC | Known | `/co/` subfolder with a geo popup (`fuxia-geo-*`). The Colombia product page shows **no price** publicly. No WCPBC asset or namespace detected | UNVERIFIED | Admin: which plugin / code makes `/co/`, and how a new product behaves there (hidden? COP price?) (L9 / DW5) |
| E18 | `Authorization` header reaches WordPress | A Woo key is accepted | Without a key → 401 `woocommerce_rest_cannot_view`. With a **deliberately invalid** key, the **same** generic 401 comes back (Woo normally says "Consumer key is invalid") → **the header very probably does not reach PHP** | **WARN (likely BLOCKER for writes)** | Adrián: pass `Authorization` to PHP on SiteGround (e.g. `.htaccess` `SetEnvIf Authorization "(.*)" HTTP_AUTHORIZATION=$1`). Re-test with the real key. Woo's query-string auth over HTTPS is a fallback, but it puts the key in URLs and logs: **not recommended** |
| E19 | WAF / SiteGround security | GETs allowed | Custom user agent allowed; no challenge. `sg-security` active | PASS (for GET) | Writes and media sideload are unverified: they will be seen with the key |
| E20 | staging4 → Supabase Storage (sideload) | Outbound HTTPS to `*.supabase.co` | **Cannot be tested from outside.** It needs a server-side request from staging4 | UNVERIFIED | Adrián: from SSH, `curl -I https://faltxpkaicwpnlqaxrdu.supabase.co/storage/v1/object/public/product-images/<test path>`; plus the PHP max upload size ≥ 10 MB (L4) |
| E21 | Dedicated Fuxia 360 REST key | It exists, staging only | **Unknown.** Keys are listed only in the admin (WooCommerce → Settings → Advanced → REST API). None was used or copied | UNVERIFIED | §3: create **only after your authorization** |
| X1 | Meta / Facebook catalog | Off / isolated (DW6) | No Facebook for WooCommerce namespace, no Meta pixel in the HTML (`facebookAppId` empty is only a Bricks setting). Business Manager can still pull the catalog by feed/URL | UNVERIFIED (no signs) | Admin: Plugins (no "Facebook for WooCommerce") + Commerce Manager: no catalog pointing at staging4 |
| X2 | Customer emails | Disabled or captured | **Unknown.** Plus `customer-reviews-woocommerce` sends review requests after orders, Jetpack can email, and WooCommerce order emails are default-on | **BLOCKER for any order test** | Before P2.3B order tests: a mail catcher or "disable all emails" plugin, or SMTP to a sandbox. Not needed for publishing products only |
| X3 | Payments | Test mode / impossible | The Store API cart lists `payment_methods: []` (block checkout has no gateway). Classic checkout gateways are not public | UNVERIFIED | Admin: WooCommerce → Settings → Payments. Every gateway in **test/sandbox** or off. Required before order tests |
| X4 | Webhooks inherited from production | None pointing outside | **Unknown** (admin only). A cloned site keeps production webhooks (they deliver to real endpoints on product/order events) | **BLOCKER for any write** | Admin: WooCommerce → Settings → Advanced → Webhooks. Pause/delete every webhook whose delivery URL is not a staging endpoint. **Publishing a product triggers `product.created` webhooks** |
| X5 | Analytics / pixels | None sending to production properties | No GA/GTM/Meta/TikTok/Clarity/Hotjar tag in the public HTML. **Jetpack** is present (Stats / WordPress.com sync). WooCommerce.com connection and `wc-telemetry` exist | WARN | Admin: is Jetpack connected to the production WordPress.com site? Disconnect it on staging (the connection is per site; a clone may share the production identity → "Safe Mode") |
| X6 | Other outbound effects of a clone | None | `woo-discount-rules`, Nextend social login (OAuth apps with production redirect URLs), mobile push app | WARN | Admin check only. Not a blocker for publishing |

## 2. L1–L9 against staging4

| L | Assumption | staging4 | Status |
|---|---|---|---|
| L1 | Color order comes from the `pa_color` term order | `pa_color` uses **custom order** (`menu_order`), not alphabetical. New terms (Nude, Rojo) will go to the end until someone reorders them | WARN: Mario decides the order of new colors |
| L2 | Sold-out sizes are offered until selected unless "Hide out of stock" is on | Settings are not public; no sold-out product to observe | UNVERIFIED (admin) |
| L3 | Variation image swaps; the gallery holds every photo | Current products use one shared image; dropdown selectors; Bricks | UNVERIFIED for a F360 product: seen at the first publish |
| L4 | Photos are sideloaded from public Supabase Storage | Outbound request not testable from outside | UNVERIFIED: Adrián's SSH test (E20) |
| L5 | No "Coming soon" / no test mu-plugin | Site is publicly served (with noindex). No "coming soon" page. Mu-plugins not visible | PASS (public) · mu-plugins UNVERIFIED |
| L6 | Whole-peso prices | `currency_minor_unit 0`, "$2,800" | **PASS** |
| L7 | Dedicated Woo key over HTTPS; `Authorization` passes | HTTPS ✔; header **probably stripped** (E18); key existence unknown | **WARN → BLOCKER for writes** until the header is fixed and re-tested |
| L8 | Cache must not serve stale stock | SiteGround Optimizer + nginx proxy cache active (`x-proxy-cache`); geo cookies skip the cache for first visits | WARN: configure the exclusion or purge before stock tests |
| L9 | No Meta sync; WCPBC doesn't break a draft product | No Meta signs publicly; `/co/` mechanism unknown | UNVERIFIED (admin) |

## 3. Minimal setup for Adrián / Mario before the first real write (acceptance)

**A. Before ANY write (product publish):**
1. **Webhooks (X4):** WooCommerce → Settings → Advanced → Webhooks. Pause or delete every webhook inherited from production.
2. **Meta (X1):** confirm that "Facebook for WooCommerce" is not installed or is deactivated on staging4, and that no Commerce Manager catalog reads staging4.
3. **Jetpack (X5):** disconnect it on staging4, or confirm it is not tied to the production WordPress.com site.
4. **Authorization header (E18/L7):** Adrián makes SiteGround pass `Authorization` to PHP. We re-test read-only with the key (`scripts/f360/p23b_preflight.mjs`).
5. **Dedicated REST key (E21):** do not create it until you authorize it. Then create:
   - **Where:** WooCommerce → Settings → Advanced → REST API → *Add key*, on staging4 only.
   - **User:** a dedicated WordPress user, "Fuxia 360 Staging", role **Shop manager**, not an administrator and not Mario's account.
   - **Description:** "Fuxia 360 staging publisher".
   - **Permission:** **Read/Write**. Read is needed for lookups and `system_status`; write is needed for terms, products, variations, stock and media. Woo has no finer scope.
   - **Handling:** the ck/cs is shown once. It goes straight into our staging publisher configuration, never into a chat or the repository.
6. **Mario's OK:** the first Macarena publish creates the `pa_color` terms **Nude** and **Rojo** (global) and one draft product. He also decides where the new colors go in the order (L1).
7. **Outbound (E20/L4):** Adrián checks from SSH that staging4 can fetch a public Supabase Storage URL, and reports the maximum upload size.

**B. Before order / stock tests (the rest of P2.3B):**
1. Emails captured or disabled (X2), including Customer Reviews reminders.
2. Every payment gateway in test mode (X3).
3. Cache exclusion or purge for product pages (L8).
4. The inventory settings (L2) and the `/co/` behavior (E17).
5. The P2.3B order webhook: created later by us, with its own secret, to the staging endpoint.

**Status:** once A.1–A.7 are confirmed, the acceptance test can start with a **draft** publish of Macarena. Until then there is nothing to write.

## 4. Update 2026-09-28: Adrián's confirmations + re-test of the remaining blockers

### 4.1 Confirmed by Adrián (the admin-side facts we could not see)

| Item | Confirmed | Resolves |
|---|---|---|
| Nature | staging4 is an **isolated clone** of production; there is **no Push to Live**; production was not modified | E1 |
| Versions | WordPress **7.1.2**, WooCommerce **11.1.2**, Bricks **2.4.1** | E4, E5, E6 → PASS |
| Payments | Real payments **disabled** | X3 → PASS |
| Email | **Outbound email blocked** (this covers Customer Reviews reminders and Woo emails) | X2 → PASS |
| Tracking / catalogs | Meta, Google for WooCommerce, GTM, Clarity and Joinchat **disabled** | X1, X5 (tracking) → PASS |
| Webhooks | "Fuxia App" and "Loyalty Sync" webhooks **disabled** | X4 → PASS |
| Indexing | Blocked (matches noindex and robots `Disallow: /`) | E1 |
| Storefront | Public PDP available | — |

**Still open, but not blocking a product publish:**
- Jetpack / WooCommerce.com connection identity (X5);
- cache exclusion for stock (L8);
- inventory "hide out of stock" (L2);
- `/co/` behavior (E17 / L9);
- Mario's OK to create the `pa_color` terms Nude and Rojo (E10 / L1).

### 4.2 SECURITY ISSUE: Loyalty Sync webhook secret exposed

**What happened:** the signing secret of the **"Loyalty Sync"** webhook appeared in a screenshot.

**Treatment:** the secret is considered **COMPROMISED**, on production and on every environment that shares it (staging4 is a clone, so it has the same value).
- The value was **not** tested, used, copied or printed by Fuxia 360.
- It is not stored in the repository.

**Why it matters:** anyone with the secret can forge a validly signed "Loyalty Sync" delivery to the receiving endpoint. That is a loyalty-points write path.

**Required actions:**
1. **Rotate the secret before re-enabling the webhook**, anywhere it is active. **Production is included:** if the production webhook is live, rotate it there as well (Adrián / Mario).
2. Update the receiving endpoint with the new secret at the same moment. Until then, the endpoint should reject the old one.
3. Keep the staging4 webhook disabled. If it is ever enabled on staging, it must point to a staging endpoint and use a **staging-only** secret, never the production one.
4. Delete the screenshot from wherever it was shared.

**Owner:** Mario / Adrián. **Status:** OPEN until the rotation is confirmed.

### 4.3 Re-test of the two remaining blockers (read-only; deliberately fake credentials, no real value)

| Blocker | Test | Result | Status |
|---|---|---|---|
| **B1: `Authorization` header / Woo REST** | (a) Woo `GET /wc/v3/system_status` with a fake Basic key. (b) WordPress core `GET /wp/v2/users/me` with fake Basic credentials. Each compared with the same request without credentials | Both return **exactly the same 401 as without credentials** (`woocommerce_rest_cannot_view`, `rest_not_logged_in`). If the header reached PHP over HTTPS, Woo would answer "Consumer key is invalid" and WordPress `invalid_username` | **FAIL (still a blocker)** |
| **B2: staging4 → Supabase Storage** | Can only be tested **from the server**. From outside, the test image returns 200 (`image/png`, 18,562 bytes) | **UNVERIFIED**: needs Adrián | **OPEN** |

**B1, likely causes** (Adrián to check; either one produces this result):
- SiteGround / Apache drops the `Authorization` header before PHP. The usual fix is in `.htaccess`, before the WordPress block: `SetEnvIf Authorization "(.*)" HTTP_AUTHORIZATION=$1`, or `RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]`.
- PHP does not see the request as HTTPS behind the proxy (`is_ssl()` false). WooCommerce then ignores Basic auth, and WordPress refuses Application Passwords.
- A security setting (SG Security) disables Application Passwords. This affects only the core check, not Woo keys.

**B1, how to confirm the fix without a key:** we re-run the same two requests. Woo should answer "Consumer key is invalid" and WordPress `invalid_username`.

**B2, commands for Adrián** (read-only: outbound GETs, nothing is saved in WordPress):
```
# 1 · network from the server
curl -sS -o /dev/null -w "%{http_code} %{content_type} %{size_download}\n" \
  "https://faltxpkaicwpnlqaxrdu.supabase.co/storage/v1/object/public/product-images/f360/MACARENA/NUDE/be223ba2-6d32-407b-92f1-9c2420621ac2.png"
# 2 · the same request through WordPress (what the media sideload will use), from the site root with WP-CLI
wp eval 'print_r(wp_remote_retrieve_response_code(wp_remote_get("https://faltxpkaicwpnlqaxrdu.supabase.co/storage/v1/object/public/product-images/f360/MACARENA/NUDE/be223ba2-6d32-407b-92f1-9c2420621ac2.png", ["timeout" => 20])));'
wp eval 'echo size_format(wp_max_upload_size());'
```
**Expected:** `200 image/png 18562`, then `200`, then a maximum upload size of at least 10 MB.

**Result:** **NOT READY FOR API KEY.** B1 fails, and B2 needs Adrián's server-side test. No key was created; nothing was written to Woo; Macarena was not published.

### 4.4 Correction 2026-09-28: B1 (Authorization header)

**SiteGround support** (after the `.htaccess` rules were added) confirmed from their logs:
- the `Authorization` header **reaches PHP**;
- no security, cache or firewall rule removes it;
- the test requests were cache MISS;
- the 401s came from credential validation.

**Our earlier conclusion was wrong. The fake-credential test cannot distinguish the two cases:**
- **WooCommerce Basic auth:** an unknown consumer key makes it return `false` silently (no "Consumer key is invalid" error; that message belongs to other paths), so the request continues unauthenticated → the same generic `woocommerce_rest_cannot_view`. That is true whether the header arrived or not.
- **WordPress core `users/me`:** Application Passwords are only checked when the current user is determined during a REST request. A plugin that resolves the user earlier (Jetpack, SG Security and Nextend social login are active) produces the same generic `rest_not_logged_in`.
- `/wp-json` advertises `application-passwords`, which confirms that WordPress sees HTTPS.

**New status:**
- **B1 resolved at the server level** (SiteGround evidence).
- **Definitive proof** = the first read-only call (`GET /wc/v3/system_status`) with the real staging key, once it is authorized and created. If that call does not return 200, we go back to SiteGround with the exact request, never with the credential.

**B2** (staging4 → Supabase Storage) is still pending Adrián's SSH / WP-CLI output (§4.3).

**Result:** READY FOR API KEY as soon as B2 passes.

### 4.5 2026-09-29: B2 PASSED → READY FOR API KEY

**Test:** run by Mario over SSH on the SiteGround server, inside `~/www/staging4.fuxiaballerinas.com/public_html`. Read-only commands; nothing changed.

| Test | Expected | Result |
|---|---|---|
| `curl` from the server to the public Supabase Storage test image | `200 image/png 18562` | **`200 image/png 18562`** ✔ |
| `wp_remote_get` through WordPress (the path the media sideload uses) | `200` | **`200`** ✔ |
| `wp_max_upload_size()` | ≥ 10 MB | **256 MB** ✔ |

**B2 PASSED** (L4 resolved). **B1** was resolved at the server level by SiteGround (§4.4); the definitive proof is the first read-only call with the real key.

## **Status: READY FOR API KEY**

**Not done yet:**
- No key created.
- Nothing written to Woo.
- Macarena not published.

**Still open (not blocking the key):**
- rotation of the exposed Loyalty Sync secret (§4.2);
- Mario's OK for the `pa_color` terms Nude / Rojo (E10 / L1);
- cache (L8), inventory setting (L2) and `/co/` (E17), before stock and order tests.

**Operational note:** the SSH key used for this test was exposed in a chat paste (its private part, passphrase-protected). It must be **deleted in SiteGround** (Developers → SSH Keys Manager) once the test is over.

### 4.6 2026-09-29: first authenticated read with the dedicated staging key

**Key setup (authorized by Mario):**
- A dedicated WordPress user `fuxia360-staging` (Shop manager) with a Woo key "Fuxia 360 staging publisher" (Read/Write), created by Mario on staging4.
- The ck/cs lives only in `tools/siteground-staging.env` (gitignored, mode 600); it was never pasted anywhere.

**The run:** `node scripts/f360/p23b_preflight.mjs tools/siteground-staging.env`. Read-only (GET only); it refuses production hosts and prints no credential.

| Check | Result |
|---|---|
| Woo REST key accepted | **PASS, HTTP 200** → **B1 definitively resolved** (the `Authorization` header reaches WooCommerce) |
| Versions | WordPress 7.1.2 · WooCommerce 11.1.2 · PHP 8.2.34 · theme "Bricks Child Theme 1.1" (Bricks 2.4.1 per Adrián) |
| Meta / Facebook for WooCommerce | PASS: not active. The only Facebook plugin is `nextend-facebook-connect` (social **login**, not catalog sync) |
| WCPBC / swatch plugins | none detected (the `/co/` geo behavior is custom code) |
| Cache | `sg-cachepress` (L8 still to configure before stock tests) |
| WP-Cron | **WARN** `wp_cron=false`: WP-Cron is disabled (SiteGround usually runs a real cron). To confirm before the P2.3B order webhook, because Woo delivers webhooks through Action Scheduler |
| Currency | MXN · 0 decimals |
| `pa_color` / `pa_medida` | ids 2 / 1. Sizes 35–40 all present. `pa_color` has no Nude / Rojo (Mario's OK needed); order is `menu_order` |
| Categories | ballerinas 18 · sandalia-plana 21 · sandalia-alta 20 · botas 19 → to record in `f360.woo_category_links` for the staging4 target |
| Stock management | `woocommerce_manage_stock=yes` |
| Hide out of stock | `no` → sold-out sizes are listed until selected (L2 = the storefront decision stays open) |
| Webhooks | The 2 inherited webhooks (`order.created`, `order.updated`) point to **production Supabase** (`tgzgiwfzddsghnxgkcqd`) and are **disabled** ✔. **They must stay disabled on staging4.** No Fuxia 360 order webhook exists yet |
| F360 products in the store | none |

**Status:**
- **READY FOR FIRST PUBLISH**, pending only Mario's OK for the `pa_color` terms Nude / Rojo and the explicit go-ahead to publish Macarena as a **draft**.
- Nothing has been written.

### 4.7 2026-09-29: FIRST REAL WRITE: Macarena published to staging4 as a DRAFT

**Authorized by Mario:** create the `pa_color` terms Nude / Rojo (appended at the end of the order) and publish Macarena as a draft.

**1 · Target** (`scripts/f360/woo_staging4_target.mjs`):
- `woo_staging4` is registered (https://staging4.fuxiaballerinas.com, not production, fulfillment = Bodega CDMX).
- Category links: ballerinas 18 · sandalia-plana 21 · sandalia-alta 20 · botas 19. They were looked up by slug once; read-only.
- The local Docker target `woo_local` is **deactivated**, not deleted; reactivable. Only one test store is active, so the product screen does not hit "más de una tienda en línea".
- `online_location` is still Bodega CDMX.

**2 · Publish** (`scripts/f360/publish_staging4.ts Macarena`):
- Path: the exact P2.2 publisher (`f360_request_publish` → `f360-woo-publish` handler), as Carolina (owner).
- Result: **job `succeeded` in 26.5 s**.
- Terms: `pa_color` **Nude (id 42) and Rojo (id 43) created**; Negro and sizes 35–40 reused.
- Product: **id 3621**, `F360-MACARENA`, type variable, **status `draft`**, category Ballerinas.
- Photos: 6, sideloaded from public Supabase Storage (L4 confirmed in practice).
- Variations: **18** (3 colors × 35–40), all with an `F360-MACARENA-{COLOR}-{SIZE}` SKU, `manage_stock` on.
- Stock pushed = Bodega CDMX availability: NUDE-35 = 4, NUDE-37 = 4, NUDE-39 = 4, NEGRO-37 = 1; the rest 0.
- Read-back verification: "1 producto (draft), 18 variaciones, todo coincide".

**3 · Independent verification** (read-only):
- **Authenticated API:** `GET /wc/v3/products/3621` → draft, 6 images, attributes Color Nude/Rojo/Negro × Medida 35–40; variation NUDE-37 `manage_stock` true, stock 4, its own image.
- **Public Store API:** a search for "Macarena" returns **0**.
- **Public URL of the draft without a session:** **404**. **Nothing is public.**

**Not done:**
- no publish (public) status;
- no webhooks, orders or stock-sync worker for staging4;
- no Meta;
- no production.

**Next P2.3B steps** (separate approval each):
1. Mario / Carolina review the draft in wp-admin (preview): photos per color, the Nude / Rojo / Negro order, sizes, how Bricks renders it.
2. Storefront decisions: sold-out sizes (L2), cache (L8), `/co/` (E17).
3. Stock push worker and order webhook for staging4 (confirm WP-Cron / real cron first).
4. Only then, the public visibility test and the first staging order.

### 4.8 2026-09-29: Mario's review of the Macarena draft (preview)

**1 · No color / size selector on the draft preview.** The preview renders a simple add-to-cart (quantity plus button).
- **Macarena's data is correct** (read-only check):
  - `pa_color` and `pa_medida` both `variation: true, visible: true`;
  - 18 variations, all with price 2,800 and purchasable.
  - This is the same shape as the published products.
- **The template supports color × size:** the published 2-attribute product "ByL puntudo" (`/mx/producto/byl-puntudo/`) renders the standard `variations_form` with **both** selects (`pa_color`, `pa_medida`).
- **Likely cause:** the product is a **draft seen through the preview** (`?preview=true`). It is not the publisher.
- **Proposed confirmation** (needs Mario's OK; a write):
  1. Switch Macarena from `draft` to `private`. It is still invisible to the public (the Store API excludes it and its URL gives 404 without a session) but is viewable by logged-in admins at its normal URL.
  2. Check that the selectors appear.
  3. Return it to `draft`.
- **Separately:** the *improved* selector that was planned (color/size buttons instead of dropdowns, sold-out sizes blocked, gallery per color: plan §I, L2 / L3, DW7) is **storefront work not done yet**. It needs a Bricks / snippet change, Adrián, and its own approval.

**2 · Choosing another country / currency does not switch.**
- This is **pre-existing custom code of the site**, not Fuxia 360:
  - the `button.fuxia-country-btn` buttons POST `admin-ajax.php` `action=fuxia_set_country`;
  - then they reload the un-prefixed URL (`/producto/…`), and the server geo-redirects to `/mx/` or `/co/` based on the `fuxia_geo_country` / `fuxia_geo_redirect_done` cookies.
- The links stay on staging4 (no production domain in them).
- **Likely causes:**
  - the server keeps the IP-based country or the `fuxia_geo_redirect_done` cookie over the chosen one;
  - or SiteGround's cache serves the earlier redirect.
- **Owner: Adrián**, who wrote that code. First check whether production behaves the same.
- It does not block Fuxia 360 publishing. It matters for E17 (how a new product behaves in `/co/`).

### 4.9 2026-09-29: Macarena switched to PRIVATE; per-country pricing found

**Private (Mario's OK):**
- Woo product 3621 went `draft → private` (one `PUT status`, guarded: it only acted after confirming the product was `F360-MACARENA` in `draft`).
- Public Store API search: 0. Its URL without a session: 404. **Still not public.**
- Mario reviews it logged in at `https://staging4.fuxiaballerinas.com/producto/macarena/`.
- **To revert:** back to `draft` after the review.
- Note: Fuxia 360's `woo_product_links.woo_status` still says `draft`. The publisher does not change the status on update, so a later sync keeps whatever Woo has.

**The country model** (clarified by Mario):
- The URL decides the country: `/mx/…` = Mexico (MXN), `/co/…` = Colombia (COP), no prefix / `/tienda` = rest of the world (USD).
- A visitor without a prefix is geo-redirected by IP (a Mexican IP → `/mx/`).

**How prices per country are stored** (read-only, product "ByL puntudo" and one of its variations):
- **Per zone meta, on the parent and on each variation:**
  - `_mexico_*`, `_colombia_*`, `_resto-del-mundo_*`, each with `_price_method=manual`, `_regular_price`, `_price` and sale fields.
  - Example: `_mexico_regular_price=3000`, `_colombia_regular_price=400000`, `_resto-del-mundo_regular_price=160`. The Woo base `regular_price` is 2800.
- This is the "Price Based on Country" meta format. The plugin does not show under that name in `active_plugins`; its exact origin is to be confirmed.
- **Older, parallel meta:** `_price_cop=420000`, `_price_usd=150`. It differs from the zone values: two sources.

**Consequences for Macarena:**
- It has **no zone prices** (only the base 2,800 MXN).
- In `/co/` and USD it will not show a manual, curated price; at best an automatic conversion, if the zone is set to exchange rate.
- **Pricing-rule decision needed** (not implemented, CLAUDE.md rule 13): Fuxia 360 today holds one MXN price per model (P2.1).
  - **Option A (recommended; matches how the store works today):** Fuxia 360 stores the manual MXN / COP / USD price per model, and the publisher writes the three zones (`price_method=manual`) on the parent and every variation.
  - **Option B:** leave CO / USD to the zone's exchange rate. It requires the zone configuration and accepts non-curated prices.
- Also to decide: the MX zone price versus the base price. For ByL, `_mexico_regular_price=3000` overrides a base 2800.

**The country switch "does not change":**
- The `fuxia-country-btn` buttons save the choice (`admin-ajax fuxia_set_country`), then reload the **un-prefixed** product URL, and the server geo-redirects it again by IP. A visitor in Mexico who picks Colombia lands back on `/mx/`.
- **Fix direction:** the button should navigate directly to the chosen prefixed URL (`/co/…`, `/mx/…`, or the no-prefix USD store), or the redirect must honor the chosen country over the IP.
- To be done in the site's own code (not Fuxia 360); owner to be defined by Mario.

### 4.10 2026-09-29: why no color / size selector shows (not caused by Macarena)

- With Macarena **private**, WooCommerce treats it as variable: the alert "Elige las opciones del producto…" appears, but no selector is visible.
- **Same on the published products:** "ByL puntudo" (color × size) and "Suecos cucarrones azul" (size only).
- **Cause 1:** the store **hides WooCommerce's standard selectors on every product**. The rule sits in the SiteGround-combined CSS, next to the Bricks product-template rules:
  - `.variations, .woocommerce-variation-add-to-cart .variations { display: none !important; }`
  - `.variations { position: absolute; visibility: hidden; height: 0; overflow: hidden; }`
- **Verified:** CSS for a custom size selector (`.fuxia-tallas`, `.fuxia-tallas-botones`, `.fuxia-btn-sistema`, `.fuxia-talla`) is loaded. Its HTML is **not** in the page served to an anonymous visitor: 0 occurrences in `/mx/producto/byl-puntudo/`, and none rendered in a real headless browser either.
- **Correction:** an earlier draft of this note guessed that a WPCode snippet was disabled on staging4. **Mario confirmed the snippets are active.** That guess is withdrawn.
- **Where that selector is generated, and under what conditions, is UNKNOWN.** Nothing further is assumed.
- **Open question:** does the size selector render for a visitor on production, on the same product? This is the only comparison that can separate a staging-only issue from a site-wide one. It needs Mario's permission for one read-only request to a public production page, or a screenshot from Mario.
- **Facts for Fuxia 360:** the Macarena data is correct (color + size variations, price, purchasable). A Fuxia 360 product needs a **color + size** selector (plan §I, L2 / L3, DW7), whatever the existing size-only selector turns out to be.

### 4.11 2026-09-29: verified comparison, production vs staging4 (same product)

**Product:** "Sandalia flip flop plateada con canutillos". Production evidence = Mario's screenshots; staging4 = rendered in a real browser, read-only.

| | Production | staging4 |
|---|---|---|
| `/mx/` price | $2,800 | $2,800 |
| `/co/` price | COP$420,000 | COP$420,000 |
| Size buttons ("TALLA") | **shown**: 23–27 in `/mx/`; 35–40 with a "Colombia / CM" toggle in `/co/` | **not rendered** in `/mx/` or `/co/` (no `.fuxia-tallas` element) |

**Verified facts:**
- The size selector renders on production and **not on staging4**.
- It is the same product, the same template, and country pricing works on both.
- The missing selector on Macarena is part of this staging4-wide difference, not of the Fuxia 360 publish.

**Unknown (not assumed):**
- which code generates the size buttons;
- why it does not render on staging4.

**Next evidence:** either one read-only look at the production page source (needs Mario's OK), or Mario checks WPCode on staging4 for a size-related snippet (the listed snippets are active).

### 4.12 2026-09-29: root difference found (production page source, read-only, authorized by Mario)

**Method:** the same public page (`/mx/producto/sandalia-flip-flop-plateada-con-canutillos/`) on production and staging4, comparing the Bricks elements present in each.

**Result:**
- Production has 34 Bricks elements; staging4 has 32.
- **The only two missing on staging4 are two Bricks "Code" elements:**
  - `brxe-cshkxp` (`data-script-id="cshkxp"`): **the size selector** (`.fuxia-tallas`, with the Colombia / CM toggle), right after the product description;
  - `brxe-jailki`: **the site footer** (`.fx-footer`).
- The other two Code elements on that page (`brxe-yjjmxd`, `brxe-hrandx`) render on both sites.
- `fuxia-tallas` appears 11 times in the production HTML and 0 times on staging4.

**Not distinguishable from outside:**
- (a) the two elements are absent from staging4's Bricks product template (an older template);
- (b) they exist but Bricks does not output them.

**Decisive check (Mario, 1 step):**
- In staging4 → Bricks → Templates → the single-product template → Edit with Bricks: is the size "Code" element there (and the footer one)?
- **If present:** check for Bricks' code-signature warning. The fix is Bricks → Settings → Custom code → Regenerate code signatures.
- **If absent:** export the template from production and import it into staging4.

**Not a Fuxia 360 publish issue:** Macarena's data is correct, and country prices render identically on both sites.

### 4.13 2026-09-29: CAUSE CONFIRMED: invalid Bricks code signatures on staging4

**Evidence:** read-only WP-CLI on staging4, run by Mario.
- The size selector element `cshkxp` is in the single-product template (post **1955**, `_bricks_page_content_2`). The footer `jailki` is in post **38** (`_bricks_page_footer_2`). The page does use template 1955 (`qpijfe` is there).
- `cshkxp` settings: `code`, `executeCode`, `signature`, `user_id`, `time`, `_cssCustom`, `cssCode`.
- Bricks global setting `executeCodeEnabled=1`.
- **Signature check:** `\Bricks\Helpers::verify_code_signature()` → **INVALIDA** for both `cshkxp` and `jailki`, and `wp_hash(code)` does not match the stored signature either. Bricks only runs code elements whose signature verifies; staging4 is a copy with its own keys.

**Fix (staging4 only; Mario, in wp-admin):**
1. Bricks → Settings → Custom code → **Regenerate code signatures**.
2. Purge the SiteGround cache.

**Then:** re-render a legacy product (expect `.fuxia-tallas` and `.fx-footer`) and the private Macarena (color + size).

### 4.14 2026-09-29: FIXED on staging4 + what the size selector covers

**Fix applied by Mario:** Bricks → Settings → Custom code → **Regenerate code signatures** (Bricks 2.4.1), on staging4.

**Verified after** (real browser, cache bypassed), "Sandalia flip flop plateada con canutillos":

| Page | Size buttons | Footer |
|---|---|---|
| `/mx/` | shown: Colombia/CM toggle · 23, 24, 25, 25.5, 26, 27 | shown |
| `/co/` | shown: Colombia/CM toggle · 35–40 | shown |

staging4 now matches production.

**What the existing size selector does**, from its code (element `cshkxp`, 4.4 KB):
- It sets only `select[name="attribute_pa_medida"]`: **size**.
- It has **no reference to `pa_color`**.
- WooCommerce's standard selects stay hidden by CSS (`.variations { display: none }`).
- **Consequence for a Fuxia 360 product with color × size** (Macarena): the size can be chosen, the color cannot. This is the planned storefront work (plan §I, L2 / L3, DW7): add color selection to the same element, image per color, sold-out sizes disabled.
- Legacy products (size only) must keep working unchanged.

### 4.15 2026-09-29: color + size selector LIVE on staging4 (verified)

**Change:**
- The Bricks product template's size Code element (`cshkxp`, post 1955) now contains the original size code **unchanged**, followed by the Fuxia 360 color selector (`tools/storefront/f360-tallas-y-color-completo.html`; the color part alone is `tools/storefront/f360-selector-color.html`).
- Saved by Mario, then **Regenerate code signatures** and a cache purge.
- **Lesson:** on staging4, editing a code element in the builder left a stale signature. After every code edit: Regenerate code signatures.

**Live verification** (real browser, cache bypassed):

| Page | Color | Sizes | Choice → WooCommerce |
|---|---|---|---|
| ByL puntudo `/mx/` | Café · Dorado · Negro · Verde · Vino, above the sizes | 23–27 (CM) | Negro + size → variation 376 found |
| ByL puntudo `/co/` | same | 35–40 | Negro + size → variation 376 |
| Flip flop (size only) `/mx/` and `/co/` | **none** (unchanged) | 23–27 / 35–40 | size → variation 3443 |

- JavaScript errors: 0 on every page.
- **Not verifiable on public products:** the photo per color and the struck-through sold-out sizes. No public product has per-color images or managed stock; Macarena, which is private, has both. **Mario checks Macarena logged in.**
- **Expected on Macarena:**
  - Nude: 35 / 37 / 39 available, the other sizes struck through, nude photo;
  - Negro: only 37;
  - Rojo: all struck through.

### 4.16 2026-09-29: which price the storefront shows per country (verified) + store availability request

**Macarena in `/co/` shows "COP$2,800"**: the MXN base amount with a COP symbol. Macarena has no Colombia / USD price.

**Source of truth for country prices** (read-only, verified by comparing meta against the rendered price):

| Product (variation meta) | `_colombia_regular_price` (zone) | `_price_cop` | `_resto-del-mundo_regular_price` | `_price_usd` | Shown in `/co/` |
|---|---|---|---|---|---|
| ByL puntudo | 400000 | **420000** | 160 | 150 | **COP$420,000** |
| Flip flop plateada | (none) | **420000** | (none) | 170 | **COP$420,000** |

**Conclusion:** the storefront uses the **per-variation meta `_price_cop` / `_price_usd`**. The `_{zone}_*` meta is leftover and not used for display.

**Therefore the Option A implementation** (pending Mario's decision):
- Fuxia 360 stores a COP and a USD price per model.
- The publisher writes `_price_cop` / `_price_usd` on every variation.
- Changes: product master fields, the publisher, the Fuxia 360 product screen.

**New requirement (Mario):** in `/mx/`, show **in which physical store** the chosen color and size is available right now.
- **Constraint:** only locations whose stock lives in Fuxia 360 are reliable. Today that is Bodega CDMX; physical stores are still legacy until their C3 cutover.
- **Design pending:** Fuxia 360 would publish per-variation availability by location to Woo meta during stock sync, and the product page would show it when a color and size are chosen.

### 4.17 2026-09-29: prices per currency, built and synced (staging)

**Decision (Mario):**
- Each shoe's price in every currency is set in Fuxia 360, and currencies can be added.
- COP suggestions: 2800 → 420,000; 3000 → 420,000; 4200 → 550,000; 4500 → 600,000.
- **USD rule / amount: pending from Mario.**

**Built:**
- **Migration** `20261005000100_f360_currency_prices.sql` (rollback in `supabase/rollbacks/`):
  - `f360.currencies`: MXN is the base = the Woo price; COP → `_price_cop`; USD → `_price_usd`;
  - `f360.product_prices`, `f360.price_suggestions` (prefill only), and `f360.price_changes` (append-only history);
  - RPCs `f360_list_currencies`, `f360_product_prices`, `f360_set_product_price` (operator+), `f360_save_currency` (owner);
  - `publish_hash` includes prices only when a model has them (published products without prices were not marked as changed);
  - `f360_pub_claim` sends them in the snapshot.
- **Publisher:** writes every active currency price to its store meta key, on the parent and every variation. The verification flags any store value that differs from Fuxia 360.
- **Fuxia 360 Web:** "Precios por moneda" on the product page (with "Usar sugerido") and a new "Monedas" page (owner adds a currency and its store field).

**Tests:**
- publisher 27/27 (2 new);
- DB suite `f360_currency_tests.sql` 23/23; all 11 suites pass (417);
- E2E `admin-web/e2e/precios.spec.ts` passes.
- Six older test files no longer assume lab users C1 / C2 are free: the demo store uses them. Each test now sets its own role / PIN inside its rolled-back transaction.

**Synced to staging4:**
- Macarena's COP 420,000 was set by Carolina from the suggestion.
- Sync `succeeded`, "todo coincide".
- Woo product 3621 is still **private**; `_price_cop=420000` on the parent and **18 / 18** variations; no `_price_usd` yet.
- **Mario checks** `/co/producto/macarena/` logged in; it should show **COP$420,000**.
