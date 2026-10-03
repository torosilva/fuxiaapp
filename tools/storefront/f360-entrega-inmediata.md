# Fragmento "Entrega inmediata + Apártalo 2 horas"

Archivo: `f360-entrega-inmediata.html`. Se pega **completo** en un elemento **Code** de Bricks (plantilla de producto individual, debajo de "Añadir al carrito").

Fuxia 360 · "Entrega inmediata" + "Apártalo 2 horas" (Fuxia Gold) para la página de producto (Bricks → elemento "Code",
  con "Ejecutar código"). Dónde va: plantilla de producto individual, debajo del botón de comprar (o al final del elemento
  de tallas). No cambia nada del formulario de WooCommerce.

  Qué hace:
    · al elegir talla (y color), pregunta a Fuxia 360 en qué tiendas hay un par LIBRE de esa talla hoy
      (sin mostrar cantidades) y muestra "Entrega inmediata hoy en: Tienda Polanco";
    · si hay tienda: botón "Fuxia Gold: apártalo 2 horas" → teléfono → código → apartado. El par queda separado en la
      tienda 2 horas; si la clienta no llega, se libera solo (sin consecuencias).
  STAGING: endpoint de staging y solo teléfonos de prueba (código de prueba, no se envía WhatsApp).

## Instalación en Bricks
1. Bricks → Ajustes → **Código personalizado** → activar **Ejecución de código** (para administradores).
2. En el elemento Code: activar **Ejecutar código**. Si Bricks lo pide, **Firmar código** (Bricks ≥ 1.9.7).
3. Si en la página se ve el código como texto, falta el paso 1 o 2.
4. Purgar caché de SG.

Solo se muestra en la tienda de México (raíz o `/mx/`), nunca en `/co/`.
