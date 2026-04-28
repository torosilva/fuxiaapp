# Fuxia Ballerinas

App de lealtad mobile para clientas de [fuxiaballerinas.com](https://fuxiaballerinas.com). Tarjeta de lealtad digital con QR, niveles (Bronce / Plata / Oro), historial de compras y notificaciones de puntos.

## Stack

- **Frontend**: React Native + TypeScript + Expo SDK 54 + expo-router (file-based)
- **Backend**: Supabase (Postgres + Auth + Edge Functions + Storage)
- **Auth**: WhatsApp OTP via Twilio (sandbox por ahora; migrar a WhatsApp Business para producción)
- **E-commerce**: WooCommerce REST API en fuxiaballerinas.com (proxy via Supabase Edge Function)
- **Build/distribución**: EAS Build → TestFlight (iOS) y APK (Android)
- **Notificaciones**: expo-notifications + Expo Push API

## Estructura

```
fuxiaapp/
├── fuxia-native/                     # Expo app
│   ├── app/                          # expo-router (pantallas)
│   │   ├── (tabs)/                   # tab navigation
│   │   ├── onboarding/               # welcome → country → phone → verify → complete-profile
│   │   ├── product/[id].tsx          # detalle de producto
│   │   └── purchases/                # "Mis Zapatos" historial
│   ├── components/                   # LoyaltyCard, ProductCard, etc.
│   ├── lib/                          # supabase client, hooks/useAuth, notifications
│   ├── services/                     # WooCommerceService (via proxy)
│   └── supabase/functions/           # edge functions (deployadas a Supabase)
│       ├── whatsapp-otp/             # OTP send/verify + check_phone
│       ├── woocommerce-webhook/      # recibe order.updated → suma puntos + push
│       ├── woocommerce-proxy/        # proxy lectura WC con secrets server-side
│       ├── calculate-points/         # (legacy, lógica inlined en useAuth)
│       └── calculate-tier/           # (legacy, lógica inlined en useAuth)
├── database/
│   ├── schema.sql                    # tablas base
│   ├── otp_migration.sql
│   ├── avatar_migration.sql          # avatar_url + bucket storage
│   └── push_tokens_migration.sql
├── claude-prompts/                   # planning original
├── BACKLOG.md                        # issues pendientes para GitHub Projects
├── APP_STORE_METADATA.md             # textos + checklist Apple
└── README.md                         # este archivo
```

## Modelo de puntos

| Regla | Valor |
|---|---|
| Puntos por compra | 1 punto cada $50 MXN |
| Bonus por par | +10 puntos por par de zapatos |
| Bronce | 0–500 pts ó 0–5 pares |
| Plata | 501–1,200 pts ó 6–12 pares |
| Oro | 1,201+ pts ó 13+ pares |

## Setup local

### Pre-requisitos

- Node.js 20+
- Cuenta Expo (`npx eas login`)
- Acceso al proyecto Supabase (project ref: `tgzgiwfzddsghnxgkcqd`)
- Expo Go en tu celular (para dev rápido) o build de EAS instalado (para testing real con push iOS)

### Instalar y correr

```bash
cd fuxia-native
npm install
cp .env.example .env  # ver "Variables de entorno" abajo
npx expo start --tunnel
```

Escanear el QR con Expo Go o conectar via `exp://...exp.direct`.

### Variables de entorno

Crear `fuxia-native/.env`:

```bash
EXPO_PUBLIC_SUPABASE_URL=https://tgzgiwfzddsghnxgkcqd.supabase.co
EXPO_PUBLIC_SUPABASE_ANON_KEY=<anon-key-publica>
```

Para EAS builds, las mismas variables están seteadas en el environment "preview"/"production" de EAS Project (no se commitean al repo).

### Secrets server-side (en Supabase Edge Functions, no en el cliente)

| Secret | Para qué |
|---|---|
| `SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY` | acceso DB con permisos elevados |
| `TWILIO_ACCOUNT_SID` / `TWILIO_AUTH_TOKEN` | enviar WhatsApp |
| `TWILIO_WHATSAPP_FROM` | número origen (`whatsapp:+14155238886` sandbox) |
| `TWILIO_CONTENT_SID` | template aprobado para OTP |
| `WC_URL` / `WC_CONSUMER_KEY` / `WC_CONSUMER_SECRET` | proxy a WooCommerce |
| `WC_WEBHOOK_SECRET` | validar firma HMAC del webhook de WC |

Setear con `npx supabase secrets set KEY=value --project-ref tgzgiwfzddsghnxgkcqd`.

## Flujos clave

### Onboarding (signup)

1. Welcome animado → tap **CREAR CUENTA**
2. País (MX / CO / GT / etc.)
3. Número de teléfono → `whatsapp-otp` action `send`
4. Código de 6 dígitos → action `verify` → crea auth user + sesión
5. Si es nuevo → completar nombre + email opcional → crea customer + loyalty_card con QR único

### Login (returning user)

1. Welcome → tap **"Ya tengo cuenta"**
2. Solo número → action `check_phone` valida que existe → action `send` → action `verify`
3. Sesión persiste en AsyncStorage (no vuelve a pedir OTP hasta logout)

### Compra → puntos

1. Clienta compra en fuxiaballerinas.com (web checkout)
2. WooCommerce dispara webhook `order.updated` → `woocommerce-webhook` edge function
3. Función valida HMAC, busca customer por phone/email, calcula puntos, inserta `transactions` + `purchase_items`, suma a `loyalty_card`, recalcula tier
4. Si subió de tier → inserta `rewards` y manda push notification "¡Subiste a Plata!"
5. Si no → push "Ganaste +X puntos"

### Compra desde la app

1. Tap producto en el tab Shop o Home
2. Detalle muestra preview "Ganarás +X puntos con esta compra"
3. Tap **"Comprar en la web"** → abre WebBrowser con el producto en el sitio + talla seleccionada
4. Checkout en el sitio → webhook → puntos en la app

## Deploy

### Edge Functions

```bash
cd fuxia-native
npx supabase functions deploy <function-name> --project-ref tgzgiwfzddsghnxgkcqd
# usar --no-verify-jwt para webhooks externos (woocommerce-webhook)
```

### Mobile build

```bash
cd fuxia-native
npx eas build --profile preview --platform android   # APK para testing interno
npx eas build --profile testflight --platform ios    # IPA → TestFlight
npx eas submit --platform ios --latest               # subir a App Store Connect
```

### OTA Updates (post-build)

Cualquier cambio JS-only:

```bash
npx eas update --branch preview --message "fix: blah"
```

Cambios nativos (nuevas libs, app.json, plugins) requieren rebuild.

## Documentos relacionados

- [BACKLOG.md](BACKLOG.md) — issues pendientes
- [APP_STORE_METADATA.md](APP_STORE_METADATA.md) — textos y checklist para Apple
- [claude-prompts/fuxia-app-claude-code-prompts.md](claude-prompts/fuxia-app-claude-code-prompts.md) — plan original

## Operaciones

### Rotar Twilio Content SID (template aprobado)

Si Twilio aprueba un template nuevo:

```bash
npx supabase secrets set TWILIO_CONTENT_SID=HX... --project-ref tgzgiwfzddsghnxgkcqd
```

### Rotar WC keys

1. WC admin → Avanzado → Claves REST API → revocar viejas + crear nuevas (read-only suficiente)
2. `npx supabase secrets set WC_CONSUMER_KEY=ck_... WC_CONSUMER_SECRET=cs_...`

### Rotar webhook secret

1. Generar: `openssl rand -hex 32`
2. Updatear en WC (webhook Fuxia Loyalty Sync) y en Supabase con el mismo valor

## Tips de desarrollo

- **No mover el repo dentro de OneDrive** — Files On-Demand corrompe los uploads de EAS y los atributos NTFS bloquean el build (`mkdir EACCES`). Mantener fuera de carpetas sincronizadas en la nube.
- **Mexico WhatsApp**: el número se ingresa como `+52XXXXXXXXXX` pero Twilio WhatsApp MX requiere `+521XXXXXXXXXX`. La función `whatsapp-otp` agrega el "1" automáticamente — no remover.
- **`useAuth` no es Context**: cada pantalla con `useAuth()` hace queries propias. Idea para refactor en BACKLOG #7.
- **Forzar dark mode**: `components/useColorScheme.ts` está hardcoded a `'dark'` ignorando el modo del sistema. Coherente con el diseño "Dark Luxury" de la marca.
