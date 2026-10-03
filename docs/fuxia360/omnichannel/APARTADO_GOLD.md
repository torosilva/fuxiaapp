# Entrega inmediata + Apartado Gold (staging)

**Decisiones de Mario (2026-10-02):**
- Funciona en la web y en la app.
- "Gold" es el nivel Gold del programa de lealtad actual.
- Una clienta puede tener **máximo 2 pares apartados a la vez**.
- El apartado dura **2 horas**; si no llega, no pasa nada.
- Piloto: **Tienda Polanco**.
- Por ahora solo con teléfonos de prueba.

## Cómo funciona

| | |
|---|---|
| **Entrega inmediata** | En la página del producto, al elegir talla: "✓ Entrega inmediata hoy en Tienda Polanco". Solo aparecen tiendas con inventario en Fuxia 360 y al menos un par **libre** de esa talla. No se muestran cantidades. |
| **Apartado** | La clienta Gold pone su teléfono y el código, y el par queda apartado 2 horas en la tienda. El par **no se mueve**: sigue en la tienda, pero nadie más lo puede comprar ni transferir. |
| **Si llega** | La vendedora vende con la tarjeta (QR) de la clienta y el apartado se cierra solo como **vendido**. |
| **Si no llega** | A las 2 horas se libera solo (un job cada minuto). No hay consecuencias. |
| **Equipo** | Admin → **Apartados Gold**: activos con el tiempo que queda, historial de 7 días y cancelar con motivo. Del teléfono solo se muestran los últimos 4 dígitos. |

## Piezas

- Migraciones:
  - `20261007001100_f360_reservations.sql`: tabla, reglas, venta en tienda y vencimiento.
  - `20261007001200_f360_reserve_web.sql`: verificación de Gold para la web.
  - Cada una tiene su rollback.
- Función pública `f360-store-reserve`, desplegada **solo en staging**:
  - Acciones: `availability`, `send_code` y `reserve`.
  - Solo acepta el origen de staging4.
  - **En pruebas:** solo los teléfonos de prueba pueden apartar, con un código fijo de prueba. No se envía WhatsApp. Cualquier otro teléfono recibe "en pruebas".
- Fragmento para WordPress: `tools/storefront/f360-entrega-inmediata.html`.
- Pruebas:
  - Base de datos: 24 pruebas (Gold, máximo 2, 2 horas, venta con y sin la clienta, transferencia bloqueada, vencimiento, cancelar, web).
  - Función: 5 pruebas.
  - Recorrido real en staging4: `screens/web-0*.png`.

### Instalar el fragmento en staging4 (Adrián)

1. Abre Bricks → plantilla de **producto individual**.
2. Agrega un elemento **Code** con "Ejecutar código" debajo del botón **Añadir al carrito**.
3. Pega completo `tools/storefront/f360-entrega-inmediata.html`.
4. Excluye la página de producto de la caché dinámica de SiteGround, o confirma que se purga, para que la disponibilidad se vea al momento.

## App (siguiente paso; requiere decisiones)

Hallazgos en `fuxia-native`:
- **El modo vendedora vende con el sistema anterior.** Escribe `channel_inventory` desde el teléfono y no usa `f360_record_store_sale`.
- **Una tienda con inventario en Fuxia 360 (como Polanco) todavía no puede vender desde la app.** `components/SellerShiftLogin.tsx` muestra "venta todavía no está habilitada".
- **Las notificaciones push** usan la tabla `push_tokens` por clienta. Las vendedoras son clientas con cuenta, así que se les puede notificar. Hoy no hay ninguna notificación por tienda ni al tocar el aviso.
- **La app apunta a Supabase de producción.** Para probar con staging hace falta una versión de prueba (perfil EAS con las variables de staging, distribución interna).

Plan propuesto para que **las vendedoras reciban los apartados**:
1. **Aviso push al apartar.** Una notificación a las vendedoras asignadas a esa tienda: "Aparta Botas Largas Café 37 para Ana · hasta 6:40 p. m.".
2. **"Apartados" en el modo vendedora.** Los activos de su tienda, con un botón **"Ya lo separé"** para que el equipo sepa que el par está en el mostrador.
3. **Venta en tienda con Fuxia 360 en la app.** Conectar `f360_record_store_sale` para tiendas con inventario en Fuxia 360. Con eso, vender con la tarjeta de la clienta cierra su apartado.
4. **Botón "Apartar" en la app de clientas** (fase 4), en la ficha del producto, junto a "Comprar en la web".
5. **Versión de prueba de la app contra staging** (Android interno / TestFlight) para probarlo todo antes de publicar.
