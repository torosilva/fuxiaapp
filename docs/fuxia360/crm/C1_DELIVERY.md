# CRM V1 · C1 — Entrega (STAGING, 2026-10-05)

**Estado:** aplicado en staging. Pruebas C1 **66/66**; suite completa **851/851**. Rollback ensayado (deja `customers` con sus 14 columnas originales).
**Producción:** no se tocó. **Pantallas:** ninguna (son C2).

**Archivos:**
- `supabase/migrations/20261010000100_f360_crm_c1_customer_profile.sql`
- `supabase/rollbacks/20261010000100_f360_crm_c1_customer_profile.down.sql`
- `supabase/staging/f360_crm_c1_tests.sql` (registrado en `scripts/f360/db_tests.mjs`)

## 1. Tres capas separadas

| Capa | Dónde | Estado inicial de una clienta dada de alta en tienda |
|---|---|---|
| **Identidad** | `public.customers` (una fila por teléfono normalizado) + `f360.customer_verifications` | Existe, **no verificada** (su teléfono no está probado) |
| **Privacidad / uso de datos** | `f360.customer_consent_events` con propósito `privacy_notice` | `requested` |
| **Marketing** | Mismos eventos, propósitos `marketing_whatsapp` y `marketing_email` | `none` (nunca se activa solo) |

- Confirmar la cuenta **no** implica aceptar promociones. Cada propósito tiene su propio historial.
- Un consentimiento `granted`, `denied` o `withdrawn` **exige** la versión exacta del aviso (`consent_notice_versions`) y que esa versión sea del mismo propósito.
- Cada evento guarda propósito, estado, versión, origen (`store_signup` / `whatsapp_link` / `app` / `web` / `import` / `admin`), quién y dónde (`actor`), evidencia y fecha.
- Los eventos son append-only. El estado actual está en `f360.customer_consent_state` (el último evento de cada propósito).
- **El texto legal y las versiones `active` llegan en C3.** Hoy no existe ninguna versión activa, a propósito.
- **Verificación:** hoy, el primer login en la app con el código de WhatsApp (`whatsapp-otp` liga `auth_user_id`) registra `app_whatsapp_otp`.
  - Las cuentas de app existentes quedaron como `existing_app_account`, porque ya probaron su teléfono con el código.
  - El método `whatsapp_link` está listo para C3.

## 2. Esquema (aditivo)

**`public.customers`**, columnas nuevas:
- `birthday_day` y `birthday_month` (sin año). Cuando la app manda la fecha completa, un trigger los llena.
- `postal_code`.
- `source` (`app` | `store` | `import` | `woo` | `admin`).
- `registered_by` y `registered_location`.

**Tablas nuevas en `f360`:**

| Tabla | Para qué |
|---|---|
| `customer_pii_viewers` | Quién ve datos completos |
| `customer_verifications` | Teléfono probado |
| `consent_purposes`, `consent_notice_versions`, `customer_consent_events` | Consentimientos |
| `loyalty_holds` | Puntos retenidos |
| `card_token_events` | Revocaciones de QR |
| `customer_access_log` | Auditoría |

**Vistas nuevas:** `customer_consent_state` y `cards_with_legacy_token`.

## 3. Teléfono: normalización y duplicados

`f360.normalize_phone(texto, país = 'MX')` convierte a E.164:

| Lo que se teclea | Resultado |
|---|---|
| `55 1234 5678`, `(55) 1234-5678`, `5512345678` | `+525512345678` |
| `+52 55…`, `+52 1 55…` (prefijo viejo), `521…`, `045 55…`, `0052…` | `+525512345678` |
| `+57 300 123 4567`, o `3001234567` con país CO | `+573001234567` |
| `12345`, vacío, `+52 55 12` | `NULL` (se rechaza, no se adivina) |

- Diez dígitos sin prefijo **se asumen México**. Una clienta colombiana debe darse de alta con `+57`.
- Para un número mexicano válido el resultado es **idéntico** al que arma la app (`+52` + 10 dígitos, `onboarding/login.tsx:23`). Por eso una clienta dada de alta en tienda entra directo a su cuenta cuando baja la app.
- **Duplicados:**
  - Ya existía `customers_phone_key` (texto exacto).
  - C1 agrega `customers_phone_normalized_key`, un índice único sobre el teléfono normalizado. **La base rechaza a la misma persona escrita en otro formato, venga de donde venga** (app, tienda, importación).
  - En el alta en tienda, si el número ya existe se regresa su ficha y **no se sobrescribe nada**.
  - Si dos vendedoras dan de alta el mismo número al mismo tiempo, la que llega segunda recibe la ficha existente.

## 4. Funciones (RPCs)

**Vendedora:** requieren el token de turno (`require_seller_session`), tienen límite de búsquedas y quedan registradas.

| RPC | Hace |
|---|---|
| `f360_shift_customer_find(token, teléfono, país)` | Busca por **número completo** (cualquier formato). No permite buscar por nombre ni por 4 dígitos |
| `f360_shift_customer_by_card(token, qr)` | Escanear la tarjeta Gold |
| `f360_shift_customer_register(token, teléfono, nombre, correo, cp?, día?, mes?, talla?, país)` | Alta. Obligatorios: WhatsApp, nombre y correo. Crea la tarjeta (token del servidor) y el consentimiento de privacidad `requested` |
| `f360_shift_customer_card(token, customer_ref)` | Reabrir una ficha ya encontrada (para "Nueva compra") |

**Ficha enmascarada.** Es lo **único** que recibe una vendedora:
- `customer_ref`, `first_name`, `phone_last4`;
- `shoe_size` (talla de perfil) y `sizes_bought` (tallas que ha comprado);
- `points`, `tier`, `points_pending`, `has_card`;
- `identity_verified`, `privacy_consent`;
- `recent_purchases`: las últimas 10, con fecha, canal, modelo, color, talla y cantidad.

**Nunca** incluye apellido, teléfono completo, correo, CP, cumpleaños ni el token del QR. Hay una prueba que verifica la lista exacta de campos.

**Admin.** Solo `customer_pii_viewers`, todo queda registrado:
- `f360_admin_customers(búsqueda, límite ≤ 200, offset)`: busca por nombre, correo, número completo o últimos 4 dígitos.
- `f360_admin_customer(id)`: ficha completa, compras e historial de consentimientos.
- `f360_admin_rotate_card_token(id, motivo)`: revoca el QR.

**Internas** (no las puede llamar la app):
- `f360.loyalty_credit_or_hold`;
- `f360.release_loyalty_holds`;
- `f360.record_consent`;
- `f360.rotate_card_token`.

## 5. Permisos y RLS

| Quién | Qué puede |
|---|---|
| **Carolina, Mario** (`customer_pii_viewers`) | Datos completos vía las funciones admin |
| **Adrián** (owner técnico) | **No** ve datos de clientas (decisión de Mario) |
| **Vendedora** | Solo la ficha enmascarada con su turno. No tiene lista ni descarga |
| **App de la clienta** | Igual que antes: lee y edita solo su propia fila (RLS `customers self *`) |
| **anon** | Nada (sin EXECUTE en ninguna función) |

- `customer_pii_viewers` solo cambia por migración o service role. No hay función para auto-otorgarse el permiso.
- Las tablas CRM de `f360` no son accesibles a clientes: el esquema `f360` no tiene USAGE para `authenticated`/`anon`, y además tienen RLS sin políticas.
- `public.customers` **no** tiene reglas de lectura nuevas. Probado: una vendedora que lee la tabla directo solo ve su propia fila de usuaria.

## 6. Auditoría y límite de búsquedas

- `f360.customer_access_log` es append-only. Guarda quién, turno, ubicación, acción, clienta (id) y resultado (`found`, `not_found`, `created`, `existing`, `invalid`, `rate_limited`, `ok`).
- **No guarda teléfono, nombre ni correo** (hay una prueba sobre la lista de columnas).
- También quedan registrados los accesos admin de Carolina y Mario.
- **Límite:** 60 búsquedas por turno, contando búsquedas por teléfono, por QR y altas (`f360.crm_params()`).
  - La búsqueda 61 se rechaza con un mensaje para la vendedora, y el rechazo queda registrado.
  - Reabrir una ficha ya encontrada no cuenta, para que la venta en curso pueda terminarse.

## 7. Tarjeta Gold / QR

- Formato nuevo: `FX1-` + 24 caracteres hexadecimales aleatorios (96 bits). **No contiene teléfono, id ni datos personales.**
- **Lo pone el servidor:** un trigger reemplaza el QR (y fuerza 0 puntos, `bronze`) en todo insert que venga de la app.
  - Cierra la deuda "cards self insert", que permitía elegir puntos o nivel al crear la tarjeta.
  - La app no necesita cambios: lee el QR de la base al cargar.
- **Revocable:** `f360_admin_rotate_card_token` genera un token nuevo y el anterior deja de funcionar al instante. Se audita solo el hash del token anterior.
- **Tarjetas con formato viejo** (`FX-<últimos 8 dígitos>-…`): `f360.cards_with_legacy_token`. En staging son 5 de prueba (`STG-…`).
  - **No se rotaron**, porque las pruebas existentes dependen de ellas.
  - En producción, rotarlas cambia el QR que ve cada clienta en su app (se actualiza al abrirla). Es una decisión para el pase a producción.

## 8. Estados de puntos

```
venta con clienta ── identidad verificada ──→ loyalty_apply (como hoy)          state = credited
                  └─ no verificada ─────────→ f360.loyalty_holds 'held'         state = held (points_pending)
login en la app (OTP) / confirmación WhatsApp (C3) ──→ release: loyalty_apply con la MISMA llave → 'released'
```

- **Las reglas de puntos no cambian:** 100 por par, niveles 300/900, sin puntos por venta a sí misma. La liberación pasa por `loyalty_apply`.
- Hay idempotencia en dos lugares: la retención (la misma venta reintentada se retiene una vez) y la liberación (la llave de la venta nunca acredita dos veces).
- Estado `cancelled` reservado para devoluciones (futuro).
- **C2 debe conectar esto a la venta:** `f360_record_store_sale` hoy llama a `loyalty_apply` directo con el QR, y en C2 pasará a `loyalty_credit_or_hold` con `customer_ref`.

## 9. Riesgos y pendientes

1. **Producción:** antes de aplicar, revisar (solo lectura) que no haya clientas duplicadas por formato. Si las hay, el índice único falla y la migración no entra; se listan para decidir (D-C4).
2. `pending_credits` (puntos del popup por teléfono) sigue acreditando sin verificar. Es el comportamiento actual; no se tocó.
3. La política existente "customers self update" permite que la clienta edite su propia fila, incluidas las columnas nuevas `source` y `registered_*`. El impacto es bajo, solo en sus propios metadatos; se puede cerrar con privilegios por columna en una unidad aparte.
4. La sesión `fuxiaapp-67` es dueña de `f360_ingest_woo_order`, `pay_links` y `test_targets`. C1 no toca nada de eso.
