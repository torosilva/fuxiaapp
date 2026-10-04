# CRO-IAB-0 · Diagnóstico del navegador de Instagram/Facebook (protocolo)

**Prioridad:** P0. **Ambiente:** STAGING (staging4). **Estado:** protocolo listo; **no ejecutado**.

Requiere teléfonos reales y no se declara ningún PASS sin prueba en dispositivo. **No** se cambian SiteGround ni el checkout. **No** se implementan `intent://`, `x-safari-*`, redirecciones forzadas ni servicios de deep links.

## 1. Matriz

| # | Dispositivo / navegador | Cómo llegar |
|---|---|---|
| A | iPhone · **Instagram** (IAB) | Link a staging4 en DM, bio de una cuenta de prueba o historia con link |
| B | iPhone · **Safari** | Mismo link copiado |
| C | Android · **Instagram** (IAB) | Igual que A |
| D | Android · **Chrome** | Igual que B |
| (E) | iPhone/Android · **Facebook** (IAB) | Opcional, mismo flujo |

Cada celda recorre este flujo; en cada paso se marca **OK / FALLA / LENTO (> 5 s)** y se toma una captura:

1. Home `/mx/`
2. Tienda: buscar "bota", filtrar Botas, color y talla
3. Página de producto (Botas Largas)
4. Elegir color
5. Elegir talla (el recuadro de entrega aparece)
6. Añadir al carrito
7. Carrito: el producto y la talla siguen ahí
8. Checkout: los campos cargan y la dirección se guarda
9. Pago en **modo prueba** (Mercado Pago / ePayco, credenciales de prueba de staging): redirección a la pasarela, 3DS si aplica
10. Regreso a la tienda: página de "pedido recibido"
11. Pedido en Woo: estado correcto; en Fuxia 360, la línea ingerida

**Precondición:** la pasarela de staging4 en **sandbox**. Hay que confirmarlo antes y **nunca** usar tarjeta real.

## 2. Sospechosos a revisar

| Área | Qué revisar | Señal |
|---|---|---|
| **SiteGround Optimizer** | ~30 scripts con `defer`; combinar o minificar JS; "Delay JS" | jQuery no listo cuando corren `found_variation` y los fragmentos; errores de JS en el IAB |
| **Caché dinámica SG** | Páginas de carrito o checkout servidas desde caché | Carrito vacío al volver; nonce vencido |
| **Cookies de sesión Woo** | `wp_woocommerce_session_*` y `woocommerce_cart_hash` en el WebView (SameSite, ITP en iOS) | Carrito que se pierde entre páginas |
| **Selector de país** | `fuxia_set_country` (AJAX + recarga) | Ciclos de redirección, cambio de moneda a media compra |
| **Bricks** | Galería (flexslider), elementos Código | Pantalla en blanco, eventos que no se disparan |
| **Pasarelas** | Redirecciones a dominios externos, 3DS en ventana nueva, `return_url` | El IAB bloquea la ventana o pierde la sesión al volver |
| **Fragmentos F360** | `fetch` a Supabase (CORS solo staging4), `localStorage` | Errores de CORS; `localStorage` no disponible (ya tiene `try/catch`) |

## 3. Telemetría técnica mínima (diseño, no implementado)

Para registrar fallas reales sin datos personales.

**Cada evento lleva:**
- `ts`
- `session_tech_id` (aleatorio por pestaña, no persistente entre visitas)
- `iab` (`instagram` / `facebook` / `none`, por User-Agent)
- `os` (`ios` / `android` / `other`)
- `route` (path sin query)
- `stage`: home / plp / pdp / color / size / atc / cart / checkout / payment / return
- `event` (`stage_view` / `js_error` / `xhr_error`)
- `error` (mensaje truncado a 200 caracteres, sin URL con query)

**No se registra:** teléfono, correo, nombre, IP, contenido del carrito, ni datos de pago.

**Destino:** una tabla `f360.storefront_tech_events` con retención de 30 días, escrita solo por la Edge Function. Requiere aprobación antes de crearla.

## 4. Fallback (diseño, no implementado)

Solo si el diagnóstico demuestra una falla:
- Aviso no intrusivo, visible **únicamente en el IAB y después de una falla detectada** (por ejemplo, un `js_error` en checkout): "¿Problemas para comprar? Abre Fuxia en Safari o Chrome para continuar."
- Botón "Copiar link" con URL, producto, variante y UTMs.
- Restaurar el carrito con un parámetro `?f360_cart=` firmado. Requiere diseño de seguridad.
- **No** se expulsa preventivamente a nadie de Instagram.

## 5. Qué necesito de Mario/Adrián para ejecutarlo

1. Un iPhone y un Android con Instagram (puede ser el tuyo y el de Adrián).
2. Confirmar que las pasarelas de staging4 están en modo prueba y tener credenciales de prueba.
3. 30–45 minutos para recorrer la matriz juntos. Yo preparo la hoja de resultados y analizo los errores.
