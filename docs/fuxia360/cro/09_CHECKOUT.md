# CRO-CHECKOUT (staging) · autorizado 2026-10-04

**Código:** `tools/storefront/f360-compra.html`. Va en un snippet HTML de WPCode, "Site Wide Footer".
- Solo presentación sobre el carrito y el checkout reales de Woo (Woo Blocks sigue siendo el motor).
- Ningún monto se calcula en JS: todo viene de la Store API o del DOM que pintó Woo.
- No toca pasarelas, reglas de cupón, precios, stock, MTO ni Gold.

## Auditoría previa (qué había)
| Tema | Realidad en staging4 |
|---|---|
| Añadir al carrito | AJAX de Bricks (`wc-ajax=bricks_add_to_cart`). Dispara `added_to_cart`. Deja el botón dorado (`bricks-cart-added`) y un link suelto "Ver carrito" (`a.added_to_cart`) |
| Checkout | Woo Blocks. Campos: email*, nombre*, apellidos*, país, dirección*, depto (ya detrás de "+ Añadir apartamento…"), población*, estado, CP*, **teléfono (opcional)**. Empresa: no se muestra. "Usar la misma dirección para facturación": **marcado por defecto** |
| "Crear una cuenta con Fuxia Ballerinas" | Casilla nativa de Woo Blocks: crea una cuenta de cliente de WordPress con ese correo. **No se tocó** (ni copy ni comportamiento) |
| Popup 10% | Snippet PHP en WordPress (`fuxia_lead` por admin-ajax). Guarda correo y WhatsApp opcional y muestra un **cupón fijo `BIENVENIDA10`**. No lo aplica. El WhatsApp se ocultaba tras la caja "+50 puntos" |
| Cupón `BIENVENIDA10` | Existe en Woo staging: 10 % (−$420 sobre $4,200 MX; −COP$55,000 sobre COP$550,000) |
| Pago | Staging4: "No hay métodos de pago disponibles" (pasarelas apagadas) |

## Qué hace (a–f)
- **a) Agregado:** al terminar el AJAX real, se lee el carrito por Store API y aparece el panel "✓ Agregado a tu carrito".
  - Muestra foto, modelo, color, talla (MX en /mx/) y el precio de Woo.
  - **Pagar ahora** va a `/{país}/finalizar-compra/` con el mismo carrito. **Seguir comprando** cierra el panel.
  - Se ocultan el link "Ver carrito" y el estado dorado del botón.
  - La página `/carrito/` sigue funcionando igual.
- **b) Identidad Fuxia en el checkout:** solo CSS sobre las clases de Woo Blocks.
  - Títulos de paso en dorado y mayúsculas; inputs de 54 px con radio 10.
  - Foco dorado; error en rojo #b3261e; botón de pedido negro tipo píldora.
  - Resumen en tarjeta crema.
- **c) Móvil:** botón "Tu pedido · $X ▾" fuera del árbol React de Woo.
  - El total es el texto que pintó Woo y se sincroniza con un MutationObserver.
  - Al tocarlo se abre el resumen nativo de Woo: producto, color/medida, cantidad, subtotal, descuento, envío y total.
- **d) Teléfono:** debajo del campo aparece "Solo para coordinar tu entrega." (uso operativo). No se usa para marketing ni se mezcla con consentimiento.
  - Ponerlo **obligatorio** es un ajuste del bloque de checkout en WordPress (ver Pendientes).
- **e) Confianza:** solo afirmaciones verificables en la página.
  - "Envío gratis en este pedido": solo si el envío de Woo dice Gratis/$0.
  - "Pago seguro con Mercado Pago": solo si el método aparece en la página.
  - "Si no te quedan, cámbialas", con link a la página de Cambios del país.
  - **6 MSI no se muestra** hasta verificarlo con Mercado Pago TEST.
  - **Promesa de entrega: no implementada** (bloqueada por la matriz G).
- **f) Cupón de bienvenida:** cuando el popup muestra su código, se guarda (`localStorage f360_bv_cupon`) y se pide a Woo aplicarlo en cuanto hay carrito.
  - En checkout se usa `wp.data` (store `wc/store/cart`); fuera de checkout, Store API `apply-coupon` con Nonce.
  - Woo valida (vigencia, usos, uso individual) y no duplica.
  - Si Woo lo rechaza, se marca `rechazado` y no se reintenta. Si la clienta lo quita en el checkout, no se vuelve a poner.
- **Popup:** el campo de WhatsApp se ve directo y sigue opcional. Copy: "+50 puntos en Club Fuxia si dejas tu WhatsApp (opcional)", sin lenguaje de publicidad.

## Pruebas (emulador · el snippet se inyecta en cada página como lo haría WPCode)
| Caso | Panel Agregado | Pagar ahora → checkout | Barra móvil | Cupón | Carrito /carrito/ | Errores JS |
|---|---|---|---|---|---|---|
| IG Android · MX · Botas Largas (F360) · cupón BIENVENIDA10 | ✓ Negro · Talla MX 23 · $4,200 | ✓ | "Tu pedido · $3,780" | aplicado: −$420, total $3,780 | ok | 0 |
| IG iPhone · MX · Croc (legacy) · cupón inválido | ✓ Talla MX 23 · $2,800 | ✓ | "Tu pedido · $2,800" | rechazado, sin descuento | ok | 0 |
| IG iPhone · CO · Botas Largas · BIENVENIDA10 | ✓ Negro · Talla 36 · COP$550,000 | ✓ | "Tu pedido · COP$495,000" | aplicado: −COP$55,000 | ok | 0 |
| Escritorio · MX · Croc | ✓ (tarjeta arriba a la derecha) | ✓ | no aplica (solo móvil) | — | ok | 0 |
| Escritorio · CO · Botas Largas | ✓ | ✓ | no aplica | — | ok | 0 |

Capturas en la carpeta temporal de la sesión, para cada caso:
- `cc_*_0pdp` (antes)
- `cc_*_1agregado`
- `cc_*_2checkout`
- `cc_*_3resumen`
- `cc_*_4full`

Antes: `co_atc_after.png` (botón dorado + "Ver carrito") y `co_before_full.png` (checkout sin estilo).

## Pendientes / bloqueos
1. **Instalar** el snippet en WPCode (staging4) y repetir la prueba en el Instagram real de Android.
2. **Mercado Pago TEST** en staging4 (autorizado solo sandbox). Lo configura Mario en el admin; las credenciales no van al repo ni al chat.
   - Verificar: credenciales TEST, ningún cobro real posible, return/webhook a staging4, nada apuntando a producción.
   - La prueba de pago con tarjetas de prueba la hace Mario en su teléfono.
3. **Teléfono obligatorio:** editar la página de checkout → bloque "Dirección de envío" → Teléfono: Obligatorio. Es un ajuste de Woo (validación del servidor), no JS.
4. En el resumen de Woo la línea dice "Medida: 36" (talla tienda). Mostrar "Talla MX 23" requiere un filtro de Woo (PHP) o cambiar el nombre del atributo. Queda para decidir.
5. CusRev: no se tocó (va en CRO-3).
6. Casos de cupón no probados de punta a punta: lead real del popup (evitado para no crear leads ni envíos) y visitante que ya usó el cupón (requiere un pedido real con ese correo).
7. Eventos futuros: según `growth/G2_MEASUREMENT_CONTRACT.md`. Sin tracking.
