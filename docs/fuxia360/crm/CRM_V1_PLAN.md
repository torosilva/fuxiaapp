# CRM V1 · Ficha de clienta, alta en tienda y venta desde la ficha

Estado: **PROPUESTA (2026-10-05)**, pendiente de aprobación de Mario. Todo se hace en STAGING. Producción va aparte, con el runbook.
Decisiones: `growth/CUSTOMER_360_MODEL.md` §3.1. Growth/GA4/CRO están congelados y no forman parte de esto.

## 0. Proceso (lo que vive Carolina / la vendedora)

```
Clienta llega → vendedora: [WhatsApp]  o  [escanear su tarjeta Gold]
   ├─ existe  → FICHA: "Ana · •••• 4521 · Talla 24 · 1,200 pts · Gold"
   └─ nueva   → nombre + correo (+ CP, cumpleaños día/mes: opcionales) → FICHA
FICHA → [Nueva compra] → modelo/color/talla/pago → venta registrada en la ficha (+ puntos)
Alta → WhatsApp a la clienta: "Confirma tu registro en Fuxia → Acepto" → consentimiento + puntos liberados
```

## 1. Lo que ya existe (auditado)

| Pieza | Dónde | Nota |
|---|---|---|
| Tabla de clientas | `public.customers` (baseline `20260924000000:455`) | `phone` NOT NULL **sin índice único**; ya tiene `birthday date` y `shoe_size text` (la app los pide en `onboarding/complete-profile.tsx`) |
| Tarjeta Gold | `public.loyalty_cards` (baseline :513) | El QR lo genera el teléfono (`useAuth.ts:291`). La regla "cards self insert" permite que el teléfono cree la tarjeta con cualquier cantidad de puntos (deuda de seguridad) |
| Login de la app | `whatsapp-otp/index.ts:260-272` | **Ya liga** una clienta existente con el mismo número E.164 a su cuenta. Una clienta dada de alta en tienda entra directo a su cuenta al bajar la app |
| Venta segura en servidor | `f360_record_store_sale` (`20261007001100:178`) | Precio, stock, idempotencia y puntos (`loyalty_apply`) en servidor; recibe `p_customer_qr` |
| Pantallas de vendedora (borrador) | `app/vendedora/{tienda,venta,apartados}.tsx`, `lib/f360Store.ts` | No están conectadas al login de turno. La otra sesión las cedió |
| Roles admin | `f360.user_roles`: owner = Carolina, Mario, **Adrián** | No existe un permiso de "datos personales" |
| Datos staging | 6 clientas, 0 duplicados, 100 % `+52…` | **Producción no se ha revisado** (duplicados/formatos) |

## 2. Unidades

### C1 · Ficha única + privacidad (base de datos y servidor) ← primera

**Base de datos (migración `20261010000100_f360_crm_c1_customer_profile.sql`, aditiva):**

- `public.customers` + columnas nuevas (nada se borra; la app de producción sigue igual):
  - `birthday_day smallint`, `birthday_month smallint` (sin año). Un trigger los llena desde `birthday` cuando la app pone la fecha completa;
  - `postal_code text`;
  - `source text` (`app` | `store` | `import` | `woo`);
  - `registered_by_seller uuid`, `registered_at_location uuid`.
- **Índice único en `phone`**. En staging hay 0 duplicados. En producción se revisa antes de aplicar; si hay duplicados, se listan (D-C4) y no se aplica hasta resolverlos.
- `f360.customer_pii_viewers(auth_user_id)`: **quién ve datos completos**. Arranca con Carolina (y Mario, si lo confirma). Es independiente del rol `owner`.
- `f360.customer_consents`:
  - campos: clienta, propósito (`datos` / `novedades`), estado (`pendiente` / `aceptado` / `rechazado`), canal (`whatsapp_link` / `app` / `import`), versión del aviso, fechas, hash del token;
  - append-only, auditado.
- `f360.customer_access_log`: cada búsqueda o vista de ficha hecha por una vendedora (quién, cuándo, qué clienta). Sirve contra la enumeración de números.

**Funciones de servidor** (token de turno de vendedora; **todo lo que regresan va enmascarado**):

| Función | Regresa a la vendedora |
|---|---|
| `f360_shift_customer_find(token, phone)` | Ficha enmascarada o "no existe". Solo número completo (no búsqueda por 4 dígitos ni por nombre). Límite de búsquedas por turno |
| `f360_shift_customer_by_qr(token, qr)` | Ficha enmascarada (para cuando la clienta no quiere dar su número) |
| `f360_shift_customer_register(token, phone, name, email, cp?, día?, mes?, talla?)` | Crea la clienta + la tarjeta Gold con QR del **servidor**. Si el número ya existe, **no sobrescribe** nada y regresa su ficha. Crea el consentimiento `pendiente` |
| `f360_shift_customer_card(token, customer)` | Ficha: primer nombre, `•••• 4521`, **talla** (la de su perfil + las que ha comprado), puntos/nivel, últimas compras (modelo/color/talla/fecha), estado de consentimiento |

**Ficha enmascarada** = primer nombre + últimos 4 dígitos + talla + puntos + compras. **Nunca** incluye correo, teléfono completo, CP, cumpleaños ni apellido.
**Admin (solo `customer_pii_viewers`)**: `f360_admin_customer_list` / `_get` con los datos completos. No hay función de exportación para vendedoras.

**Seguridad**
- Las vendedoras no leen tablas directamente: solo pasan por las funciones con token de turno (patrón S0.2).
- La máscara se aplica en el servidor.
- `customers` no gana reglas de lectura nuevas.
- El QR de la tarjeta lo genera el servidor.
- Las búsquedas tienen límite y quedan registradas.

**Rollback:** `supabase/rollbacks/20261010000100…down.sql`, que quita las columnas nuevas, las tablas, las funciones y el índice.
**Pruebas:** `supabase/staging/f360_crm_c1_tests.sql`. Cubre:
- la vendedora no ve PII;
- un no-viewer no ve PII;
- Carolina sí ve PII;
- no hay duplicados por número;
- registrar un número existente no sobrescribe;
- el trigger de cumpleaños funciona;
- el límite de búsquedas funciona;
- el QR lo genera el servidor;
- la clienta creada en tienda queda ligada al hacer login (simulación `whatsapp-otp`).

**Criterio de aceptación:** existen la ficha enmascarada y el alta en tienda, el número no se duplica y solo los viewers ven los datos completos. Todo verificado con pruebas en staging.

### C2 · Pantallas de vendedora: ficha → nueva compra
- Login de turno → **Clientas** (WhatsApp o escanear QR) → **Ficha** (talla grande y visible) → **Nueva compra** (`f360_record_store_sale` con la clienta ya ligada) → regresa a la ficha con la compra agregada.
- "Venta sin clienta" = venta anónima (D-C5).
- Se construye sobre `venta.tsx` / `f360Store.ts`. También se arregla el tope de piezas (disponible − apartado) y "ventas de hoy" para ventas F360.
- **Meta de UX:** alta de clienta nueva en ≤ 20 s; clienta existente en ≤ 5 s.

### C3 · Consentimiento por WhatsApp
- Al dar de alta se envía un WhatsApp con la liga "Acepto" y el aviso de privacidad. Al aceptar: consentimiento `aceptado` + los puntos guardados se liberan.
- Requiere una plantilla de WhatsApp aprobada y el **texto del aviso revisado por un abogado** (LEGAL_REVIEW_REQUIRED). La liga es de un solo uso y expira.

### C4 · Admin: Clientas
- Lista, búsqueda, ficha completa (solo viewers), "Cumpleaños de este mes" y filtros básicos.
- Las vendedoras y los no-viewers ven la versión enmascarada o nada.

### C5 · Carga de clientas de Carolina
- Carolina pega o sube su lista (CSV o vCard exportado del teléfono) → vista previa: nuevas / ya existen / con errores → confirma.
- `source = import`, consentimiento `pendiente` (sin marketing hasta que acepten).

### C6 · Historial en línea (Woo producción, solo lectura)
- Pedidos de Woo → ficha, por número/correo: **sugerir, nunca unir solo** (D-C3).
- **Lectura de producción: aprobación aparte.**

## 3. Preguntas abiertas para Mario
1. ¿Mario también ve datos completos? ¿Adrián (owner técnico) **no**?
2. Límite de búsquedas por vendedora: ¿60 por turno está bien?
3. Venta desde la ficha cuando la clienta aún no confirma por WhatsApp: los puntos quedan guardados hasta que confirme (recomendado).
