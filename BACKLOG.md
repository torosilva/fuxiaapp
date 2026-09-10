# Fuxia App — Backlog

Estado actualizado al 2026-09-10. Convención:

- **P0** bloquea / **P1** alto / **P2** medio / **P3** nice to have
- **Status**: ✅ done · 🟡 in progress · ⬜ todo · 🚫 blocked

> **Regla operativa**: cada vez que se deja algo fuera de un trabajo entregado (por falta de decisión de producto, complejidad, o alcance), se anota acá en `⬜ Todo` con la prioridad, el motivo por el que quedó fuera y una estimación. No queda solo en el chat.

---

## ✅ Completado

| ID | Título | Notas |
|---|---|---|
| #0 | Setup Supabase + DB schema | tablas + edge functions calculate-points/calculate-tier |
| #1 | Onboarding por WhatsApp OTP | flujos signup + login separados, normalizer +52→+521, template aprobado |
| #2 | Tarjeta de lealtad real | CardScreen + Profile leyendo de Supabase, sin mocks |
| #3 | Webhook WooCommerce (código) | edge function `woocommerce-webhook` con HMAC, deployed (falta config en WP, ver #18) |
| #4 | Foto de perfil | bucket `avatars` con RLS + expo-image-picker + upload + UI con badge cámara |
| #5 | Historial de compras | pantalla `/purchases` agrupada por mes, expandible |
| #6 | Categorías clickeables | tiles del Home navegan a Shop con filter, chips funcionales |
| #7 | Botón "Comprar en la web" | abre WebBrowser con permalink + talla |
| #8 | Logo + splash + iconos | logo-icon.png, logo-wordmark.png, app icon 1024² |
| #9 | Welcome screen animado | logo spring + tagline + botones Crear cuenta / Iniciar sesión |
| #10 | Tab bar custom + FAB | hoja dorada como FAB central, tab bar fija al borde inferior |
| #11 | Dark mode forzado | `useColorScheme.ts` hardcoded a 'dark' |
| #12 | EAS Update setup | OTA configurado, channel `preview` |
| #13 | Mover WC creds a proxy | edge function `woocommerce-proxy` con whitelist read-only, secrets server-side |
| #14 | Rotar WC keys | nuevas claves seteadas en Supabase (revocar las viejas en WC admin) |
| #15 | Build iOS (IPA) | testflight profile + Distribution Certificate + Provisioning Profile |
| #16 | Push notifications backend | tabla `push_tokens` + RLS + registro desde useAuth + push al ganar puntos / subir tier |
| #17 | Sacar proyecto de OneDrive | movido a `C:\Users\mario\Documents\...` para evitar EAS build EACCES |
| #18 | Build iOS subido a TestFlight | build 1.0.0(6) en App Store Connect, status "Ready to Submit", grupo "Team (Expo)" creado |
| #19 | Twilio WhatsApp Business Sender comprado | número productivo `+5215599628645` registrado, status Online, throughput 80 mps |
| #20 | Twilio Partner permissions sobre WABA | Twilio Inc agregado como Socio con Control total sobre WABA `1479833616977117` |
| #21 | Meta Business Verification aprobada | Sender productivo activo, template OTP aprobado, secrets actualizados en Supabase |
| #22 | Webhook WooCommerce configurado | Dos webhooks activos en WP Admin (Fuxia App — Order Completed + Fuxia Loyalty Sync) apuntando a woocommerce-webhook |
| #23 | ITSAppUsesNonExemptEncryption | Ya seteado en `false` en app.json infoPlist |

---

## 🟡 En progreso

### Invitar más testers internos a TestFlight (P1)

Build subida a TestFlight. Grupo "Team (Expo)" creado pero solo 1 invite. Para abrir más:
1. App Store Connect → TestFlight → Internal Testing → **+** → crear grupo (ej. "Familia")
2. Add Testers por email (hasta 100, sin Apple review)
3. Llenar **Test Information** (Beta App Description ya redactado, solo pegar; agregar email de soporte y notas para reviewer)

---

## ⬜ Todo

### #18 Build Android preview (P1)

Después del fix de OneDrive read-only y commit con pre-install hook, debería andar.

```powershell
npx eas build --profile preview --platform android --non-interactive --no-wait
```

DoD: APK descargable + instalado en celu Android probando todo el flow.

---

### #19 Privacy Policy + Soporte en fuxiaballerinas.com (P0 Apple)

Apple exige ambas URLs antes de submit a producción.

**Pages a crear**:
- `https://fuxiaballerinas.com/privacy` — copy template en `APP_STORE_METADATA.md`
- `https://fuxiaballerinas.com/soporte` — email + FAQ básico
- Email `soporte@fuxiaballerinas.com`

DoD: ambas URLs accesibles públicamente, contenido al día.

---

### #20 Screenshots para App Store (P1)

Apple requiere **6.7"** (1290×2796) y **6.5"** (1242×2688) en portrait.

**Pantallas a capturar** (capturables hoy):
1. Welcome con logo animado + botones
2. Tarjeta de lealtad con QR
3. Home (hero + Novedades + Categorías)
4. Detalle de producto con preview de puntos
5. "Mis Zapatos" con compras
6. Profile con avatar + último pedido

Sugerido: usar Figma para overlay con copy promocional.

DoD: 6 screenshots por size subidos a App Store Connect.

---

### #21 Store Scanner para vendedoras (P2)

Pantalla protegida con PIN para vendedoras en tienda. Cámara escanea QR → muestra perfil + permite registrar venta channel='store'.

Detalle completo: ver `claude-prompts/fuxia-app-claude-code-prompts.md` Prompt 5.

Sub-tareas:
- [ ] Ruta `/store/scanner` fuera de tabs (acceso protegido)
- [ ] PIN screen (4 dígitos por tienda)
- [ ] expo-camera + scan formato `FX-...`
- [ ] Lookup por `qr_code` en `loyalty_cards`
- [ ] Bottom sheet con perfil + últimas 3 compras
- [ ] Registrar venta `channel='store'`
- [ ] Insertar en `qr_scans`
- [ ] Fraud detection (`utils/fraudDetection.ts`): >3 scans/10min same store, montos > $10k MXN

---

### #22 useAuth como Context compartido (P2, tech-debt)

Hoy cada pantalla con `useAuth()` hace queries propias → 3-4x duplicadas al cambiar tabs. Mover a `AuthProvider` Context.

- [ ] Crear `AuthProvider` que expone state + actions
- [ ] `useAuth()` pasa a ser consumer
- [ ] Envolver `<AuthProvider>` en `app/_layout.tsx`
- [ ] Exponer `refresh()` para recargar on-demand

---

### #23 Wire grid actions del Profile (P3)

Tiles "Seguimiento", "Regalar", "Pagos" están sin destino. Solo "Mis Compras" funciona. Decidir:
- Implementar (cada uno tiene su sub-spec)
- Ocultarlos hasta tener spec
- Reemplazarlos por links útiles

---

### #24 ITSAppUsesNonExemptEncryption (P2, Apple) ✅ ya resuelto

Warning durante build iOS. Para evitar config manual cada submit:

```json
"ios": {
  "infoPlist": {
    "ITSAppUsesNonExemptEncryption": false
  }
}
```

(Solo HTTPS estándar — no usamos cripto custom)

---

### #25 Push notifications testing en device real (P1)

Los push solo funcionan en builds nativos (no Expo Go iOS). Una vez la build esté en TestFlight:
- [ ] Instalar TestFlight build en iPhone propio
- [ ] Loguear → confirmar que `push_tokens` se inserta
- [ ] Forzar webhook → confirmar que llega notificación

---

### #26 Notificaciones push a segmentos (P2)

Que la administradora pueda mandar un mensaje push a un segmento (todas las Bronze, todas las Silver, todas las Gold, o todas). Hoy solo hay push automáticas al ganar puntos / subir de tier (`push_tokens` + hook en webhook y en `admin-points`), no hay envío manual desde admin.

Por qué se dejó fuera: necesita edge function nueva (`admin-broadcast-push`) que agrupe destinatarios por tier y llame al Expo Push API, más UX de composición (título, cuerpo, ¿imagen?, ¿deep link a un producto?).

Sub-tareas:
- [ ] Edge function `admin-broadcast-push` (input: tier | 'all', title, body, data)
- [ ] Query `push_tokens` filtrando por customer.tier via loyalty_cards
- [ ] Envío en batches de 100 al Expo Push API con dedupe
- [ ] Registrar el broadcast en tabla `broadcasts` (auditoría + rate limit)
- [ ] Pantalla `/admin/broadcast`: form con segmento, título, cuerpo, opcional deep link, preview y confirm
- [ ] Rate limit: máx 1 broadcast por día por segmento (evitar spam)

Estimación: ~3h. DoD: admin manda un push a segment 'silver' y a un teléfono con push_token registrado como Silver le llega la notificación.

---

### #27 Catálogo de recompensas canjeables (P2)

Hoy los perks por tier son texto en `payments/index.tsx` — no se pueden canjear desde la app, la clienta tiene que ir físicamente y reclamar. Falta un catálogo dinámico administrable con canje.

Por qué se dejó fuera: necesita schema nuevo y una decisión de producto grande (¿auto-canje al llegar al nivel? ¿claim manual con QR? ¿la clienta reserva y admin confirma?).

Sub-tareas:
- [ ] Schema DB: `rewards_catalog` (id, name, description, min_tier, points_cost, image_url, stock, active) y `redemptions` (id, customer_id, reward_id, status: pending/fulfilled/cancelled, redeemed_at, fulfilled_at, redemption_code)
- [ ] Admin CRUD `/admin/rewards` para gestionar catálogo
- [ ] Pantalla `/rewards` en cliente para ver disponibles según tier + puntos
- [ ] Flujo de canje (definir: ¿genera QR que admin escanea en tienda? ¿reservación con confirmación por WhatsApp?)
- [ ] Descontar puntos en `redeem-reward` edge function con lock optimista
- [ ] Notificación push cuando una recompensa se marca como fulfilled

Estimación: ~5h + reunión de producto para decidir el flujo de canje.

---

### #28 Vendedora ve sus propios stats en /vendedora/home (P3)

Hoy `/vendedora/home` muestra "Ventas de hoy" del **canal completo** — cualquier vendedora del bazar ve el mismo número. Falta un toggle o segunda card que muestre las suyas específicas (filtradas por `offline_sales.staff_id`).

Por qué se dejó fuera: alcance de la iteración de "admin panel". Es cambio muy chico pero afecta la UX del `/vendedora/home` y quería mantener el commit del admin acotado.

Sub-tareas:
- [ ] Segunda card en `/vendedora/home` con "Mis ventas de hoy" filtrando por `staff_id` (viene por URL param del PIN screen)
- [ ] Sumatoria de `total` como monto acumulado por la vendedora
- [ ] Opcional: `/vendedora/my-sales-today` con detalle por venta (fecha, monto, código)

Estimación: ~30min. DoD: en la home del vendedor se ven dos números — total del canal y las propias — sin confundirlos.

---

### #29 Verificar/configurar grupo Colombia en WCPBC (WordPress) (P0)

Reporte: clientas descargando desde Colombia ven precios en MXN en lugar de COP.

En la app se corrigieron dos bugs (commit próximo a este) que hacían que el país elegido en el onboarding se ignorara y las clientas terminaran mostrando la moneda del device (a menudo `es-MX` por default en Android). Con eso, cuando eligen "Colombia" en el country picker, la app manda `wcpbc-manual-country=CO` a la Store API de WooCommerce.

**Lo que queda por verificar del lado de WordPress**:

- [ ] En `fuxiaballerinas.com/wp-admin` → **WooCommerce → Settings → Price Based on Country**: confirmar que existe un grupo activo con **Colombia** en la lista de países y **COP** como moneda.
- [ ] Si el grupo existe: revisar que cada producto tenga precio en COP configurado (o que use el multiplicador de tasa de cambio para convertir MXN → COP automáticamente).
- [ ] Si el grupo NO existe: crearlo. Documentación WCPBC: https://wcpbc.com/documentation/
- [ ] Test manual: abrir `https://fuxiaballerinas.com/wp-json/wc/store/v1/products?wcpbc-manual-country=CO` desde el navegador y verificar que la respuesta tiene `currency_code: "COP"` — si devuelve `"MXN"`, es que el grupo no está configurado.
- [ ] Repetir el mismo test para US y otros países soportados en `SUPPORTED_COUNTRIES` (US, CA, GT, SV, CL, AR, PA, CR, PE) — hoy todos se agrupan como `mxn_rate: 17` (USD), que asume un grupo USD en WCPBC.

Sin este paso, el fix del lado app no sirve: la app pide COP correctamente pero WordPress igual devuelve MXN como fallback.

Estimación: 15 min si el grupo ya existe, 1h si hay que crear grupos + configurar precios/tasa.

---

## 🚫 Blocked / Wait

### Migrar a Supabase Auth phone-only nativo (post-MVP)

Hoy creamos un `auth.user` con email fake (`{phone}@fuxia.app`) y password derivado. Funciona pero es hacky. Cuando Supabase libere mejor soporte phone-only auth, migrar.

---

## Cómo convertir esto a GitHub Projects

1. Crear Project en https://github.com/torosilva/fuxiaapp/projects (Board template)
2. Por cada item ⬜/🟡, **New issue** con título y body de acá
3. Labels según prioridad (P0/P1/P2) y categoría (frontend/backend/devex/security/apple)
4. Movés tarjetas entre `Todo` → `In Progress` → `Done`
5. Los ✅ ya completados los podés agregar como referencia histórica en columna `Done`
