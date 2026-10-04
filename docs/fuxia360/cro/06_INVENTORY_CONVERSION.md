# CRO · Inventario y conversión (CRO-5a, D-CRO-01/02/04)

Staging. Decisiones de Mario del 2026-10-04.

## 1. CRO-5a · Guard de inventario certificado

Migración `20261007002400_f360_scarcity_guard.sql`. Rollback en `supabase/rollbacks/`. Pruebas en `supabase/staging/f360_scarcity_guard_tests.sql`: 20 checks; el suite completo pasa (687).

### 1.1 Cuándo un inventario es CERTIFICADO

Se deriva de la evidencia operativa, **no de un interruptor manual**.

Una talla (variante) está certificada en una ubicación cuando esa ubicación tiene su **único** evento `OPENING_PHYSICAL_COUNT`. Ese evento:
- está en `f360.inventory_events`;
- no se puede editar ni borrar;
- tiene un índice único por ubicación.

Y además se cumple una de estas dos condiciones:

| Origen del evento | Qué certifica |
|---|---|
| **Cutover de tienda completado** (`business_reference_type = 'location_cutover'`). La ubicación completa se contó con doble control | Todas las tallas de esa ubicación |
| **Conteo de apertura cargado** (`'opening_count'`, `opening_counts.status = 'cargado'`) | Las tallas **dentro del alcance** del conteo, más las tallas **creadas después de la carga** (su inventario nació registrado) |

Una talla que ya existía y quedó **fuera del alcance** (su homologación se reabrió durante el conteo) **no** está certificada.

Función: `f360.variant_inventory_certified(variant, location)`.

### 1.2 Cuándo el ATS online es confiable para mostrar escasez

`inventory_reliable_for_scarcity` (`f360.online_scarcity_reliable(variant, fulfillment)`) es **true solo si TODAS** las ubicaciones elegibles del ATS están certificadas para esa talla. Las ubicaciones elegibles (`f360.online_ats_locations`) son:
- la ubicación de fulfillment del target (Bodega CDMX);
- todas las tiendas online (`f360.online_store_locations()`): activas, vendibles, `store`, ledger f360, sin conteo en curso y dentro de sus fechas.

Se exige **todas las elegibles**, no solo las que tienen pares hoy. Un "0" sin certificar es tan poco confiable como un "2" sin certificar. Con una sola ubicación elegible sin certificar, el resultado es `false`. Los bazares no cuentan, porque no son elegibles.

### 1.3 Qué expone

| Función | Quién la usa | Qué devuelve |
|---|---|---|
| `public.f360_scarcity_state(woo_variation_id)` | anon / página de producto | Solo `{"reliable": true\|false}`. Variación desconocida ⇒ `false` (cerrado por defecto) |
| `public.f360_inventory_certification()` | operator+ | Por ubicación: certificada sí/no, vía (cutover / conteo de apertura) y desde cuándo |
| Edge `f360-store-reserve`, acción `scarcity` | fragmento de producto | `{reliable}`. Error ⇒ `false` |

### 1.4 Presentación (fragmento de producto)

Cambio en `tools/storefront/f360-entrega-inmediata.html`:
- Se retiró **"¡Último par!"**.
- Cualquier texto de existencia de Woo **con número o con "último par" / "quedan"** queda **oculto** mientras la respuesta no sea `{reliable:true}`. Es cerrado por defecto: sin respuesta, sigue oculto.
- Los textos sin cantidad ("Agotado") no cambian.
- Se sigue quitando "(puede reservarse)".

### 1.5 Pruebas de base de datos

| Caso | Resultado |
|---|---|
| Ninguna ubicación certificada | `false`; anon recibe `{"reliable": false}` |
| Bodega certificada por conteo y tienda A por cutover; tienda B no | `false` |
| Todas certificadas, ATS = 2 | `true`; anon recibe `{"reliable": true}` |
| ATS = 1, todas certificadas | `true` (la confiabilidad depende de la evidencia, no de la cantidad) |
| MTO apagado / prendido | Misma confiabilidad; MTO sin cambio |
| Talla existente fuera del alcance del conteo | `false` |
| Talla creada después de cargar el conteo | Certificada |
| Bazar sin certificar | No afecta |
| ATS / pedidos Woo / apartados Gold / payload del push a Woo | Sin cambio (el payload no tiene campos nuevos) |
| Permisos | anon no ve el reporte; operator sí |

### 1.6 Prueba en la página (staging4, iPhone 13, Botas Largas)

| Talla | Antes (fragmento instalado) | Después (fragmento nuevo) | Certificado (simulado) |
|---|---|---|---|
| Negro 27 (ATS 1) | "¡Último par!" visible | **Oculto** | "1 disponibles" |
| Café 23 (ATS 3) | "3 disponibles" visible | **Oculto** | "3 disponibles" |
| Café 26 (5–7 días) | — | — | — |

Capturas: `screens/pdp-antes-negro27.png`, `screens/pdp-despues-negro27.png`.

**Pendiente:** Mario pega el fragmento nuevo en Bricks. Hasta entonces, staging4 sigue mostrando "¡Último par!".

**Confirmaciones:**
- Sin cambios en `f360.online_ats` ni en `f360-woo-sync` / `sync.ts`.
- Sin cambios en la ingesta de pedidos, en `make_to_order` ni en `f360.reservations` / Gold.
- Nada en producción.

## 2. D-CRO-02 · Copy de entrega inmediata (propuesta, SIN aplicar)

| Dónde aparece | Copy actual | Propuesta |
|---|---|---|
| Página de producto (`.f360-inm-envio-t`), México, con par en Bodega o tienda, de 8 a 19 h | "🛵 Entrega inmediata en Zona Metropolitana" | "🛵 **Disponible para envío hoy** en Zona Metropolitana" + nota: "Te confirmamos la hora de entrega por WhatsApp." |
| Página de producto, fuera de horario | "🛵 Entrega mañana a partir de las 8 a. m. en Zona Metropolitana" | "🛵 Disponible para envío mañana en Zona Metropolitana" |
| Tienda, filtro (`f360-tienda.html`) | "Entrega inmediata en Zona Metropolitana" | "**Disponible hoy** (Zona Metropolitana)" |
| Barra superior del sitio (Adrián, también en producción) | "ENTREGA INMEDIATA EN LA MAYORÍA DE NUESTROS MODELOS" | "ENVÍO EL MISMO DÍA EN ZONA METROPOLITANA EN MODELOS DISPONIBLES" (fuera de Fuxia 360: lo decide Mario y lo cambia Adrián) |
| Admin (interno) | "Entrega inmediata" | Sin cambio |

La propuesta evita un SLA en horas mientras la operación no esté demostrada. Sigue diciendo que el par existe y sale hoy.

**Condición para volver a la promesa fuerte** ("Entrega inmediata" con SLA):
1. CRO-OPS aprobado de punta a punta con la app real: pedido online → fulfillment asignado → push a la tienda → "envíalo hoy" → acuse de la vendedora → estado del pedido actualizado.
2. Al menos 10 pedidos de prueba seguidos, de Bodega y de tienda, con acuse en ≤ 30 min y salida el mismo día.
3. Inventario certificado en las ubicaciones que surten (sección 1).
4. Medición del SLA visible en el admin (tiempo pedido → acuse → envío).

## 3. D-CRO-04 · Más vendidas: regla de transición

- **Regla vigente**, desde el 2026-10-03 (migración `20261007002200`): unidades de F360 de los últimos 60 días (pedidos online `sold`/`sobre_pedido` + ventas de tienda F360) **más** `legacy_woo_map.sold_90d` (histórico Woo de 90 días, leído en la homologación). Es un **bootstrap** temporal.
- **Condición de salida (automática, no implementada todavía):**
  - `D_online` = fecha del primer pedido online ingerido por `f360-woo-orders` en el target de **producción**, sin huecos. Huecos: `woo_webhook_deliveries` en error sin resolver o reconciliación con diferencias abiertas.
  - `D_tiendas` = fecha desde la cual **todas** las tiendas físicas activas venden con ledger F360 (cutover completado).
  - Se retira el histórico cuando `hoy ≥ max(D_online, D_tiendas) + 60 días`.
- **Cómo se verifica:** una función `f360.bestseller_history_ready()` (por crear) calcula las dos fechas y la ausencia de huecos. El catálogo deja de sumar `sold_90d` cuando devuelve `true`. Hasta entonces, la respuesta del catálogo debería indicar `bootstrap: true` para que quede visible.
- **Riesgo:** en staging nunca se cumplirá (no hay ventas reales), así que es inofensivo. En producción hay que implementar el retiro **antes** del go-live para que no se quede permanente.

## 4. D-CRO-08 · Deuda: redirecciones de productos unidos

Los productos por color quedaron **privados** (no borrados). Pueden tener URLs indexadas, backlinks, campañas, reseñas e historial.

**Antes de producción:**
- Importar el CSV de redirecciones (admin → Productos → "Ver redirecciones" → "Descargar CSV") en el plugin Redirection.
- Migrar o enlazar las reseñas de los productos legacy al producto unido (ver `03_REVIEWS.md`).

No se resolvió dentro de CRO-5a.
