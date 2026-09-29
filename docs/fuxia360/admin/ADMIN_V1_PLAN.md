# Fuxia 360 Admin — V1 Vertical Slice (PLAN; not implemented)

**Track:** Product (runs in parallel with the S0.0A security track). **Status:** design for review. Nothing is coded, migrated or deployed.
**User:** Carolina, founder/operator; not technical; avoids inventory software.
**Job:** one simple place to **receive merchandise arriving in Mexico** and **know exactly which variant is at each location**.
**V1 functional modules:** Inicio · Productos · Inventario. The others (Producción, Pedidos, Clientes, Growth) appear in the navigation as honest "Próximamente" pages.
**Workflows:** 1) **Recibir mercancía** 2) **Mover inventario**.

---

## 0. Decisions needed before building (flagged, not invented)

| # | Decision | Why it matters | Recommendation |
|---|---|---|---|
| D1 | **Which locations the new ledger is authoritative for in V1.** The POS still sells from `channel_inventory` (independent numbers per channel) | If stores get Fuxia 360 balances while the POS keeps decrementing `channel_inventory`, there are **two masters** for the same pairs (CLAUDE.md rule 11) | V1 is **authoritative for non-POS locations** (receiving point, bodega, workshop pickup). Stores/bazaars can be *destinations* of transfers, but their card shows a clear badge ("Ventas de tienda aún no descontadas"). They become fully authoritative when POS sales write to the same ledger (S0.3 on this ledger; see D5) |
| D2 | **Where the first products come from** (WooCommerce integration is later) | Step 3 "select an existing product" needs products | V1: **create a product inside the flow** in under a minute (photo, name, colors, size run). Optional: a one-time *read-only* import of names/photos from the public Woo Store API, run by us (not a live sync). Carolina chooses |
| D3 | **Hosting / URL** for the web admin | Carolina opens it in a browser | Vercel (preview on staging → production), later `admin.fuxiaballerinas.com`. Alternative: Supabase-hosted static build. Needs owner account/billing |
| D4 | **Who gets which role** at launch | Permissions are server-enforced | Owner: Carolina, Mario. Operator: a named receiving person (if any). Viewer: none initially. NovaMktLab: no inventory access in V1 |
| D5 | **One ledger, not two.** S0.3 (Q11) planned an `inventory_events` audit row per POS sale keyed to legacy `channel_inventory` | Two parallel ledgers would contradict "no duplicate sources of truth" | This V1 ledger (`f360.inventory_events` / `inventory_movements`) **is** the target. S0.3 writes its SALE events here once POS rows map to variants/locations. Until then, S0.3's legacy audit rows are the "forward-compatible" feed, migrated into this ledger 1:1 (the Sprint 2 path already documented) |
| D6 | ~~Size run 22–27 by halves~~ | — | **Superseded by DW1 (2026-09-24):** canonical sizes are **Colombian** (`35–40`, as in the live Woo catalog). Mexican cm equivalents are a display layer only. See `WOO_PUBLISHING_V1_PLAN.md` |

---

## 1. Screen map

```
Login (teléfono → código)
└── Shell: sidebar on desktop/tablet · bottom bar on phone
    ├── Inicio ──────────────► [Recibir mercancía] [Mover inventario]  (big primary actions)
    │                          Resumen por ubicación · Últimos movimientos
    ├── Productos ───────────► Lista (fotos) ─► Producto ─► Color ─► Matriz talla × ubicación
    │        └── + Nuevo producto (foto, nombre, colores, tallas)       └── Historial del producto
    ├── Inventario ──────────► Por ubicación (chips) ─► Lista de productos en esa ubicación
    │        └── Movimientos (línea de tiempo) ─► Detalle de movimiento (inmutable)
    ├── Producción   (Próximamente: "Pedidos por fabricar, talleres y fechas")
    ├── Pedidos      (Próximamente)
    ├── Clientes     (Próximamente)
    └── Growth       (Próximamente)

Flows (full-screen, step-by-step, can start from Inicio, a Product or a Location):
  Recibir mercancía:  Producto → Color → Tallas y cantidades → Ubicación → Confirmar → Listo
  Mover inventario:   Producto → Color → Desde → Hacia → Tallas y cantidades → Confirmar → Listo
```

## 2. UX, screen by screen

**Design language:**
- premium retail, not an admin panel;
- warm neutral background, black type, Fuxia gold accent (`#B8860B`, as in the app), generous whitespace;
- large product photography; one primary action per screen;
- touch targets ≥ 48 px; tablet-first, fully usable on a phone;
- Spanish copy in business language ("Llegaron productos", "Mover", "Pares"), no database words;
- no tables with more than one screen of columns;
- numbers shown as **pairs** ("12 pares").

### 2.1 Login
Phone field → "Enviar código" → 6-digit code → in. It reuses the existing verified-phone login (`whatsapp-otp`), so there are no new passwords. If the account has no Fuxia 360 role: "Esta cuenta no tiene acceso a Fuxia 360. Pídele acceso a Mario." (no data shown).

### 2.2 Inicio
```
Buenos días, Carolina                                   [foto]
┌────────────────────────────┐  ┌────────────────────────────┐
│  ⬇  Recibir mercancía       │  │  ⇄  Mover inventario        │   ← 2 huge buttons
│  Llegaron productos         │  │  De una ubicación a otra    │
└────────────────────────────┘  └────────────────────────────┘
Pares por ubicación
 Recepción CDMX   184   ·  Tienda Polanco 62 ⓘ  ·  Bazar Octubre 40 ⓘ
Últimos movimientos
 Hoy 11:20  Recibido  Ballerina Classic · Negro · 24 pares → Recepción CDMX   (Carolina)
 Ayer       Movido    Ballerina Classic · Negro · 6 pares  Recepción → Tienda Polanco
```
(ⓘ = D1 badge on POS locations.) No charts in V1.

### 2.3 Productos (list)
Grid of cards: photo, name, color dots, total pairs. Search box ("Busca por nombre o color"). Sort: recently received first. The "+ Nuevo producto" button sits at top right.

### 2.4 Producto (detail)
- Hero photo; name; color swatches as tabs (each with its own photo).
- For the selected color: a **size × location matrix**, with locations as rows and sizes as columns, plus row and column totals. Zero cells are dimmed, not hidden.
- Buttons: "Recibir más" and "Mover", pre-filled with this product and color.
- "Historial": immutable movements for this product (who, when, what, from → to).

### 2.5 Nuevo producto (minimal, under a minute)
- Photo (camera or file).
- Name.
- Colors: add a color = name + optional photo.
- Sizes: preset chips, tap to include or exclude.
- Optional: category.
- "Guardar". This creates the product, its colors, and the variants (color × size).
- No SKU required (generated internally; editable later). No cost or price in V1.

### 2.6 Recibir mercancía (wizard; the core flow)
1. **Producto**: a search box plus recent products with photos. "¿Es nuevo? Crear producto" opens 2.5 inline and comes back.
2. **Color**: big photo swatches.
3. **Tallas y cantidades**: one row per size with − / number / + steppers (large). The live total "24 pares" is shown at the bottom. "Agregar otro color de este producto" repeats steps 2–3 inside the same receipt.
4. **¿Dónde llegó?**: large location cards; the last used is preselected (usually Recepción).
5. **Confirmar**: a summary card (photo, color(s), size breakdown, total pairs, destination, optional note). The primary button reads "Confirmar recepción (24 pares)".
6. **Listo**: "Recibido ✓". It shows the **new balances at that location** for the received variants, with "Recibir otro" and "Ver producto".

Rules:
- Zero-quantity sizes are ignored.
- Confirm is disabled at 0 pairs.
- A double tap can't create a double receipt (idempotency key per wizard session).
- Leaving mid-flow asks "¿Salir sin guardar?"

### 2.7 Inventario
- Location chips at the top (Recepción, Tiendas, Bazares, …) with pair totals.
- Selecting a location shows its products with photo and pairs, expandable to the size breakdown.
- A second tab, "Movimientos", is a timeline filterable by location, product, type (Recepción / Traspaso) and date. Tapping one shows **Detalle de movimiento**: lines, actor, time, "Este registro no se puede modificar."
  - Corrections come later as their own "Ajuste" event (Sprint 2), never as an edit.

### 2.8 Mover inventario (wizard)
Producto → Color → **Desde** (only locations with stock of that color; each card shows its pairs) → **Hacia** (any other active location) → **Tallas y cantidades** (the stepper max is the pairs available at the origin; the available count is shown next to each size) → Confirmar ("Mover 6 pares de Recepción a Tienda Polanco") → **Listo** (both locations' new balances side by side).
Rules: origin ≠ destination; it can't move more than exists (enforced server-side too); one idempotent event.

### 2.9 Placeholder modules
Each has one sentence of what's coming and no fake data. Producción: "Aquí verás los pedidos por fabricar, el taller responsable y la fecha prometida" (the next slice).

---

## 3. Data model (new; in a dedicated schema `f360`)

Why a separate schema:
- `f360` is **not exposed through PostgREST**, so clients have no direct table access at all;
- every read and write goes through RPCs with explicit permission checks;
- it avoids the default `GRANT ALL … TO anon/authenticated` on `public` tables (P0-11);
- legacy `public` tables stay untouched.

| Table | Columns (types abbreviated) | Constraints / notes |
|---|---|---|
| `f360.user_roles` | `auth_user_id uuid PK → auth.users`, `role text` (`owner`/`operator`/`viewer`), `display_name text`, `granted_by uuid`, `created_at` | Written **only** by migrations or service role. **Independent of `customers.role`**, so Fuxia 360 permissions are unaffected by P0-1 |
| `f360.products` | `id uuid PK`, `name text`, `slug text UNIQUE`, `category text null`, `status text` (`active`/`archived`), `tier text null` (A/B/C; later), `image_path text null`, `wc_product_id int null` (later), `created_by uuid`, `created_at`, `updated_at` | name required |
| `f360.product_colors` | `id uuid PK`, `product_id → products`, `name text`, `hex text null`, `image_path text null`, `sort int` | `UNIQUE(product_id, lower(name))` |
| `f360.product_variants` | `id uuid PK`, `product_id`, `color_id → product_colors`, `size text`, `sku text UNIQUE null`, `barcode text null`, `status text`, `make_to_order_eligible bool default false`, `wc_variation_id int null` (later), `created_at` | `UNIQUE(color_id, size)`; SKU auto-generated if empty |
| `f360.locations` | `id uuid PK`, `name text`, `type text` (`receiving`/`warehouse`/`store`/`bazaar`/`workshop`/`other`), `status text` (`active`/`inactive`), `legacy_channel_id uuid null → public.channels`, `pos_managed bool` (D1 badge), `created_at` | Existing channels are mapped, not duplicated |
| `f360.inventory_events` | `id uuid PK`, `event_type text` (`RECEIPT`, `TRANSFER`; later `ADJUSTMENT`, `SALE`, `RETURN`, `RESERVATION`, `RELEASE`, `WRITE_OFF`), `idempotency_key uuid UNIQUE`, `actor_auth_user_id uuid`, `actor_role text`, `note text null`, `business_reference_type text null`, `business_reference_id uuid null`, `occurred_at`, `created_at` | **Append-only:** a trigger rejects UPDATE/DELETE; no client grants |
| `f360.inventory_movements` | `id uuid PK`, `event_id → inventory_events`, `variant_id → product_variants`, `from_location_id uuid null`, `to_location_id uuid null`, `quantity int CHECK > 0` | RECEIPT: from null, to set. TRANSFER: both set and different. Append-only (trigger) |
| `f360.inventory_balances` | `PK(variant_id, location_id)`, `on_hand int CHECK (on_hand >= 0)`, `last_event_id`, `updated_at` | A **derived cache**, updated only inside the same transaction as the movement. A nightly/on-demand **reconciliation query** checks balance = Σ movements in − out |

Deliberately **not** in V1: cost/price, reservations, allocations, production requests (the next slice), Woo mapping writes. The columns reserved for later are nullable and unused.

Storage: product and color photos go to the existing `product-images` bucket under `f360/…`. The upload policy is limited to users with an `f360` role, via a SECURITY DEFINER helper.

## 4. API / server boundaries

**Pattern:**
- The browser talks to Next.js **server actions**, which run as the logged-in user (JWT in an httpOnly cookie via `@supabase/ssr`).
- Server actions call Postgres RPCs, `public.f360_*` functions that are `SECURITY DEFINER`, pin `search_path`, check the role inside, and are EXECUTE-granted **only to `authenticated`** (explicit grants, consistent with A1's hardened defaults).
- **No service-role key in the web app.** The actor always comes from `auth.uid()`, never from the request.

| RPC | Role | Behavior |
|---|---|---|
| `f360_me()` | any f360 role | role, display name (the login gate) |
| `f360_home_summary()` | viewer+ | pairs per location, last 10 events |
| `f360_list_products(q text)` / `f360_get_product(id)` | viewer+ | products with colors, variants and the balance matrix |
| `f360_create_product(name, category, image_path, colors jsonb, sizes text[])` | operator+ | one transaction: product + colors + variants |
| `f360_list_locations()` | viewer+ | active locations and totals |
| `f360_location_inventory(location_id)` | viewer+ | products and sizes at that location |
| `f360_list_events(filters)` / `f360_get_event(id)` | viewer+ | immutable history |
| `f360_receive_inventory(idempotency_key, location_id, lines jsonb[{variant_id, qty}], note)` | operator+ | **atomic:** validates lines, qty > 0, active location/variants; inserts event + movements; upserts balances; returns the event and new balances. Replaying the same key returns the original event |
| `f360_transfer_inventory(idempotency_key, from_id, to_id, lines, note)` | operator+ | **atomic:** from ≠ to; locks the origin balances `FOR UPDATE`; rejects if `on_hand < qty` (no negative stock); one TRANSFER event; decrements the origin, increments the destination |

Validation: Zod in the server actions for UX errors, but the **authoritative checks live in the RPCs**. Errors come back as Spanish messages ("Solo hay 4 pares de talla 24 en Recepción").

## 5. Permission model

| Role | Sees | Can do |
|---|---|---|
| `owner` (Carolina, Mario) | everything in V1 | receive, transfer, create products, manage locations (via us in V1) |
| `operator` (receiving person) | products, inventory, history | receive, transfer, create products |
| `viewer` | products, inventory, history | nothing that writes |
| no role (including any customer, email sign-up, or the review demo) | nothing | nothing (login gate + every RPC denies) |

- Enforcement lives in **the database (RPC checks)**, not hidden menu items (07_ADMIN_WEB §4).
- Roles are granted by migration or service role only; there's no role-management UI in V1.
- Every event records `actor_auth_user_id` + `actor_role`.
- **Security-track dependencies:**
  - V1 authorization does **not** rely on `customers.role` (P0-1) or `user_metadata` (P0-10);
  - **A1 must be in production** before V1 goes to production, so new functions aren't public by default;
  - the `f360` schema isn't exposed, so the P0-11 table defaults don't apply;
  - email sign-up (G5) and the review login (P0-6.3) don't grant f360 access unless a role row exists.

## 6. Relationship to the existing app

| Existing | V1 relationship |
|---|---|
| Mobile app (customers, sellers, current mobile admin screens) | **Unchanged.** It keeps working on the legacy tables |
| `channels` | Mapped to `f360.locations` via `legacy_channel_id`; not modified |
| `channel_inventory` | **Not the source of truth and not modified.** POS stores keep using it until S0.3 + the Sprint 2 cutover (D1). A read-only comparison report (legacy vs f360 per mapped variant) can come later |
| `customers` / loyalty / Woo webhook | Untouched |
| Login | Reuses `whatsapp-otp` (verified phone). Web sessions are the same Supabase Auth users |
| S0.0A migrations | Share `supabase/migrations/`; f360 migrations are ordered after the approved S0.0A units and follow the same staging → production rules |
| Mobile admin screens (`app/admin/*`) | Stay for now; later they either link to or are replaced by the web admin (product decision after V1) |

## 7. Proposed web stack (based on this repo)

- **New app `admin-web/`** at the repo root, next to `fuxia-native/`. No monorepo conversion (02_TARGET_ARCHITECTURE §4); npm, as the repo already uses.
- **Next.js (App Router) + TypeScript**: server actions keep the session and RPC calls on the server; good tablet/phone performance; easy preview deployments.
- **UI:** Tailwind CSS + Radix-based primitives (shadcn/ui style), with Fuxia's own tokens (gold, warm neutrals, large type). Headless primitives give accessibility without an "admin template" look.
- **Supabase:** `@supabase/supabase-js` + `@supabase/ssr` (cookie sessions). Types from `supabase gen types` against staging, committed in `admin-web/`.
- **Validation:** Zod. **Images:** Supabase Storage (`product-images/f360/…`) + Next `<Image>`.
- **Why not Expo Router web (reuse `fuxia-native`)?** It's possible, but a back-office with matrices, deep links and desktop/tablet layouts is better served by a web-native framework, and it keeps the customer app's release cycle (EAS/OTA) separate from the admin's.
- **Environments:** local → staging Supabase (`faltxpkaicwpnlqaxrdu`) + preview URL → production only after approval.

## 8. Implementation sequence

| Step | Deliverable | Verification |
|---|---|---|
| 0 | Decisions D1–D6 | recorded |
| 1 | Migration `f360` schema: tables, constraints, append-only triggers, balance cache, `user_roles`, all RPCs, explicit grants/revokes; paired rollback | staging: automated tests — receive/transfer are atomic; idempotent replay; negative stock rejected; from = to rejected; UPDATE/DELETE on events rejected; a no-role user, E1 and anon are denied; viewer can't write; balance = Σ movements |
| 2 | `admin-web` scaffold: login (phone → code), role gate, shell with the 7 nav items (4 placeholders) | login works on staging with a synthetic owner; no-role account blocked |
| 3 | Productos: list, detail (matrix), Nuevo producto (with photo upload) | create a product with 2 colors × 11 sizes in under a minute |
| 4 | **Recibir mercancía** wizard + Listo screen | end-to-end receipt; balances update; the event appears in the timeline; double-tap safe |
| 5 | Inventario: by location, Movimientos timeline, event detail | numbers match the RPC balances; history is immutable |
| 6 | **Mover inventario** wizard | both balances update; over-transfer blocked with a clear message |
| 7 | Inicio summary | totals per location = sum of balances |
| 8 | Carolina acceptance on staging (tablet + phone) | receives a realistic shipment unaided (10_SPRINTS Sprint 3 acceptance) |
| then | **Production Tracking Lite** slice | — |

## 9. What can be visibly working at the end of the FIRST development sprint

On a **staging preview URL**, on a tablet or phone:
1. Carolina logs in with her phone and a code (synthetic or her own staging account with the `owner` role).
2. She sees **Inicio** with the two big actions and the full navigation (Producción/Pedidos/Clientes/Growth marked "Próximamente").
3. She creates a product with a photo, colors and a size run, or picks one from a small set she provides.
4. She completes **Recibir mercancía** end to end, and sees the new pairs at the chosen location immediately.
5. She opens the product and sees the **size × location matrix** and the **immutable receipt** in its history.

**Mover inventario** and the Inicio totals follow in sprint 2 if sprint 1 runs long. Everything runs on staging data until D1–D4 are decided and A1 is in production.
