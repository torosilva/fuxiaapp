# Fuxia Ballerinas — App Store metadata

Checklist de lo que pide App Store Connect al subir la app a TestFlight/producción.

---

## Identidad

| Campo | Valor |
|---|---|
| **App name** (30 char max) | `Fuxia Ballerinas` |
| **Subtitle** (30 char max) | `Lealtad premium. Un par a la vez.` |
| **Bundle ID** | `com.fuxiaballerinas.app` |
| **SKU** | `fuxia-ballerinas-001` |
| **Primary Category** | Shopping |
| **Secondary Category** | Lifestyle |
| **Content Rights** | No, does not contain third-party content |
| **Age Rating** | 4+ |

---

## Descripciones

### Promotional text (170 char, editable sin re-review)
> Tu tarjeta de lealtad digital. Acumula puntos con cada par, sube de nivel y canjea recompensas exclusivas. Todo desde tu teléfono.

### Description (4000 char)
> Fuxia Ballerinas te acompaña en cada paso. Con nuestra app de lealtad, cada par que compras —en tienda o en línea— se convierte en puntos que te acercan a recompensas exclusivas.
>
> **Tu tarjeta de lealtad digital**
> Accede a tu código QR único desde tu teléfono. Muéstralo en tienda para acumular puntos al instante, sin necesidad de tarjetas físicas.
>
> **Niveles de recompensa**
> • **Bronce**: tu punto de partida con accesorios gratis al primer hito
> • **Plata**: un par de ballerinas básicas gratis al llegar al nivel
> • **Oro**: un par premium de regalo + beneficios exclusivos
>
> **Historial de tus compras**
> Revisa cada par que has coleccionado, con fecha, color y talla. Re-compra tus favoritos con un toque.
>
> **Notificaciones inteligentes**
> Entérate cuando ganas puntos, subes de nivel o cuando tu recompensa está lista para canjear.
>
> **Segura y sencilla**
> Ingresa con tu número de WhatsApp. Sin contraseñas que recordar. Tu información está protegida.
>
> Diseñada para quienes creen que un buen par de zapatos cambia el día.

### Keywords (100 char, coma-separado)
> zapatos, ballerinas, flats, moda, lealtad, puntos, recompensas, sandalias, fuxia, catálogo

### Support URL
> https://fuxiaballerinas.com/soporte  _(crear página)_

### Marketing URL (opcional)
> https://fuxiaballerinas.com

### Privacy Policy URL *(obligatorio)*
> https://fuxiaballerinas.com/privacy  _(crear página)_

---

## App Privacy (Apple lo exige antes de submit)

Responder en App Store Connect → App Privacy:

| Data type | Collected? | Linked to user? | Used for tracking? | Purpose |
|---|---|---|---|---|
| Phone number | **Yes** | Yes | No | App functionality (auth) |
| Name | **Yes** | Yes | No | App functionality |
| Email (opcional) | **Yes** | Yes | No | App functionality |
| Photos | **Yes** | Yes | No | App functionality (avatar) |
| Purchase history | **Yes** | Yes | No | App functionality |
| Location | No | — | — | — |
| Contacts | No | — | — | — |
| Device ID | No | — | — | — |

Explicación clara en el privacy policy: "Recolectamos tu número de teléfono para autenticarte via WhatsApp, tu nombre y email opcional para personalizar tu cuenta, y la foto que tú subas opcionalmente para tu perfil. Tus compras se sincronizan desde fuxiaballerinas.com para calcular tu nivel de lealtad. No vendemos tus datos a terceros ni hacemos tracking."

---

## Screenshots requeridos

Todas en **portrait**. Mínimo **6.7" (iPhone 15 Pro Max — 1290×2796)** y **6.5" (iPhone 11 Pro Max — 1242×2688)**. Sugerido también 5.5" (iPhone 8 Plus — 1242×2208).

Pantallas a capturar (4-8 screenshots):
1. Pantalla welcome (logo animado + "CREAR CUENTA")
2. Tarjeta de lealtad (Bronce/Plata/Oro con QR)
3. Home con hero + categorías
4. Detalle de producto con preview de puntos ("Ganarás +X puntos")
5. Historial "Mis Zapatos" (con compras agrupadas)
6. Perfil con foto y último pedido

**Tip**: usa el simulador iOS con `xcrun simctl io booted screenshot` o EAS Preview. Superpón un título (ej. "Tu lealtad, en tu bolsillo") con Figma antes de subir.

---

## Versión

- **Version**: `1.0.0` (se cambia en cada release)
- **Build**: `1` (incrementa con cada upload — EAS lo hace automático)
- **Copyright**: `© 2026 Fuxia Ballerinas`

---

## Test Information (TestFlight)

| Campo | Valor |
|---|---|
| **Beta App Description** | Fuxia Ballerinas app beta. Testing auth flow, loyalty card and purchase history. |
| **Beta App Feedback Email** | soporte@fuxiaballerinas.com _(crear)_ |
| **Marketing URL** | https://fuxiaballerinas.com |
| **Privacy Policy URL** | https://fuxiaballerinas.com/privacy |
| **Demo account** | Phone: `+525543412939` (Mario Silva test user). Apple reviewer puede requerir OTP — responder rápido al mensaje de WhatsApp. |
| **Notes for reviewer** | "This app uses WhatsApp OTP via Twilio for login. Reviewer: please ask the testing contact (see support email) for an OTP during review. The app is a loyalty rewards client for an existing e-commerce site (fuxiaballerinas.com) — no in-app payments." |

---

## Cuenta Apple Developer (pre-requisito)

- https://developer.apple.com/programs/enroll/ → $99 USD/año
- Si el negocio tiene RFC/EIN, enrollarse como Organization (no Individual) — requiere D-U-N-S number.
- Una vez enrolado: https://appstoreconnect.apple.com → **My Apps** → + → New App

---

## Flujo de build & submit con EAS (sin Mac)

```bash
cd fuxia-native
npm install -g eas-cli
eas login                              # cuenta Expo
eas build:configure                    # genera eas.json si no existe
eas build --platform ios --profile production
# EAS te pide Apple ID + app-specific password → genera IPA firmado en sus servidores
eas submit --platform ios              # sube a App Store Connect → pasa a TestFlight en 10-30 min
```
