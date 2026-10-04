# CRO-4 · Sticky "Añadir al carrito" (staging)

**Dónde:** `tools/storefront/f360-entrega-inmediata.html`, el mismo Code de la ficha de producto que ya está en Bricks; no es un elemento nuevo. Función `stickyCompra()`.

**Regla:** el sticky **no tiene lógica de compra**.
- Refleja el estado del botón de Woo: falta elegir / no disponible / comprable, incluidos los backorders de "5 a 7 días".
- Al tocarlo hace `click()` en ese mismo botón. Precio, stock, MTO, Gold y validación siguen siendo de Woo y del servidor.

| Estado del botón de Woo | Sticky |
|---|---|
| Falta color | "Elige tu color" → desplaza a los colores y los resalta |
| Falta talla | "Elige tu talla" → desplaza a las tallas |
| Variante no disponible (`wc-variation-is-unavailable`) | "No disponible" (gris) → lleva a tallas |
| Variante comprable (incluye 5–7 días) | El mismo texto que el botón de Woo ("Añadir al carrito") → `click()` en el botón real |
| Producto agotado sin botón | No aparece |

**Visibilidad y convivencia con otros elementos:**
- Solo en ≤ 900 px y solo mientras el botón real está fuera de pantalla (IntersectionObserver).
- Mientras se ve el sticky, "Descarga la app" se oculta y el botón de Hilo sube por encima.
- Muestra el nombre del modelo, el color, la talla (MX en `/mx/`, número de tienda en `/co/`) y el precio que da Woo para la variante.

**Pruebas:** ver `05_MOBILE_IAB_RESULTS.md`. Matriz MX/CO, F360 y legacy, móvil y escritorio: carrito 0 → 1, carrito y checkout cargan, 0 errores JS. Capturas: `st_*_1.png` (antes de elegir) y `st_*_2.png` (listo para añadir).

**Pendiente:**
- Probar en teléfonos reales (IAB-0).
- Caso "No disponible" con una variante real sin stock y sin backorder: en staging casi todo tiene backorder.

**Eventos (no implementados, GTM bloqueado):** definidos en `growth/G2_MEASUREMENT_CONTRACT.md` §4.2:
- `f360_sticky_atc_view` (una vez por página);
- `f360_sticky_atc_click` con `sticky_state` = `elegir_color` / `elegir_talla` / `no_disponible` / `anadir`.

El anterior `sticky_atc_scroll_to_selector` queda cubierto por los estados `elegir_*`.
