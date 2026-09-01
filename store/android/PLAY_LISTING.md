# Ficha de Google Play — valores para copiar y pegar

Todo sale de `APP_STORE_METADATA.md`, adaptado a los límites y formularios de Play.

---

## Ficha principal (Store listing)

| Campo | Límite | Valor |
|---|---|---|
| Nombre de la app | 30 | `Fuxia Ballerinas` |
| Descripción corta | 80 | `Tu tarjeta de lealtad digital. Acumula puntos con cada par y canjea premios.` (76) |
| Categoría | — | Compras (Shopping) |
| Etiquetas | 5 | moda · compras · lealtad · zapatos · recompensas |
| Email de contacto | — | `soporte@fuxiaballerinas.com` — **es público en la ficha** |
| Sitio web | — | `https://fuxiaballerinas.com` |

> El subtitle de iOS ("Lealtad premium. Un par a la vez.") son 33 caracteres y también
> entra, pero desaprovecha 47 del espacio disponible. La descripción corta es lo segundo
> que lee la gente después del nombre.

### Descripción completa (4000 máx.)

```
Fuxia Ballerinas te acompaña en cada paso. Con nuestra app de lealtad, cada par que compras —en tienda o en línea— se convierte en puntos que te acercan a recompensas exclusivas.

TU TARJETA DE LEALTAD DIGITAL
Accede a tu código QR único desde tu teléfono. Muéstralo en tienda para acumular puntos al instante, sin necesidad de tarjetas físicas.

NIVELES DE RECOMPENSA
• Bronce: tu punto de partida con accesorios gratis al primer hito
• Plata: un par de ballerinas básicas gratis al llegar al nivel
• Oro: un par premium de regalo + beneficios exclusivos

HISTORIAL DE TUS COMPRAS
Revisa cada par que has coleccionado, con fecha, color y talla. Re-compra tus favoritos con un toque.

NOTIFICACIONES INTELIGENTES
Entérate cuando ganas puntos, subes de nivel o cuando tu recompensa está lista para canjear.

SEGURA Y SENCILLA
Ingresa con tu número de WhatsApp. Sin contraseñas que recordar. Tu información está protegida.

Diseñada para quienes creen que un buen par de zapatos cambia el día.
```

> Play no renderiza markdown: los `**negritas**` de la versión de Apple se convirtieron en
> MAYÚSCULAS para los encabezados.

### Gráficos

| Asset | Archivo |
|---|---|
| Icono 512×512 | `store/android/play-icon-512.png` |
| Feature graphic 1024×500 | `store/android/feature-graphic.png` |
| Screenshots de teléfono | **faltan** — mínimo 4, 9:16 |

---

## Contenido de la app (Policy → App content)

Estas son las que bloquean la publicación.

### Data safety

Mismas respuestas que el App Privacy de Apple. Para cada tipo: **recolectado = sí**,
**vinculado al usuario = sí**, **usado para tracking = no**, propósito **App functionality**.

| Tipo de dato | ¿Se recolecta? |
|---|---|
| Número de teléfono | Sí — autenticación |
| Nombre | Sí — personalizar la cuenta |
| Email (opcional) | Sí |
| Fotos | Sí — avatar que el usuario sube |
| Historial de compras | Sí — calcular nivel de lealtad |
| Ubicación / Contactos / Device ID | **No** |

Marcar además: **cifrado en tránsito = sí**, y **el usuario puede solicitar la eliminación
de sus datos = sí**.

### Eliminación de cuenta

Play pide **dos** cosas y hay que dar las dos:

1. **En la app** — ya existe: Perfil → "Borrar cuenta" → edge function `delete-account`.
2. **URL web pública** — donde se pueda solicitar sin instalar la app. Es lo único que
   Apple no pedía. Si todavía no hay página dedicada, sirve apuntar a la de privacidad
   y agregarle un párrafo que explique cómo pedir el borrado (el botón in-app y un mail
   de contacto). Lo que Play rechaza es que no haya nada.

### Resto de declaraciones

| Sección | Respuesta |
|---|---|
| Política de privacidad | `https://fuxiaballerinas.com/privacy` |
| Content rating (IARC) | Cuestionario; con este contenido sale Everyone / 3+ |
| Público objetivo | 18+ (no marcar "dirigida a niños") |
| Anuncios | **No** — la app no muestra publicidad |
| App de gobierno / finanzas / salud | **No** |
| Permisos sensibles | Solo `CAMERA`, justificada por el escáner QR en tienda. `RECORD_AUDIO` está bloqueado en el manifest |

### Acceso para el revisor

Google revisa manualmente las apps con login. Mismo demo account que Apple:

```
País:    México
Teléfono: 5555555555
Código:   555555
```

Nota para el revisor:

```
La app autentica por SMS OTP. Para la revisión existe una cuenta demo que no envía
ningún mensaje y no requiere apps externas:

1. "CREAR CUENTA" en la pantalla de bienvenida
2. Seleccionar México
3. Teléfono: 5555555555
4. Código de verificación: 555555

Entra como usuario demo con datos de lealtad de ejemplo (compras, puntos, nivel).

Eliminación de cuenta: tras iniciar sesión, pestaña Perfil → abajo → "Borrar cuenta".
Dos confirmaciones y se elimina la cuenta, la tarjeta de lealtad y las transacciones.

La app es un cliente de lealtad de una tienda existente (fuxiaballerinas.com).
No hay pagos dentro de la app.
```

---

## Limitación conocida en esta versión

Las **notificaciones push no funcionan en Android**: falta configurar Firebase / FCM V1
(sección 2.3 de `ANDROID_PUBLISHING.md`). La app funciona en todo lo demás. Se arregla
con una actualización posterior, sin nueva revisión.

Conviene no prometerlas en los materiales de lanzamiento hasta que estén.
