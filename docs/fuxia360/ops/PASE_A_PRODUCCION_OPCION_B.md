# Pase a producción · Opción B (Mario, 2026-10-05)

**Decisión:** Fuxia 360 se instala en la base de producción de la app (`tgzg…`, la que usa la app publicada en App Store / Google Play) y **todo lo que Carolina capturó en el ambiente actual (`faltx…`) se copia tal cual, con los mismos identificadores**. Nada se recaptura. Al terminar, se crea un ambiente de pruebas nuevo como copia.

**Por qué B y no A:**
- La app publicada trae fija la base `tgzg…`.
- Mover producción a `faltx…` obligaba a publicar una app nueva y esperar la revisión de Apple y Google, con dos bases vivas mientras tanto.
- Con B la app no se toca.

**Regla:** cada fase se ejecuta solo con aprobación explícita de Mario de *esa* fase, con ensayo previo y respaldo. Este documento es el plan; **nada de esto se ha ejecutado**.

## Estado de partida (verificado 2026-10-05)

| | Ambiente actual `faltx…` (hoy llamado "staging") | Producción `tgzg…` |
|---|---|---|
| Esquema Fuxia 360 | 65 migraciones aplicadas | Solo el baseline; **ninguna** migración F360 |
| Datos de Carolina | 62 modelos, 894 variantes, 575 fotos (bucket `product-images`), 666 homologaciones confirmadas, precios por moneda, categorías, 8 ubicaciones, fichas "Ajuste y talla" | — |
| Clientas / Gold / puntos / compras de la app | 6 clientas de prueba | **Las reales** |
| Tienda conectada | staging4 (copia; sus pedidos son de prueba, `is_test`) | fuxiaballerinas.com |
| Admin | fuxia360-staging.vercel.app | no existe |

## Fases

### F0 · Proteger lo de Carolina (ya, sin riesgo)
- **Respaldo diario** de los datos maestros de `faltx…`: catálogo, variantes, colores, tallas, fotos (lista + archivos), precios, categorías, homologación, ubicaciones, fichas de ajuste y ventas pasadas. Es solo lectura, en un archivo con fecha.
- Carolina **sigue capturando** en el admin actual hasta F4. No se pierde nada.

### F1 · Auditoría de migraciones para producción
- Las 65 migraciones se revisan una por una. **9 traen datos de staging** y se separan en "esquema" vs "datos del ambiente":
  - `20260930000100` (roles y ubicaciones);
  - `20261003000100`;
  - `20261005000100`;
  - `20261007000100`;
  - `20261007000900`;
  - `20261007001300`;
  - `20261007001400`;
  - `20261009000300` (canales de prueba);
  - `20261010000100` (permisos de datos por nombre).
- Se revisa cada `ALTER` y `CREATE OR REPLACE` sobre tablas `public.*` que la app de producción usa (`customers`, `loyalty_cards`, `offline_sales`, `transactions`…). La app publicada debe seguir funcionando igual; las pruebas de compatibilidad ya existen en staging.
- **Resultado:** lista exacta de qué se aplica y en qué orden, más el script de "datos de producción" (canal real `woo_production`, usuarios reales, permisos).

### F2 · Ensayo completo en una copia de producción
- Copia de la base de producción **sin datos personales** (Q6 prohíbe copiar clientas reales a pruebas), o un proyecto temporal con el esquema de producción.
- Ensayo:
  1. aplicar las migraciones;
  2. cargar los datos maestros de `faltx…`;
  3. correr la suite de pruebas (hoy 923);
  4. probar la app de clientas contra esa copia (login, tarjeta, puntos).
- Rollback ensayado.

### F3 · Usuarios del admin en producción
- Carolina, Mario y Adrián tienen otra cuenta (`auth.users`) en producción. Se ligan **por correo** a sus roles, y a "ver datos de clientas" solo Carolina y Mario.
- Las vendedoras: rol, ubicación y PIN se dan de alta en producción.

### F4 · Ventana de pase (corta, con Carolina avisada)
1. Congelar la captura en el admin actual (aviso a Carolina).
2. Respaldo de producción y del ambiente actual.
3. Aplicar las migraciones a producción, en el orden de F1.
4. Copiar los datos maestros con los mismos identificadores; copiar los archivos de fotos al bucket de producción.
5. **No se copia:**
   - pedidos de prueba;
   - clientas de prueba;
   - inventario de prueba;
   - conteos de prueba;
   - ventas pasadas de prueba (las reales de Carolina sí);
   - cualquier `ZZ`.
6. Verificación: conteos origen = destino y suite de pruebas.
7. Admin de producción: un proyecto Vercel nuevo apuntando a `tgzg…`. Hoy el guard de entorno lo prohíbe a propósito; se cambia en esta fase.

### F5 · Conectar la tienda real
- Funciones Edge en producción (`f360-woo-*`, `f360-store-reserve`, `f360-hilo-intake`…) con sus secretos.
- Webhooks de fuxiaballerinas.com.
- **Homologación:** los IDs legacy de Woo de staging4 son una copia de producción → se verifica 1:1 antes de usarlos. Los modelos publicados por F360 en staging4 **no existen** en la tienda real y se publican de nuevo, con revisión de Carolina.
- **Inventario:** arranca del **conteo real** en producción (modo de un conteo), no de staging.
- La sincronización de stock se enciende al final, con aprobación aparte (decisión D-1).
- **Storefront / promesa de entrega (CRO-6, Mario 2026-10-05).** Todo esto va en el pase, no antes:
  1. Edge Function `f360-storefront` en producción, con sus secretos `F360_STOREFRONT_SERVER_KEY`, `F360_STOREFRONT_TARGET` y `F360_RESERVE_ORIGINS`.
  2. **P0 antes del pase:** Pedido recibido dice "✓ Recibimos tu pago / confirmado" aunque el pedido esté pendiente (`f360-compra.html`, unidad de la sesión 67). Se corrige antes de instalar en la tienda real.
  3. Snippets de PDP, checkout y Pedido recibido (`f360-promesa-avisame.html`, `f360-promesa-checkout.html`), adaptados de mu-plugin de staging4 a producción.
  4. WPCode #2551 de producción: quitar "6 MSI tiempo limitado" y "Entrega INMEDIATA en la mayoría de nuestros modelos" (líneas 41/44/45/46, ver `STOREFRONT_V1_CLOSEOUT.md` §P.4), según la decisión comercial sobre MSI.
  5. **Hilo (HiloLabs):**
     - merge y deploy de la rama `f360-delivery-promise` (tool `get_delivery_promise` + tabla de tallas del KB);
     - variables de Railway `F360_STOREFRONT_URL` y `F360_STOREFRONT_SERVER_KEY`, apuntando a la F360 de **producción** (nunca a staging);
     - en la misma ventana, aplicar el parche KB (d): `scripts/kb_patch_2026_10d.py --apply --backup …`.
     - **Hilo producción no debe depender de F360 staging.**

### F6 · Nuevo ambiente de pruebas
- Proyecto nuevo, copia del esquema de producción con datos maestros y **sin datos personales reales**, conectado a staging4.
- Los guards de scripts se actualizan para que la referencia de producción sea `tgzg…` y la de pruebas el proyecto nuevo.

## Riesgos principales
- **La app publicada comparte tablas** (`customers`, `loyalty_cards`, `offline_sales`…): cada cambio de F360 sobre ellas ya es aditivo y probado, pero F2 lo confirma contra el esquema real de producción.
- **Fotos:** son 575 archivos; se copian y se verifica que cada `storage_path` exista en destino.
- **IDs de usuarios distintos por proyecto:** se ligan por correo, nunca por id.
- **Datos de prueba mezclados en `faltx…`:** la lista de exclusión de F4.5 se revisa con Carolina.

## Siguiente paso
F0 (respaldo diario) y F1 (auditoría de las 65 migraciones) no tocan producción. Con la aprobación de Mario, se ejecutan primero.
