# Fuxia App — Backlog

Estado actualizado al 2026-09-10. Convención:

- **P0** bloquea / **P1** alto / **P2** medio / **P3** nice to have
- **Status**: ✅ done · 🟡 in progress · ⬜ todo · 🚫 blocked

> **Regla operativa**: cada vez que se deja algo fuera de un trabajo entregado (por falta de decisión de producto, complejidad, o alcance), se anota acá en `⬜ Todo` con la prioridad, el motivo por el que quedó fuera y una estimación. No queda solo en el chat.

Los IDs numéricos son etiquetas informales para referirse a items — no se reutilizan al mover cosas entre secciones.

---

## ✅ Completado

### Infraestructura base

| ID | Título | Notas |
|---|---|---|
| #0 | Setup Supabase + DB schema | tablas + edge functions calculate-points/calculate-tier |
| #1 | Onboarding por WhatsApp OTP | flujos signup + login separados, normalizer +52→+521, template aprobado |
| #2 | Tarjeta de lealtad real | CardScreen + Profile leyendo de Supabase, sin mocks |
| #3 | Webhook WooCommerce (código) | edge function `woocommerce-webhook` con HMAC, deployed |
| #4 | Foto de perfil | bucket `avatars` con RLS + expo-image-picker + upload + UI con badge cámara |
| #5 | Historial de compras | pantalla `/purchases` agrupada por mes, expandible |
| #6 | Categorías clickeables | tiles del Home navegan a Shop con filter, chips funcionales |
| #7 | Botón "Comprar en la web" | abre WebBrowser con permalink + talla |
| #8 | Logo + splash + iconos | logo-icon.png, logo-wordmark.png, app icon 1024² |
| #9 | Welcome screen animado | logo spring + tagline + botones Crear cuenta / Iniciar sesión |
| #10 | Tab bar custom + FAB | hoja dorada como FAB central, tab bar fija al borde inferior |
| #11 | Dark mode forzado | `useColorScheme.ts` hardcoded a 'dark' |
| #12 | EAS Update setup | OTA configurado, canales preview y production |
| #13 | Mover WC creds a proxy | edge function `woocommerce-proxy` con whitelist read-only |
| #14 | Rotar WC keys | claves nuevas en Supabase, viejas revocadas |
| #16 | Push notifications backend | tabla `push_tokens` + RLS + registro desde useAuth + push al ganar puntos / subir tier |
| #22 | Webhook WooCommerce configurado en WP | Fuxia App — Order Completed + Fuxia Loyalty Sync activos |
| #24 | ITSAppUsesNonExemptEncryption | `false` en app.json infoPlist |

### iOS / App Store

| ID | Título | Notas |
|---|---|---|
| #15 | Build iOS (IPA) | testflight profile + Distribution Certificate + Provisioning Profile |
| #18 | Build iOS a TestFlight | build 1.0.0(6) en App Store Connect, grupo "Team (Expo)" |
| #19 | Twilio WhatsApp Business Sender | `+5215599628645` productivo, throughput 80 mps |
| #20 | Twilio Partner permissions sobre WABA | Twilio Inc con Control total sobre WABA `1479833616977117` |
| #21 | Meta Business Verification aprobada | Template OTP aprobado, secrets en Supabase |

### Android / Google Play

| ID | Título | Notas |
|---|---|---|
| #40 | Build AAB producción | `com.fuxiaballerinas.loyalty`, target SDK 36, firmado por EAS |
| #41 | Feature graphic 1024×500 | `store/android/feature-graphic.png` |
| #42 | Icono 512×512 | `store/android/play-icon-512.png` |
| #43 | Screenshots Android | 3 screenshots 1080×1920 (9:16) subidos a Play |
| #44 | Ficha Play Store completa | Nombre, short/full description, categoría, contacto |
| #45 | Publicación a Producción de Play | Envío #4 publicado 9/sep, 176 países habilitados |

### Sitio y páginas legales

| ID | Título | Notas |
|---|---|---|
| #46 | Página `/privacy/` en fuxiaballerinas.com | plantilla en `wordpress/page-privacy.php`, publicada |
| #47 | Página `/eliminar-cuenta/` | requerida por Play, publicada |
| #17 | Sacar proyecto de OneDrive | movido a rutas normales, evita EAS build EACCES |

### Fixes de esta sesión (sept 2026)

| ID | Título | Notas |
|---|---|---|
| #48 | Firebase / FCM V1 configurado | `google-services.json` + FCM key en EAS credentials |
| #49 | Home: nuevo mensaje de comunidad Fuxia | commit `244c181` |
| #50 | Beneficios: textos y perks por tier alineados | commit `efd8e17` |
| #51 | Referidos: código + copy alineados a 1x primera compra en tienda | commits `1d265ca`, `67fb151` |
| #52 | Admin: gestión de vendedoras + reportes + entrada "Soy vendedora" en welcome | commit `dd6e1fe` |
| #53 | Fix precios en moneda del país (Colombia dejaba de ver MXN) | commits `2a400b1`, `beb1d3e` — persiste país del onboarding + conversión app-side con SUPPORTED_COUNTRIES.mxn_rate |
| #54 | GitHub Action keepalive de Redis de Hilo | `.github/workflows/hilo-keepalive.yml` — POST cada 12h |

---

## 🟡 En progreso

*(nada agenda para trabajo activo — items todo se listan abajo)*

---

## ⬜ Todo

### #29 Verificar/configurar zona Colombia en WCPBC (WordPress) (P0)

Reporte: clientas descargando desde Colombia ven precios en MXN en lugar de COP.

En la app se corrigieron los bugs de detección de país (#53). Con el fix de conversión app-side, la app ya muestra COP correctamente **dentro de la app**. Pero cuando la clienta toca "Ver en la web" y llega a `fuxiaballerinas.com`, ahí sigue viendo MXN porque WooCommerce responde en la moneda base sin la zona configurada.

**Lo que queda por hacer en WordPress**:

- [ ] En `fuxiaballerinas.com/wp-admin` → **WooCommerce → Settings → Price Based on Country**: crear zona con **Colombia** + **COP** como moneda + tasa de cambio (~150 COP por MXN) o precios por producto.
- [ ] Crear también zona **USD** para los 9 países soportados como USD (US, CA, GT, SV, CL, AR, PA, CR, PE) — mismo enfoque.
- [ ] Test manual: `https://fuxiaballerinas.com/wp-json/wc/store/v1/products?wcpbc-manual-country=CO` → debe devolver `currency_code: "COP"`. Hoy devuelve `"MXN"`.

Sin este paso, la web y la app se ven inconsistentes (app muestra COP, web MXN).

Estimación: 15 min si el grupo ya existe, 1h para crearlo con tasas.

---

### #30 Prevenir que la Redis de Hilo se muera cada 14 días (P1)

Upstash free tier borra bases inactivas a los 14 días. Ya pasó una vez (sept 2026).

Estado actual: hay **GitHub Action** (`.github/workflows/hilo-keepalive.yml`) que hace POST al chat cada 12h para mantener actividad. Con eso debería alcanzar, pero es una mitigación, no un fix estructural.

Opciones restantes (opcionales, elegí una si querés más solidez):

- [ ] **Upgrade Upstash a Pay As You Go** (~$0.20/100K commands, ~$5-10/mes) — la más limpia, elimina la dependencia del keepalive.
- [ ] O que el backend Hilo tenga **fallback si Redis falla** (responder sin memoria de conversación en vez de crashear todo) — cambio en el código Python (~1h).

Nota operativa si se cae de nuevo: en Upstash console → base "Deleted" tiene botón **Restore** que migra los backups a una base nueva (con hostname/password nuevos). Después hay que actualizar `REDIS_URL` en Railway → Variables con la URL completa (`rediss://default:PASSWORD@nuevo-host.upstash.io:6379`).

---

### #55 Probar preview APK en Android real (P1)

La app nunca corrió en Android físico. La build de producción está en Play (Envío #4) pero no se probó en un dispositivo real antes. Riesgos: edge-to-edge, back button gestures, permisos de cámara y notificaciones runtime, animaciones moti/reanimated en gama media, deep links `fuxia://`.

Sub-tareas:

- [ ] `eas build --platform android --profile preview` → APK instalable
- [ ] Instalar en un Android de gama media (Motorola/Samsung baratos son buen test)
- [ ] Testear: login WhatsApp, ver home, entrar a beneficios, escanear QR de tienda como vendedora, ver notificación push al ganar puntos
- [ ] Documentar bugs encontrados en tickets nuevos

Estimación: 30 min de build + 30 min de test.

---

### #56 Declaraciones Policy → App content en Play (P1)

Aunque la app ya está en producción, faltan algunas declaraciones que Play puede exigir con más rigor a futuro (o al hacer una actualización mayor):

- [ ] Data safety form completo (teléfono, nombre, email, fotos, historial de compras — todos "collected + linked to user, not tracking")
- [ ] Content rating IARC (cuestionario, debería salir Everyone / 3+)
- [ ] Target audience 18+
- [ ] Ads = No
- [ ] URL de eliminación de cuenta (`fuxiaballerinas.com/eliminar-cuenta`) ya publicada, hay que declararla si no está
- [ ] Credenciales del revisor: México, teléfono `5555555555`, código `555555`

Estimación: 30 min de formularios.

---

### #57 Service account de Google Play para eas submit automático (P2)

Hoy los AABs se suben a mano en cada release. Con una service account de Google Cloud vinculada al proyecto Play, `eas submit --platform android --profile production` sube el AAB automáticamente.

Sub-tareas:
- [ ] Play Console → Setup → API access → vincular Google Cloud
- [ ] Google Cloud → IAM & Admin → Service Accounts → crear una con permiso "Release manager"
- [ ] Descargar JSON como `fuxia-native/google-play-service-account.json` (ya está en `.gitignore`)
- [ ] O mejor: `eas secret:create` para no tener el JSON en local

Estimación: 15 min.

---

### #25 Push notifications testing en device real (P1)

Los push solo funcionan en builds nativos (no Expo Go iOS). Confirmar end-to-end:

- [ ] Instalar TestFlight build en iPhone propio
- [ ] Loguear → confirmar que `push_tokens` se inserta con el `expo_push_token`
- [ ] Registrar una compra manual en WooCommerce (o correr el webhook con curl) → confirmar que llega notificación al iPhone
- [ ] Idem en Android con la build de Play

---

### #26 Notificaciones push a segmentos desde admin (P2)

Que la administradora pueda mandar push a segmentos (Bronze, Silver, Gold, o todas). Hoy solo hay push automáticas al ganar puntos / subir de tier.

Sub-tareas:
- [ ] Edge function `admin-broadcast-push` (input: tier | 'all', title, body, data)
- [ ] Query `push_tokens` filtrando por customer.tier via loyalty_cards
- [ ] Envío en batches de 100 al Expo Push API con dedupe
- [ ] Registrar el broadcast en tabla `broadcasts` (auditoría + rate limit)
- [ ] Pantalla `/admin/broadcast`: form con segmento, título, cuerpo, opcional deep link, preview y confirm
- [ ] Rate limit: máx 1 broadcast por día por segmento (evitar spam)

Estimación: ~3h.

---

### #27 Catálogo de recompensas canjeables (P2)

Hoy los perks por tier son texto en `payments/index.tsx` — no se pueden canjear desde la app. Falta un catálogo dinámico administrable con canje.

Sub-tareas:
- [ ] Schema DB: `rewards_catalog` (id, name, description, min_tier, points_cost, image_url, stock, active) y `redemptions` (id, customer_id, reward_id, status, redeemed_at, fulfilled_at, redemption_code)
- [ ] Admin CRUD `/admin/rewards` para gestionar catálogo
- [ ] Pantalla `/rewards` en cliente para ver disponibles según tier + puntos
- [ ] Flujo de canje (definir producto: ¿QR que admin escanea? ¿reservación con confirmación WhatsApp?)
- [ ] `redeem-reward` edge function con lock optimista para descontar puntos
- [ ] Notificación push cuando una recompensa se marca como fulfilled

Estimación: ~5h + reunión de producto para el flujo de canje.

---

### #28 Vendedora ve sus propios stats en /vendedora/home (P3)

Hoy `/vendedora/home` muestra "Ventas de hoy" del **canal completo** — cualquier vendedora del bazar ve el mismo número. Falta que vea las suyas específicas.

Sub-tareas:
- [ ] Segunda card con "Mis ventas de hoy" filtrando por `offline_sales.staff_id`
- [ ] Sumatoria de `total` como monto acumulado por la vendedora
- [ ] Opcional: `/vendedora/my-sales-today` con detalle por venta (fecha, monto, código)

Estimación: ~30 min.

---

### #58 useAuth como Context compartido (P2, tech-debt)

Cada pantalla con `useAuth()` hace queries propias → 3-4× duplicadas al cambiar de tab. Mover a AuthProvider Context.

- [ ] Crear `AuthProvider` que expone state + actions
- [ ] `useAuth()` pasa a ser consumer
- [ ] Envolver `<AuthProvider>` en `app/_layout.tsx`
- [ ] Exponer `refresh()` para recargar on-demand

---

### #59 Wire grid actions del Profile (P3)

Tiles "Seguimiento", "Regalar", "Pagos" están sin destino. Solo "Mis Compras" funciona. Decidir:

- Implementar (cada uno tiene su sub-spec)
- Ocultarlos hasta tener spec
- Reemplazarlos por links útiles

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
