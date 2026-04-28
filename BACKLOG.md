# Fuxia App — Backlog

Issues pendientes para convertir en GitHub Issues y trackear en el Project "Fuxia App Roadmap".

Convenciones:
- **Labels** entre paréntesis
- **Priority**: P0 (bloquea) / P1 (alto) / P2 (medio) / P3 (nice to have)
- **Estado**: `Todo` por defecto; mover a `In Progress` y `Done` en el board

---

## 1. Configurar webhook WooCommerce en fuxiaballerinas.com
*(backend, setup, P0)*

La función `woocommerce-webhook` está deployada en Supabase y el secret `WC_WEBHOOK_SECRET` seteado. Falta conectarla desde WooCommerce para que las compras reales sumen puntos.

**Pasos:**
1. Entrar a `fuxiaballerinas.com/wp-admin` → WooCommerce → Ajustes → Avanzado → Webhooks → Agregar webhook
2. Completar:
   - **Nombre**: `Fuxia Loyalty Sync`
   - **Estado**: Activo
   - **Tema**: `Pedido actualizado` (procesa cuando pasa a completed)
   - **URL**: `https://tgzgiwfzddsghnxgkcqd.supabase.co/functions/v1/woocommerce-webhook`
   - **Secreto**: `0e2097b05882b5b25be59f907636972d04923f95b57ee70711332a2a1707f7db`
   - **API**: WP REST API Integration v3
3. Mandar un "Send test ping" y verificar en los logs de la edge function que llegó con 200

**DoD:** una compra real en el sitio hace subir `total_points` en `loyalty_cards` del cliente correspondiente y aparece en el tab "Mis Compras" de la app.

---

## 2. Store Scanner: pantalla de escaneo QR para vendedoras
*(feature, frontend, P1)*

Pantalla protegida con PIN de tienda donde la vendedora escanea el QR de la clienta y ve su perfil + historial + talla más frecuente. Permite registrar venta en tienda física que suma puntos con `channel='store'`.

**Sub-tareas:**
- [ ] Nueva ruta `/store/scanner` fuera del stack de tabs
- [ ] Pantalla PIN (4 dígitos) con PIN por tienda en `localStorage` o env
- [ ] Integrar `expo-camera` y escaneo de códigos (formato esperado: `FX-...`)
- [ ] Query por `qr_code` en `loyalty_cards` → resolver `customer_id`
- [ ] Bottom sheet con perfil: nombre, tier, puntos, pares, últimas 3 compras, talla más frecuente (agrupar `purchase_items.size`)
- [ ] Pantalla "Registrar venta": monto + productos buscados por nombre/SKU
- [ ] Crear `transactions` con `channel='store'`, recalcular tier, insertar reward si sube
- [ ] Insertar en `qr_scans` cada lectura (store_id, staff_id, scanned_at)
- [ ] `utils/fraudDetection.ts`: alerta si mismo QR escanea >3 veces en 10min desde misma tienda; requiere confirm si monto > 10,000 MXN

---

## 3. Push notifications
*(feature, backend, P2)*

Notificar: gana puntos / sube de nivel / falta poco para nivel / recompensa lista.

**Sub-tareas:**
- [ ] `npm install expo-notifications`
- [ ] `services/notificationService.ts`: `registerForPushNotifications()` guarda token en tabla `push_tokens`
- [ ] Migración SQL: nueva tabla `push_tokens (customer_id, expo_token, platform)`
- [ ] Edge Function `send-push-notification`: recibe customer_id + mensaje, envía por `POST https://exp.host/--/api/v2/push/send`
- [ ] Triggers (Postgres): sobre `loyalty_cards` — al aumentar points o cambiar tier, llamar a la edge function vía `pg_net`
- [ ] Mensajes con nombre: "¡Hola Ana! Ganaste 27 puntos 🎉"
- [ ] Probar en Expo Go (push requiere build real en iOS, funciona en Expo Go Android)

---

## 4. Flujo de compra en app: decisión + implementación
*(feature, decision, P1)*

Hoy no hay checkout. Decidir entre:
- **Opción A — WebView**: botón "Comprar" abre `fuxiaballerinas.com/producto/{slug}` en WebView. Rápido de implementar (1-2h), reutiliza checkout del sitio. Webhook suma puntos al completar.
- **Opción B — Nativo**: carrito + dirección + pago (Stripe/Mercado Pago SDK). 1-2 días.
- **Opción C — Deep link**: abre navegador del sistema. Cero costo de build.

**DoD (opción A)**: tap en "Añadir al carrito" desde `/product/[id]` abre WebView modal con el producto. Al completar, app vuelve y muestra confirmación.

---

## 5. Foto de perfil real (Supabase Storage)
*(feature, frontend, P3)*

Hoy el avatar muestra iniciales. Permitir subir foto.

**Sub-tareas:**
- [ ] Bucket público `avatars` en Supabase Storage con RLS (cada usuario solo lee/escribe su archivo)
- [ ] Columna `avatar_url TEXT` en `customers`
- [ ] Usar `expo-image-picker` para seleccionar foto
- [ ] Subir con `supabase.storage.from('avatars').upload(...)` → guardar URL pública
- [ ] Fallback: si `avatar_url` es null, seguir mostrando iniciales
- [ ] Botón "Cambiar foto" en tap del avatar

---

## 6. Mover WC consumer_key/secret a env vars
*(security, tech-debt, P1)*

`constants/WooCommerce.ts` tiene las credenciales de WooCommerce hardcoded en el bundle cliente. Cualquiera que descompile el APK las saca y puede crear/editar órdenes. Problema real.

**Sub-tareas:**
- [ ] Mover `WC_CONSUMER_KEY` y `WC_CONSUMER_SECRET` a env vars `EXPO_PUBLIC_*` (mitigación parcial)
- [ ] Mejor aún: mover **todas** las llamadas a WC a un Edge Function proxy en Supabase. El cliente solo llama al proxy con su JWT; el proxy guarda los secrets y hace la request a WC.
- [ ] Rotar las credenciales actuales en WooCommerce (las que están en el repo ya son públicas)

---

## 7. useAuth como Context compartido
*(tech-debt, performance, P2)*

Hoy `useAuth` se ejecuta independiente en cada pantalla que lo usa (Card, Profile, Purchases, Product Detail). Cada montaje hace sus propias queries a Supabase → 3-4x queries duplicadas al cambiar de tab.

**Sub-tareas:**
- [ ] Crear `AuthProvider` Context
- [ ] Mover la lógica de `loadSession`/`loadCustomerData` al provider
- [ ] `useAuth()` pasa a ser consumer del contexto
- [ ] Envolver `<AuthProvider>` en el root `_layout.tsx`
- [ ] Exponer `refresh()` para recargar on-demand (ej. después de crear perfil o completar compra)

---

## 8. Dev Build con EAS para testeo rápido
*(devex, P2)*

Expo Go + tunnel es lento (bundle de 20MB se baja cada arranque). Un dev build instala el bundle en el celu → reload instantáneo + permite módulos nativos que Expo Go no soporta.

**Sub-tareas:**
- [ ] `npm install -g eas-cli`
- [ ] `eas login`
- [ ] `eas build:configure`
- [ ] `eas build --profile development --platform android`
- [ ] Instalar APK en el celu
- [ ] Documentar el flujo en `README.md`

---

## 9. Grid actions del Profile: wire tiles restantes
*(feature, frontend, P3)*

Las tiles "Seguimiento", "Regalar", "Pagos" en el tab Profile están sin funcionalidad (solo "Mis Compras" navega a `/purchases`).

**Sub-tareas:**
- [ ] **Seguimiento**: pantalla con órdenes WC en estado `processing`/`shipped`. Requiere endpoint en WooCommerce.
- [ ] **Regalar**: decidir producto (¿tarjeta de regalo? ¿referir amiga?). Necesita spec.
- [ ] **Pagos**: pantalla de "métodos de pago guardados" — sólo tiene sentido si vamos por flujo de compra nativo (ver #4).

Podrían quedar ocultas hasta que tengan destino real, en vez de visibles-sin-función.

---

## Cómo convertir esto en issues de GitHub

1. Abrir el Project `Fuxia App Roadmap`
2. Por cada sección de arriba, *New issue* en la columna `Todo`
3. Copiar título + pegar el bloque de texto correspondiente como descripción
4. Agregar labels según la cabecera
5. Linkear el issue al project (el Project los auto-agarra si están en `torosilva/fuxiaapp`)

Tip: en vez de copiarlos a mano, podés instalar `gh` CLI y correr:
```bash
gh issue create --title "1. Configurar webhook WooCommerce" --body-file - < section1.md
```
