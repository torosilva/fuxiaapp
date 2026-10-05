# Customer 360 — proposed model (B1) and the identity decisions it needs

Status: **PROPOSAL.** The additive, identity-independent parts are built (see §5). The customer tables and any linking of customers are **not** built. They wait for Mario's decisions D-C1…D-C5.

## 1. Principles (from G5 / B9, already approved)

- Authorization comes only from **verified, server-controlled identity** (`auth.users` id). An editable phone, email or `user_metadata` is never an authority.
- **No automatic merge of ambiguous identities.** A merge is an explicit, audited, reversible act by a person.
- **One identity source of truth.** Customer 360 does **not** create a second "customer" that competes with `public.customers` / `auth.users`. It is a *profile* that **links** existing records.

## 2. Proposed shape

```
f360.customer_profiles          one row per real person as Fuxia knows them (UUID; no PII copy of its own)
  └─ f360.customer_identifiers  what points to that person, each with its source and confidence:
       kind: auth_user | loyalty_customer | woo_customer_id | email_hash | phone_hash | offline_code
       source: auth | loyalty | woo | offline | manual
       confidence: verified | strong | weak
       UNIQUE (kind, value) → an identifier can belong to ONE profile only
  └─ f360.customer_link_decisions  append-only: who linked/unlinked what, why, when (merges are reversible)
f360.commerce_orders (fact)     one row per order from ANY source, NOT mixed: source = woo | loyalty_tx | offline | f360
  └─ f360.commerce_order_lines  SKU → F360 variant when known; legacy SKU kept as text
metrics (views)                 computed per profile ONLY from orders linked to it with verified/strong identifiers
```

- **Resolution rules (proposal):**
  - `verified`: a Supabase auth user, and a loyalty customer with `auth_user_id`.
  - `strong`: a Woo customer id, and a **verified** phone/email that belongs to exactly one profile.
  - `weak`: a guest-checkout email or phone typed at checkout.
  - Weak matches are **suggestions** in a review queue; they are never auto-linked.
- **Duplicates:** two profiles sharing a weak identifier appear as "posibles duplicados" for a person to decide. Merging keeps both identifier sets, records the decision, and can be undone.
- **Multiple channels:** each order keeps its `source`. Metrics show the channel split, and never add sources whose overlap hasn't been proven. For example, a loyalty transaction and the same Woo order are one order: deduplicated by `wc_order_id`.

## 3. Decisions that can cause loss, duplication or wrong mixing — STOP HERE

| # | Decision needed from Mario | Why it matters |
|---|---|---|
| **D-C1** | **Source of truth for the ecommerce history:** may Fuxia 360 read the full Woo order history (production) for Customer 360? Read-only; where is it computed (production DB after P2.4, or staging with anonymized data)? | Without it, every historical metric stays "no disponible". Q6 forbids copying production customer data to staging |
| **D-C2** | **PII storage:** may Fuxia 360 store customer name/email/phone/city/state from Woo orders (today P2.3A drops them), or only hashed email/phone plus city/state? Retention? | Determines whether segments by city/state and a customer card are possible, and the privacy obligations |
| **D-C3** | **Matching rule for guest orders:** is an identical email (or phone) on a guest order the same person as a member? Auto-link, suggest, or never? | Auto-linking by editable email/phone can merge two different people (the G5 risk). Recommended: suggest only |
| **D-C4** | **Existing duplicates:** the same person may have several `customers` rows (different phone formats, old accounts). Review manually, or leave as-is? | Merging wrongly is hard to undo in loyalty (points/tier). Recommended: detect and list, never merge automatically |
| **D-C5** | **Physical sales without a claimed QR/phone:** count them as anonymous revenue only (no customer)? | Otherwise physical revenue is either lost or attached to the wrong person |

### 3.1 Decisiones de Mario (2026-10-05)

- **D-C1 · SÍ.**
  - Fuxia 360 lee el historial completo de pedidos de WooCommerce **de producción**, solo lectura (es el mismo Woo).
  - Esa lectura de producción se ejecuta con aprobación aparte, según el runbook.
- **D-C2 · SÍ.**
  - Se guardan nombre, correo, WhatsApp y ciudad/estado.
  - Además, **código postal** (ideal, no obligatorio) y **cumpleaños, solo día y mes** (sin año).
  - La dirección completa no es obligatoria.
- **D-C3 · Pendiente de aclarar.** Mario entendió la pregunta como "datos de tienda", no como "pedidos invitados en línea". Mientras se aclara, se aplica la recomendación: **sugerir, nunca unir solo**.
- **D-C4 · SÍ.** Detectar y listar duplicados, sin unir automáticamente (hoy casi no hay datos).
- **D-C5 · SÍ**, aunque no le encanta.
  - Una venta física sin clienta cuenta como venta anónima.
  - El objetivo es que la clienta **deje su teléfono** a cambio de puntos en la App y acceso anticipado a colecciones nuevas.
- **Nuevo · Alta en tienda.**
  - Obligatorios: nombre, correo y WhatsApp.
  - Opcionales: CP y cumpleaños (día/mes).
  - **Debe tomar segundos** ("la gente es muy desesperada").
- **Nuevo · Carga de clientas de Carolina.** Importar los contactos de clientas que Carolina tiene en su teléfono, con revisión y sin duplicados.
- **Nuevo · Cumpleaños.** Usar el día y mes de cumpleaños para enviar una nota y, a veces, un detalle de Fuxia.
- **Nuevo · Privacidad (obligatorio).**
  - **Solo Carolina** ve los datos personales completos de las clientas.
  - **Cualquier vendedora ve solo el primer nombre y los últimos 4 dígitos del teléfono**, y **no puede descargar ni exportar nada**.
  - Se aplica en el servidor (RLS / funciones con máscara), no solo en pantalla.
- **Nuevo · Consentimiento.** La clienta debe confirmar el uso de su información.
  - Mario propuso una tablet de firma en tienda.
  - Propuesta técnica: confirmación por WhatsApp en su propio teléfono (ver §3.2).
  - Decisión final pendiente.

## 4. Growth-specific decisions (not identity, but needed for correct metrics)

| # | Decision |
|---|---|
| D-G1 | Which period counts as "history" (Woo go-live? 2025-01-01?) and whether legacy SKUs are mapped to models (129 legacy products, free-form SKUs) |
| D-G2 | **Definition of "accesorios"** (no accessories category exists in the live catalog). Until defined, the shoes-vs-accessories segments show "no disponible" |
| D-G3 | **Attribution rule** for "revenue from CRM / repurchase" (e.g. any order by a returning customer, or only orders after a CRM contact, within X days) |
| D-G4 | How Mario's 2025/2026 figures should be recorded: total of which channels, gross or net of refunds/VAT |

## 5. Built now (additive, reversible, identity-independent)

- **B4 — Plan / Revenue model (`/growth`, "Plan 2027"):**
  - North Star (default $15,000,000 MXN, editable, labeled "objetivo, no pronóstico");
  - three scenarios with **editable assumptions only** (empty until someone enters them);
  - derived targets: monthly, customers, orders, required AOV and frequency, gap, and mix breakdowns;
  - "Actual" shows **"Sin datos confiables todavía"**.
- **Reported figures:** a record with source, period, scope and status (`reportada_no_verificada` → `verificada`), for Mario's numbers when he confirms them. Nothing is preloaded.
- **Clientes (`/clientes`) and Growth history:** honest "todavía no hay datos suficientes" states per metric, with the source classification from `DATA_AUDIT.md`, and the segment catalog (definitions only).
- **Navigation:** Inicio | Productos | Inventario | Pedidos | Clientes | Growth (Avisos stays reachable).
