# CRO-IAB-0 · Resultados (2026-10-04)

**Estado: PRE-CHECK EMULADO = PASS · TELÉFONOS REALES = PENDIENTE.** Ningún PASS de esta tabla sustituye la prueba en dispositivo (protocolo: `05_MOBILE_IAB.md`).

## 1. Pre-check emulado (Playwright · Chromium)
Qué se hizo:
- User-Agent real de Instagram (iOS y Android); en iPhone, viewport recortado al tamaño del IAB (390×620).
- Flujo: Home → Tienda → PDP → color → talla → Añadir al carrito (con el **sticky nuevo** en móvil) → Carrito → Checkout.
- El carrito se verificó por la Store API (`items_count` antes y después).

| Perfil | País | Producto | Resultado | Errores JS |
|---|---|---|---|---|
| Instagram iPhone (UA + viewport IAB) | MX | Botas Largas (F360 color+talla) | 11/11 PASS | 0 |
| Safari iPhone 13 | MX | Botas Largas | 11/11 PASS | 0 |
| Instagram Android (Pixel 7, WebView UA) | MX | Botas Largas | 11/11 PASS | 0 |
| Chrome Android (Pixel 7) | MX | Botas Largas | 11/11 PASS | 0 |
| Instagram iPhone | MX | Croc (legacy, solo talla) | 10/10 PASS | 0 |
| Instagram iPhone | CO | Botas Largas | 11/11 PASS | 0 |
| Instagram Android | CO | Botas Largas | 11/11 PASS | 0 |
| Chrome Android | CO | Croc (legacy) | 10/10 PASS | 0 |
| Escritorio 1366 | MX | Botas Largas (botón normal; el sticky no aparece) | 9/9 PASS | 0 |
| Escritorio 1366 | CO | Croc (botón normal) | 8/8 PASS | 0 |

**Hallazgo:** en `/co/`, a un visitante geolocalizado en México le aparece el aviso "Parece que estás en México… Sí, ir a México / Seguir en Colombia". Ese aviso tapa la parte baja de la pantalla, incluido el sticky, hasta que se responde. No rompe la compra; es el comportamiento esperado del selector de país. La primera corrida falló en CO solo por eso.

**Límites del emulado:**
- No es WebKit real ni el WebView real de Instagram, así que no detecta ITP, cookies de terceros ni el manejo de ventanas del IAB.
- No se probó el pago ni el regreso de la pasarela: falta confirmar que las pasarelas de staging4 están en sandbox.

## 2. Teléfonos reales: PENDIENTE (Mario/Adrián)
Orden: Instagram iPhone → Safari iPhone → Instagram Android → Chrome Android.
- Link: mandarse por DM de Instagram `https://staging4.fuxiaballerinas.com/mx/producto/botas-largas/` y abrirlo desde el DM.
- En cada paso anotar PASS/FAIL, el modelo de teléfono, la versión del sistema, el navegador y la URL. Si algo falla, grabar pantalla.
- Pago: solo si Mario confirma que la pasarela de staging4 está en modo prueba. Nunca con tarjeta real.
