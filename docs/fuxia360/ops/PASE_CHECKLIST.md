# Pase a producción · Lista única (la que manda)

**Dueño del pase:** una sola sesión, fuxiaapp-c4 (Mario, 2026-10-06). Las demás sesiones no tocan nada del pase.

**Decisión base:**
- **Producción** = la base de la app (`tgzg…`), con la tienda fuxiaballerinas.com. La app no se republica.
- **Desarrollo** = el ambiente actual (`faltx…` + `fuxia360-staging.vercel.app` + staging4). Queda intacto y **no se borra**.
- Hay una sola fuente de verdad.

**Detalle por tema:**

| Tema | Documento |
|---|---|
| Plan | `PASE_A_PRODUCCION_OPCION_B.md` |
| Migraciones | `PASE_F1_MIGRATIONS_AUDIT.md` |
| Ensayo | `PASE_F2_ENSAYO.md` |
| Inventario de Carolina | `PRODUCTION_INVENTORY_CUTOVER.md` |
| Tienda | `STAGING4_TO_PRODUCTION_MANIFEST.md`, `CANAL_PRODUCCION_CATALOGO.md` |

Leyenda: ✅ hecho · ⏳ en curso · ⬜ pendiente · 🔒 necesita OK de Mario.

## A. Preparación (no toca producción)

| # | Paso | Estado |
|---|---|---|
| A0 | Respaldo completo de producción antes de tocarla (no hay respaldos automáticos: 0 y sin PITR) | ✅ `~/fuxia360-respaldos/prod-20261006-091255/`: 24 tablas, 735 filas, solo lectura |
| A1 | Respaldo diario de lo de Carolina (F0), con fotos | ✅ Automático cada noche + uno extra hoy (64 modelos, 486 pares, 582 fotos) |
| A2 | Auditoría de las migraciones (F1) | ✅ |
| A3 | Chequeo de producción, solo lectura (P-1 a P-10) | ✅ Todo en verde (Mario, 2026-10-06) |
| A4 | Ensayo completo en copia local (F2): 74 migraciones, datos de Carolina con los mismos ids, fotos, rollback | ✅ |
| A5 | Todas las migraciones guardadas en git (incluidas las de otras sesiones) | ✅ 74 |
| A6 | Comparar la estructura real de producción con la ensayada (P-5) | ✅ **Idéntica**: 294 objetos de `public` (tablas, columnas, funciones, triggers, políticas), 0 diferencias, y todavía sin esquema `f360`. Misma imagen de Postgres (17.6.1.104). Leída con la API de administración de Supabase (sesión de la CLI, consulta de solo lectura), **sin la contraseña de la base** |
| A7 | Probar la app de clientas contra la copia (login, tarjeta, puntos) | ✅ Con lo que hace la app **1.0.2**, usando sus mismos roles (`supabase/staging/pase_app_compat_check.sql`): la venta de vendedora sin sesión, el alta de clienta, la tarjeta (el servidor pone `FX-`, 0 puntos, bronce) y el reclamo de venta con puntos funcionan. Hizo falta el permiso de compatibilidad para anon (ya va en G8). **Bug que YA existe hoy en producción, no causado por el pase:** si la clienta tenía "puntos pendientes", crear su tarjeta falla (el trigger usa el canal `popup`, que la regla de `transactions` no acepta). Producción tiene 37 pendientes sin aplicar. Decisión de Mario, fuera del pase |
| A8 | Inventario de Carolina: cantidades por tienda aprobadas por ella; Bodega CDMX certificada (sin el pedido de prueba #3654 ni el traslado de prueba) | ⬜ Carolina confirma tienda por tienda |
| A9 | Admin sin "staging4" escrito a mano (5 lugares) → variable de entorno | ✅ `975ab00`: `NEXT_PUBLIC_F360_STORE_KEY` (por defecto staging4, sin cambio hoy); el candado rechaza `woo_production` en pruebas. `f360-store-reserve` toma la tienda de la configuración y ya no del navegador (desplegada en staging) |
| A10 | Instalar y probar en staging4 el arreglo P0 "Recibimos tu pago" en pedidos pendientes | ✅ Instalado (WPCode #4105 + mu-plugin; respaldos `~/f360-backups/*_20261006-090003*`). Pendiente → "Registramos tu pedido… en cuanto se confirme tu pago"; pagado → "Recibimos tu pago"; sin llave del pedido no se revela el estado. Evidencia: `docs/fuxia360/cro/screens/p0-pedido-recibido/` |
| A11 | Decidir cuándo se quita el acceso anónimo viejo (A2), según la versión publicada de la app | ✅ **Revisado:** la app publicada es la **1.0.2** (2026-09-24). Trae el escáner `FX-` (las tarjetas nuevas sí se escanean), pero la sección de vendedora es la **vieja**: vende con permisos anónimos y no usa el turno de F360. **A2 NO se aplica en el pase.** Se mantiene el acceso anónimo (ruta de compatibilidad, Q2) y A2 se aplica cuando una versión nueva de la app esté publicada y adoptada |

## B. Ventana del pase (con Carolina avisada)

| # | Paso | Estado |
|---|---|---|
| B1 | Congelar la captura en el admin | 🔒 |
| B2 | Respaldo de producción completo + respaldo F0 de ese momento | 🔒 |
| B3 | Aplicar las 74 migraciones a producción (`--db-url` explícito, dry-run primero) | ✅ **2026-10-06.** Dry-run en producción misma (transacción con ROLLBACK, verificado sin cambios) → **aplicado por Mario** en una sola transacción: 72 migraciones F360 + permiso de compatibilidad anon (Q2) + registro. Verificado: 90 tablas, 13 vistas, 327 funciones, 5 jobs, 74 migraciones; **datos de la app intactos** (41 clientas, 39 tarjetas, 36 ventas, 44 transacciones); lecturas de la app sin sesión → 200. Catálogo F360 vacío hasta B4 |
| B4 | Cargar catálogo, fotos y equipo con los mismos ids (`pase_copy_master.mjs`, `pase_copy_photos.mjs`) | ⏳ **Catálogo y equipo ✅ (2026-10-06 15:52 UTC)**: `supabase/pase/20261006_b4_catalogo_carolina.sql` aplicado con `prod_sql.sh` (dry-run OK). **21/21 tablas iguales** al respaldo de las 15:49 UTC (64 modelos, 948 variantes, 582 fichas de foto, 30 precios, 6 fichas de ajuste, 792 homologaciones, 2 bazares reales). Roles: Carolina (…4188) y Mario (…1363) dueños, únicos que ven datos de clientas. Adrián: sin cuenta en prod todavía. `woo_production` **apagado**. Datos de la app intactos. **Fotos ✅:** 585 archivos en `product-images/f360/` y las **582 rutas del catálogo verificadas**. **Inventario ✅ (B5):** 487 pares (Polanco 164, Bodega 133, San Jerónimo 97, Amsterdam 84, En camino 9); se excluyó la venta de prueba del pedido #4111; saldos = movimientos. Equipo: solo Mario Silva y Carolina como dueñas/os con datos de clientas; la cuenta …1363 sin acceso. Adrián: lectura cuando tenga cuenta |
| B5 | Cargar el inventario aprobado como apertura por ubicación (A8) | 🔒 |
| B6 | Comparar origen = destino, tabla por tabla. Si no cuadra, no se abre | 🔒 |
| B7 | Admin de producción en Vercel (proyecto nuevo) | ⏳ **Desplegado: https://fuxia360.vercel.app** (proyecto `fuxia360`, desde un worktree limpio de `7f7662f`). Variables: `NEXT_PUBLIC_F360_ENV=production`, URL y llave pública de producción, `NEXT_PUBLIC_F360_STORE_KEY=woo_production`; sin secretos ni publicador. El candado de producción pasa y `/login` pide teléfono (código por WhatsApp, la misma cuenta que la app). **Falta:** dar el rol a Carolina, Mario y Adrián por su teléfono (G8) |
| B8 | Hilo: deploy de la rama `f360-delivery-promise` + parche KB (d), apuntando a F360 de producción | 🔒 |
| B9 | ✅ 2026-10-06 Hilo en fuxiaballerinas.com: `f360-store-reserve` + `f360-hilo-intake` en prod (`deploy_prod_function.sh`), mu-plugins `f360-hilo.php` (reemplaza Joinchat, oculta AI Studio de SG) y `f360-compra.php` (link de pago REAL + estado real del pago en Pedido recibido) con `deploy_prod_wp.sh`; Railway `web` (profound-growth) `F360_INTAKE_URL` → intake de prod. Pendiente: filtros de /mx/tienda (Bricks) siguen apuntando a staging — requiere canal activo + stock | ✅ |

## C. Conectar la tienda real (después de B)

| # | Paso | Estado |
|---|---|---|
| C1 | Llave de WooCommerce de producción (usuario solo-catálogo) | 🔒 Mario |
| C2 | Canal `woo_production` encendido para catálogo; publicar los 58 modelos; redirecciones antes de ocultar los viejos; mover reseñas | ⏳ **U1 ✅ en staging** (`20261012000100`, capacidades por canal: staging4 idéntico, producción todo apagado; encender solo dueña + dominio; stock/tienda de producción no se encienden desde ahí; 19 pruebas, suite 1018/1018, rollback ensayado). **U2 ✅ en staging** (`20261012000200` + publicador/sincronización): producción solo con catálogo encendido; con stock apagado el publicador crea variaciones *disponibles* sin control de stock y nunca empuja stock; antes de escribir la tienda confirma su identidad (`/wp-json`); el tick salta stock/pedidos/ocultar según el canal. 45/45 pruebas del publicador, suite 1018/1018, funciones desplegadas en staging con guard OK (cron 200). Siguen U4 (botón), U5 (redirecciones + reseñas), U6 (identidad de producción) |
| C3 | Snippets de la PDP, el checkout y "Pedido recibido" en producción. **"6 MSI" se queda** (es estrategia comercial, Mario 2026-10-06) | 🔒 |
| C4 | Sincronización de stock con la tienda | 🔒 Al final, aprobación aparte |

## D. Fuera de F360 (Adrián)

| # | Paso | Estado |
|---|---|---|
| D1 | El carrusel del home de fuxiaballerinas.com liga a staging4: `wp search-replace 'staging4.fuxiaballerinas.com' 'fuxiaballerinas.com' --all-tables --dry-run`, después sin `--dry-run`, y `wp sg purge` | ⬜ |

## Reglas que no se rompen

1. Nada de Carolina se pierde. Cada copia se compara contra el respaldo de ese momento, y `faltx…` no se borra.
2. Nada de prueba viaja a producción (pedidos de staging4, clientas de prueba, el pedido #3654, el traslado de prueba).
3. Nunca `--linked` (el repo apunta a producción por defecto). Siempre `--db-url` y dry-run.
4. Cada paso 🔒 espera el OK explícito de Mario para ese paso.
