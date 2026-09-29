# Customer 360 / CRM / Growth — Data audit (B0)

Date: 2026-09-25. Sources:
- the production **schema** snapshot (`docs/fuxia360/audit/live/schema.sql`, structure only, no rows);
- the integration audit (`INTEGRATION_AUDIT.md`);
- read-only row **counts** in Supabase **staging**.

No production rows were read. Per Q6, production customer data is not exported.

## 1. Where the data actually lives

| # | Source | What it contains | Coverage | Who writes it |
|---|---|---|---|---|
| S1 | **WooCommerce (production)**, orders | Every ecommerce order: items (SKU, qty, price), totals, status, refunds, billing/shipping address (city, state, country, CP), email/phone, date. Plus coupons | **All ecommerce, all history**. The only complete ecommerce source | Woo checkout |
| S2 | `public.transactions` + `public.purchase_items` | Woo orders (and some store/app sales) **linked to a loyalty member**: amount, status, points, pairs, channel (`web`/`store`/`app`); items with SKU, name, size, color, category, qty, unit price | **Partial.** Only loyalty members, only since the loyalty webhook went live. `purchase_items.category` depends on what the webhook copied | `woocommerce-webhook` (loyalty) |
| S3 | `public.unmatched_orders` | Woo orders whose phone/email didn't match a member: total, pairs, items, phone, email | **Partial.** Non-members since the webhook went live. Can later be linked (`link-orders`) | `woocommerce-webhook` |
| S4 | `public.offline_sales` | Physical sales **registered in the app** (code/QR claim): channel (store/bazaar), staff, customer phone, items, total | **Partial.** Only sales staff registered in the app; POS/cash sales outside the app are missing | App staff flow |
| S5 | `public.customers` | Loyalty/app members: phone (NOT NULL), name, email, country (default MX), `wc_customer_id`, `auth_user_id`, birthday, shoe size, referral | **Members only.** No city/state | App sign-up / OTP |
| S6 | `public.loyalty_cards`, `tier_config`, rewards, `referrals`, `pending_credits` | Points, tier (bronze/silver/gold), pairs count, last purchase, referrals, popup credits (origin) | **Reliable for loyalty itself** | Loyalty functions |
| S7 | `f360.inventory_events` (SALE) + `f360.woo_order_lines` | P2.3A: online sales of **F360-managed products**: variant, qty, order id, date. **No customer, no price** (PII minimized by design) | **New products only**, from P2.3A on | `f360-woo-orders` |
| S8 | Mario (verbal) | Revenue **2025 ≈ $5.5M MXN**, **2026 ≈ $6M MXN** | Unverified; source, scope and channels unknown | — |

**Staging today** holds only synthetic lab data: 5 customers (all 555-01xx test phones), 4 loyalty cards, 1 transaction, 1 purchase item (no category), 2 offline sales, 2 unmatched orders, 3 F360 test sales. It is enough to test logic, **not** to produce any real metric.

## 2. Metric-by-metric classification (with the sources that exist today)

"Confiable" means complete and correct for the question. "Parcial" means a correct subset that must not be read as the total. "No disponible" means no accessible source.

| Metric / question | Status | Why |
|---|---|---|
| Total revenue (all channels) | **No disponible** | Ecommerce total only in Woo (S1, not connected). Physical sales outside the app are not recorded anywhere accessible. S8 is unverified |
| Ecommerce revenue | **No disponible hoy** (source exists: S1) | Needs an approved read of Woo orders history (decision D-G1) |
| Revenue of loyalty members | Parcial | S2 (members only, since webhook go-live) |
| Physical-channel revenue | Parcial | S4 only covers app-registered sales |
| New vs returning | No disponible | Needs the full order history per customer identity (S1 + identity resolution) |
| AOV | Parcial | S2+S3 give Woo orders since webhook go-live; not the full history |
| Purchase frequency / time to repurchase | No disponible (reliably) | Requires a stable customer key across all orders (D-C1..C3) |
| Revenue by model / color / size | Parcial | S2/S3 items (since webhook go-live); legacy SKUs are free-form (92/129 have SKU). F360 products: units only (S7) |
| Models acquiring new customers | No disponible | Needs first-order detection over full history |
| Second-purchase products, categories bought together | No disponible (reliably) | Same as above |
| City / state revenue, penetration | **No disponible** | Only in Woo billing/shipping (S1). `customers` has only country |
| Acquisition channel | No disponible (mostly) | Only fragments: referrals, popup credit origin, `transactions.channel`. No UTM / order attribution stored |
| % revenue from CRM / repurchase | No disponible | No campaigns exist yet; needs attribution rules (D-G3) |
| Shoes vs accessories | **No disponible / undefined** | The live catalog shows only 4 shoe categories (Ballerinas, Sandalia Plana, Sandalia Alta, Botas); no accessories category was observed. Needs a definition (D-G2) |
| Loyalty tier / points per member | **Confiable** | S6 (the loyalty system itself) |
| Cancellations / refunds | Parcial | S2 status (`cancelled`/`refunded`, `reversed_at`) for members; Woo has all of them (S1) |
| Online units of F360 products | Confiable (for that scope) | S7, from P2.3A on |

## 3. What this means for the build

- **B1–B3 can be built** as the model, logic, screens and segment definitions, tested on staging data.
- **B1–B3 cannot show real numbers** until an approved, complete source is connected and identity resolution is decided. Screens must say "todavía no hay datos suficientes" per metric, never zero or estimates.
- **B4 (planning)** does not depend on history. It can be built now with **editable assumptions**. "Actual vs objetivo" stays empty until a reliable source exists.
- **Mario's figures (S8)** are **not loaded as facts.** B4 provides a "reported figure" record, with source, period, scope and status "no verificada", to add them formally when Mario confirms.
