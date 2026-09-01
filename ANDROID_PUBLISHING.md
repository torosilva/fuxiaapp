# Publicar Fuxia Ballerinas en Google Play

Checklist de todo lo que hace falta para pasar de "app que corre en iOS" a "app publicada en Play Store".
La app ya está en App Store Connect (ascAppId `6764388920`), así que casi todo el contenido
(descripciones, screenshots, política de privacidad) se reutiliza. Lo que cambia es la cuenta,
las credenciales y algunos requisitos propios de Google.

---

## 0. Estado actual del repo

Ya resuelto en esta rama:

| Punto | Antes | Ahora |
|---|---|---|
| `targetSdkVersion` | fijado en 35 | **36** — es el default de Expo SDK 54, y Play exige API 36 desde el 31-ago-2026. Se quitó el pin de `expo-build-properties` en vez de subirlo: fijar `buildToolsVersion` a mano puede romper el build si esa versión exacta no está en la imagen de EAS |
| Permiso `RECORD_AUDIO` | declarado | **bloqueado** — la cámara solo escanea QR, no graba audio |
| Permisos Android | implícitos | `CAMERA` + `POST_NOTIFICATIONS` explícitos |
| Formato de build | APK (preview) | **AAB** en el perfil `production` (Play solo acepta App Bundle) |
| `eas submit` Android | no existía | configurado con track `internal` y `releaseStatus: draft` |

### ⚠️ El identificador de Android NO es el mismo que el de iOS

| Plataforma | Identificador |
|---|---|
| iOS (`bundleIdentifier`) | `com.fuxiaballerinas.app` |
| Android (`package`) | **`com.fuxiaballerinas.loyalty`** |

`com.fuxiaballerinas.app` ya estaba tomado en Google Play por una app creada antes en
la cuenta personal. Los package names de Play son **únicos a nivel global y permanentes**:
no se liberan ni borrando la app, así que se eligió uno nuevo para Android.

Son namespaces independientes, no hay ningún problema en que difieran. Pero hay que usar
`com.fuxiaballerinas.loyalty` — y no el de iOS — en **todo lo que sea Android**: la ficha de
Play Console, el proyecto de Firebase y cualquier deep link con intent filter. Los deep links
actuales usan el scheme `fuxia://`, que no depende del package name.

Falta lo que no se puede hacer desde el repo: cuenta, credenciales y contenido de la ficha.

---

## 1. Cuenta de Google Play Console — **el bloqueador más largo**

1. Crear cuenta de desarrollador: https://play.google.com/console/signup → **25 USD, pago único** (no anual como Apple).
2. Elegir tipo de cuenta:
   - **Organización** (recomendado si el negocio tiene RFC): pide un **D-U-N-S number** y verificación del negocio. Tarda días/semanas.
   - **Personal**: verificación de identidad con documento oficial.
3. **Requisito de testing para cuentas personales**: si la cuenta es de tipo *personal* y se creó después de nov-2023, Google exige **20 testers reales opt-in durante 14 días seguidos** en closed testing antes de poder solicitar acceso a producción.

✅ **Estado: resuelto.** La cuenta de Fuxia es de tipo **organización**, así que está **exenta** de ese requisito. Se puede ir de internal testing directo a producción sin esperar las 2-3 semanas.

---

## 2. Credenciales técnicas

### 2.1 Keystore de firma
EAS lo genera y lo custodia solo. No hay que hacer nada:
```bash
cd fuxia-native
eas credentials --platform android      # ver / gestionar
```
Activar también **Play App Signing** en la Console (Google guarda la llave de firma final).
Guarda un respaldo del keystore de upload: `eas credentials` → *Download keystore*.

### 2.2 Service account para `eas submit`
Sin esto hay que subir el AAB a mano en cada release.

1. Play Console → **Setup → API access** → vincular un proyecto de Google Cloud.
2. Google Cloud → **IAM & Admin → Service Accounts** → crear una → **Keys → Add key → JSON**.
3. Volver a Play Console → **Users and permissions** → invitar el email de la service account con permiso **Release manager** (o al menos *Release to testing tracks* + *View app information*).
4. Guardar el JSON como `fuxia-native/google-play-service-account.json`.
   Ya está en `.gitignore` — **nunca commitearlo**. Alternativa mejor: `eas secret:create` y referenciarlo desde ahí.

### 2.3 Firebase / FCM V1 — necesario para push notifications
`expo-notifications` en Android **no funciona sin Firebase**. iOS usa APNs, Android usa FCM.

1. https://console.firebase.google.com → crear proyecto (o reusar uno).
2. Add app → Android → package name exacto: **`com.fuxiaballerinas.loyalty`**.
3. Descargar `google-services.json` → ponerlo en `fuxia-native/`.
4. Referenciarlo en `app.json`:
   ```json
   "android": { "googleServicesFile": "./google-services.json" }
   ```
5. Subir la credencial FCM V1 a EAS: `eas credentials` → Android → *Push Notifications (FCM V1)* → subir el JSON de la service account de Firebase.

Sin esto la app compila y corre, pero **ninguna notificación llega en Android**.

---

## 3. Assets gráficos de la ficha de Play

Distintos a los de Apple — hay que producir dos que no existen todavía:

| Asset | Requisito | Estado |
|---|---|---|
| **Icono de la app** | 512×512 PNG, 32-bit, sin transparencia | derivar de `assets/images/icon-brand.png` |
| **Feature graphic** | **1024×500 PNG/JPG, obligatorio** | ⚠️ **no existe — hay que diseñarlo** |
| **Screenshots de teléfono** | mín. 4 (máx. 8), 16:9 o 9:16, lado corto ≥ 320px, largo ≤ 3840px | reusar los de iOS re-encuadrados, o capturar en emulador |
| Screenshots de tablet 7"/10" | opcional, pero sin ellos Play marca la app como "no optimizada para tablets" | opcional |
| Video promocional | opcional (URL de YouTube) | — |

Las mismas 6 pantallas del plan de iOS sirven: welcome, tarjeta de lealtad con QR, home, detalle de producto, "Mis Zapatos", perfil.

---

## 4. Contenido de la ficha (Store listing)

Se reutiliza casi todo de `APP_STORE_METADATA.md`, con límites distintos:

| Campo | Límite Play | Valor |
|---|---|---|
| App name | 30 | `Fuxia Ballerinas` |
| Short description | **80** | ⚠️ el subtitle de Apple (33 char) cabe: `Lealtad premium. Un par a la vez.` |
| Full description | **4000** | reusar la descripción de App Store tal cual |
| Categoría | — | Shopping |
| Etiquetas | hasta 5 | moda, compras, lealtad, zapatos, recompensas |
| Email de contacto | obligatorio y **público** | `soporte@fuxiaballerinas.com` (crear) |
| Website | opcional | https://fuxiaballerinas.com |
| Política de privacidad | **obligatoria** | https://fuxiaballerinas.com/privacy — plantilla en `wordpress/page-privacy.php`, falta publicarla |

---

## 5. Declaraciones obligatorias en Play Console

Estas se llenan en **Policy → App content** y bloquean la publicación si faltan:

- [ ] **Data safety form** — el equivalente al App Privacy de Apple. Reusar la tabla de `APP_STORE_METADATA.md`: teléfono, nombre, email, fotos e historial de compras, todos *collected + linked to user*, ninguno para tracking. Declarar cifrado en tránsito y que el usuario puede pedir borrado.
- [ ] **URL de eliminación de cuenta** — Play exige una **página web pública** donde se pueda solicitar el borrado, no basta con el botón in-app. El botón ya existe (Perfil → "Borrar cuenta" → edge function `delete-account`), pero hay que publicar además algo como `https://fuxiaballerinas.com/eliminar-cuenta` y declarar la URL en la Console.
- [ ] **Content rating** — cuestionario de IARC. Con este contenido sale *Everyone / 3+*.
- [ ] **Target audience** — declarar 18+ (o 13+); si se marca "dirigida a niños" se activan las reglas de Families Policy.
- [ ] **Ads** — declarar **No** (la app no muestra publicidad).
- [ ] **Government apps / Financial features / Health** — todo **No**.
- [ ] **Permisos sensibles** — con `RECORD_AUDIO` ya bloqueado no hay que justificar micrófono. `CAMERA` se justifica solo con el flujo de QR.
- [ ] **Credenciales de prueba para el revisor** — mismo demo account que Apple: México, teléfono `5555555555`, código `555555`. Google también revisa manualmente apps con login.

---

## 6. Build y submit

```bash
cd fuxia-native

# 1. AAB de producción firmado (EAS maneja el keystore)
eas build --platform android --profile production

# 2. Primera subida: hacerla MANUAL en Play Console
#    (Google requiere que el primer AAB del package se suba a mano
#     para poder crear la ficha; eas submit falla si la app no existe aún)
#    Play Console → Create app → Internal testing → subir el .aab descargado

# 3. Releases siguientes: automático
eas submit --platform android --profile production
```

Progresión de tracks recomendada: **Internal testing** (hasta 100 testers, disponible en minutos) → **Closed testing** (aquí se cumplen los 14 días / 20 testers si aplica) → **Production**.

Tiempo de revisión de Google: horas a 7 días para la primera publicación; los updates suelen ser mucho más rápidos.

---

## 7. Antes de subir — probar en Android de verdad

La app nunca corrió en Android; hay cosas que solo se ven ahí:

- [ ] APK de preview en un teléfono real: `eas build --platform android --profile preview`
- [ ] **Edge-to-edge** está activo (`edgeToEdgeEnabled: true`) — revisar que ninguna pantalla quede tapada por la barra de navegación o el notch.
- [ ] **Botón físico / gesto de "atrás"** en cada pantalla (no existe en iOS). `predictiveBackGestureEnabled` está en `false`, así que el back es el clásico.
- [ ] Permiso de cámara en el escáner QR (`components/QRScanner.tsx`) y en el picker de foto de perfil.
- [ ] Permiso `POST_NOTIFICATIONS` — en Android 13+ hay que pedirlo en runtime; verificar que `lib/notifications.ts` lo solicite y que el canal `default` se cree.
- [ ] Deep links con el scheme `fuxia://` y los intent filters.
- [ ] Fuentes, `expo-linear-gradient` y las animaciones de `moti` / `reanimated` en gama media.

---

## Orden sugerido

1. **Hoy**: abrir la cuenta de Play Console (es lo que más tarda) y publicar las páginas de privacidad y de eliminación de cuenta.
2. En paralelo: crear el proyecto Firebase y diseñar el feature graphic 1024×500.
3. Build de preview y probar en un Android real.
4. Llenar la ficha y las declaraciones de App content.
5. Build de producción → Internal testing → Closed testing → Producción.
