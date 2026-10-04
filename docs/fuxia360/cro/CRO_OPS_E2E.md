# CRO-OPS · Entrega inmediata de punta a punta (preparación)

**Estado: NO listo.** No se declara listo hasta probarlo con la app de vendedoras real.

## 1. Flujo que hay que demostrar

| # | Paso | Qué existe hoy | Estado |
|---|---|---|---|
| 1 | Pedido online pagado | `f360_ingest_woo_order` (webhook Woo → `f360-woo-orders`) | ✅ Existe, con pruebas de BD |
| 2 | Asignación de fulfillment | Bodega primero; si no hay, la tienda con el par libre (`f360.store_for_online`) → `f360.online_store_shipments` | ✅ Existe, con pruebas de BD |
| 3 | Aviso a la tienda | Trigger → `f360.push_outbox` → Edge `f360-push` → Expo, a `f360.location_team(tienda)` | ⚠️ BD y función probadas. **El push real a un teléfono no se ha probado** (ver 2.3) |
| 4 | "Envíalo hoy" en la app | — | ❌ **No existe** pantalla de envíos online en la app de vendedoras |
| 5 | Acuse de la vendedora | — | ❌ No existe estado "aceptado" (solo `por_enviar` / `enviado`) ni una función que la vendedora pueda llamar con su turno |
| 6 | Enviado | `f360_online_store_shipment_sent`, **solo operator** (admin web) | ⚠️ La vendedora no puede marcarlo desde su turno |
| 7 | Estado del pedido | — | ❌ No se actualiza el pedido Woo (por ejemplo, `completed` o una nota "enviado desde Polanco"). Woo no se entera |

## 2. Qué falta exactamente en la app de vendedoras

1. **Conectar el inicio de turno a las pantallas F360.**
   - `components/SellerShiftLogin.tsx` todavía responde "la venta en esta ubicación todavía no está habilitada" para tiendas F360.
   - Debe ir a `app/vendedora/tienda.tsx`. Esa pantalla existe, sin commit todavía, junto con `apartados.tsx`, `venta.tsx` y `lib/f360Store.ts`.
2. **Pantalla "Envíos en línea"** (nueva):
   - Lista de `online_store_shipments` de la tienda del turno, con modelo, color, talla, pedido y hora.
   - Botones **"Lo tengo, lo preparo"** (acuse) y **"Ya se envió"**.
   - Alerta dentro de la app, como la de apartados.
3. **Base de datos** (migración nueva, con su rollback y pruebas):
   - Estado `aceptado` con `accepted_at` y `accepted_by`.
   - Funciones por turno `f360_shift_shipments(token)`, `f360_shift_shipment_accept(token, id)` y `f360_shift_shipment_sent(token, id)`. La tienda la determina el turno, nunca el cliente.
4. **Push real:**
   - **iOS:** necesita una build de prueba (EAS, perfil staging, bundle id aparte) y que la vendedora inicie sesión, porque así se registra su `push_token`.
   - **Android:** no hay Firebase (`google-services.json`), así que no hay push; queda la alerta dentro de la app.
5. **Estado del pedido en Woo:** al marcar "enviado", agregar una nota al pedido y, si se aprueba, cambiar el estado. Usa la Edge Function de Woo de staging. Es un cambio de negocio (cuándo se completa un pedido) que Mario debe aprobar.
6. **Build de prueba:** perfil `staging` en `eas.json` con las variables de staging y un paquete distinto (`…loyalty.staging`) para no reemplazar la app de producción. Requiere `eas build` (cuenta torosilva) y keystore nuevo.

## 3. Prueba E2E propuesta (cuando lo anterior exista)

1. Una vendedora de prueba asignada a Polanco, con PIN, inicia turno en la build de staging.
2. Desde staging4 se compra con pasarela sandbox una talla que **solo** esté en Polanco.
3. **Verificar:**
   - Shipment `por_enviar` en Polanco.
   - Push en el teléfono (iOS) o alerta dentro de la app (Android) en ≤ 1 min.
   - "Lo tengo" → `aceptado` (se mide el tiempo).
   - "Ya se envió" → `enviado`.
   - Nota en el pedido Woo.
   - Ledger: un `SALE` desde Polanco.
   - ATS de la talla baja en Woo.
4. Repetir con Bodega (sin shipment de tienda) y con un par apartado Gold (no debe tomarse).
5. Criterio de aprobación: ver `06_INVENTORY_CONVERSION.md` §2.
