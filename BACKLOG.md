# Fuxia App — Backlog

Estado actualizado al 2026-04-28. Convención:

- **P0** bloquea / **P1** alto / **P2** medio / **P3** nice to have
- **Status**: ✅ done · 🟡 in progress · ⬜ todo · 🚫 blocked

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

---

## 🟡 En progreso

### Submit IPA a TestFlight (P0)

Build OK. Falta `eas submit` con creación del entry en App Store Connect.

**Próximo paso** (terminal interactiva):
```powershell
cd C:\Users\mario\Documents\Emprendimientos\fuxia\fuxiaapp\fuxia-native
npx eas submit -p ios --id d13bfc89-4ec2-49b2-b8d3-338a707c4ea5
```
EAS pregunta si crear app en ASC → Y → llenar (Fuxia Ballerinas, SKU `fuxia-ballerinas-001`, lang es-MX). Tarda ~5min upload.

DoD: la build aparece en App Store Connect → TestFlight → Internal Testing, lista para invitar testers.

---

## ⬜ Todo

### #18 Configurar webhook en WooCommerce admin (P0)

La edge function está deployada y probada (test directo desde curl funciona). Falta crear el webhook en WordPress.

**Pasos** (15 min):
1. fuxiaballerinas.com/wp-admin → WooCommerce → Avanzado → Webhooks → Agregar
2. Nombre: `Fuxia Loyalty Sync`, Activo, Tema: `Pedido actualizado`
3. URL: `https://tgzgiwfzddsghnxgkcqd.supabase.co/functions/v1/woocommerce-webhook`
4. Secreto: `0e2097b05882b5b25be59f907636972d04923f95b57ee70711332a2a1707f7db`
5. API: WP REST API Integration v3
6. Probar editando un pedido completed

DoD: hacer una compra real con número `+525543412939` → ver puntos sumar en la app sin intervención manual.

---

### #19 Build Android preview (P1)

Después del fix de OneDrive read-only y commit con pre-install hook, debería andar.

```powershell
npx eas build --profile preview --platform android --non-interactive --no-wait
```

DoD: APK descargable + instalado en celu Android probando todo el flow.

---

### #20 Migrar Twilio sandbox → WhatsApp Business sender (P1)

El sandbox requiere que cada nuevo número haga `join <palabra>` antes de recibir. No escala para producción ni para testers de TestFlight.

**Pasos**:
1. Comprar número WhatsApp en Twilio Console o usar uno existente
2. Solicitar habilitación WhatsApp Business (revisión Meta, 3-7 días)
3. Template OTP ya aprobado (`HX229f5a04fd0510ce1b071852155d3e75`)
4. Updatear `TWILIO_WHATSAPP_FROM` en Supabase secrets

DoD: clientes nuevos reciben OTP sin `join` previo.

---

### #21 Privacy Policy + Soporte en fuxiaballerinas.com (P0 Apple)

Apple exige ambas URLs antes de submit a producción.

**Pages a crear**:
- `https://fuxiaballerinas.com/privacy` — copy template en `APP_STORE_METADATA.md`
- `https://fuxiaballerinas.com/soporte` — email + FAQ básico
- Email `soporte@fuxiaballerinas.com`

DoD: ambas URLs accesibles públicamente, contenido al día.

---

### #22 Screenshots para App Store (P1)

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

### #23 Store Scanner para vendedoras (P2)

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

### #24 useAuth como Context compartido (P2, tech-debt)

Hoy cada pantalla con `useAuth()` hace queries propias → 3-4x duplicadas al cambiar tabs. Mover a `AuthProvider` Context.

- [ ] Crear `AuthProvider` que expone state + actions
- [ ] `useAuth()` pasa a ser consumer
- [ ] Envolver `<AuthProvider>` en `app/_layout.tsx`
- [ ] Exponer `refresh()` para recargar on-demand

---

### #25 Wire grid actions del Profile (P3)

Tiles "Seguimiento", "Regalar", "Pagos" están sin destino. Solo "Mis Compras" funciona. Decidir:
- Implementar (cada uno tiene su sub-spec)
- Ocultarlos hasta tener spec
- Reemplazarlos por links útiles

---

### #26 ITSAppUsesNonExemptEncryption (P2, Apple)

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

### #27 Push notifications testing en device real (P1)

Los push solo funcionan en builds nativos (no Expo Go iOS). Una vez la build esté en TestFlight:
- [ ] Instalar TestFlight build en iPhone propio
- [ ] Loguear → confirmar que `push_tokens` se inserta
- [ ] Forzar webhook → confirmar que llega notificación

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
