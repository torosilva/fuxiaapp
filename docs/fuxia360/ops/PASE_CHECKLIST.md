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
| A1 | Respaldo diario de lo de Carolina (F0), con fotos | ✅ Automático cada noche + uno extra hoy (64 modelos, 486 pares, 582 fotos) |
| A2 | Auditoría de las migraciones (F1) | ✅ |
| A3 | Chequeo de producción, solo lectura (P-1 a P-10) | ✅ Todo en verde (Mario, 2026-10-06) |
| A4 | Ensayo completo en copia local (F2): 74 migraciones, datos de Carolina con los mismos ids, fotos, rollback | ✅ |
| A5 | Todas las migraciones guardadas en git (incluidas las de otras sesiones) | ✅ 74 |
| A6 | Comparar la estructura real de producción con la ensayada (P-5) | ⏳ Falta la contraseña correcta en `~/.fuxia-prod.env` |
| A7 | Probar la app de clientas contra la copia (login, tarjeta, puntos) | ⬜ |
| A8 | Inventario de Carolina: cantidades por tienda aprobadas por ella; Bodega CDMX certificada (sin el pedido de prueba #3654 ni el traslado de prueba) | ⬜ Carolina confirma tienda por tienda |
| A9 | Admin sin "staging4" escrito a mano (5 lugares) → variable de entorno | ⬜ |
| A10 | Instalar y probar en staging4 el arreglo P0 "Recibimos tu pago" en pedidos pendientes | ⬜ Código listo (`40204ca`) |
| A11 | Decidir cuándo se quita el acceso anónimo viejo (A2), según la versión publicada de la app | 🔒 |

## B. Ventana del pase (con Carolina avisada)

| # | Paso | Estado |
|---|---|---|
| B1 | Congelar la captura en el admin | 🔒 |
| B2 | Respaldo de producción completo + respaldo F0 de ese momento | 🔒 |
| B3 | Aplicar las 74 migraciones a producción (`--db-url` explícito, dry-run primero) | 🔒 |
| B4 | Cargar catálogo, fotos y equipo con los mismos ids (`pase_copy_master.mjs`, `pase_copy_photos.mjs`) | 🔒 |
| B5 | Cargar el inventario aprobado como apertura por ubicación (A8) | 🔒 |
| B6 | Comparar origen = destino, tabla por tabla. Si no cuadra, no se abre | 🔒 |
| B7 | Admin de producción en Vercel (proyecto nuevo) | 🔒 |
| B8 | Hilo: deploy de la rama `f360-delivery-promise` + parche KB (d), apuntando a F360 de producción | 🔒 |

## C. Conectar la tienda real (después de B)

| # | Paso | Estado |
|---|---|---|
| C1 | Llave de WooCommerce de producción (usuario solo-catálogo) | 🔒 Mario |
| C2 | Canal `woo_production` encendido para catálogo; publicar los 58 modelos; redirecciones antes de ocultar los viejos; mover reseñas | ⬜ Diseño hecho, nada construido |
| C3 | Snippets de la PDP, el checkout y "Pedido recibido" en producción; quitar "6 MSI tiempo limitado" | 🔒 |
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
