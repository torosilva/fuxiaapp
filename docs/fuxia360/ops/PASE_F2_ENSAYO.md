# Pase a producción · opción B · F2 — Ensayo (2026-10-06)

**Qué es:** el ensayo del pase en una base **desechable y local**: Supabase en Docker, en la carpeta temporal de la sesión, Postgres 17.6 como el ambiente actual.

- Arranca **solo** con el esquema base de producción (`20260924000000` + `…0001`, el baseline de `tgzg…`).
- Sobre ella se aplicaron todas las migraciones de F360 y se cargaron los datos de Carolina con los mismos ids.
- **No se tocó producción ni el ambiente actual** (este solo se leyó).

**Decisión que lo enmarca (Mario, 2026-10-06):**
- La app no se republica y debe haber **una sola base**, así que producción es `tgzg…` (opción B).
- El ambiente actual (`faltx…` + `fuxia360-staging.vercel.app` + staging4) queda como **desarrollo** después del pase. No hace falta otro Supabase.

## Resultado

| Paso del plan | Resultado |
|---|---|
| 1 · Aplicar las migraciones sobre el baseline de prod | ✅ **72/72** en orden (2 baseline + 70 F360), sin errores. Quedan 90 tablas `f360`, 13 vistas, 322 funciones y los 5 jobs de cron `f360-*`. Extensiones: `pg_net`, `pg_cron`, `pgcrypto`, `supabase_vault` |
| 2 · Cargar los datos de Carolina (G9) con los mismos ids | ✅ **38 tablas idénticas** al respaldo F0 del 2026-10-05: 62 modelos, 152 colores, 372 tallas, 912 variantes, 572 fotos (filas), precios, historial, 7 ubicaciones, 792 homologaciones (666 confirmadas), plan de crecimiento. Las 8 tablas que no viajan son las del §6 "nunca copiar" (ligas de staging4) |
| 2b · Inventario de Carolina (opción Q7) | ✅ Cargado: 261 eventos, 498 movimientos, 410 saldos, 2 traslados, conteo de apertura con 672 líneas. **Saldos = suma de movimientos: 0 diferencias** (451 pares). **0** envíos encolados a Woo |
| 2c · Fotos | ✅ 575 archivos subidos al bucket `product-images`; **572 de 572** rutas del catálogo existen en el destino |
| G8 · Personas y canal real | ✅ Carolina, Mario y Adrián ligados **por correo**: `f360_me` funciona con cada cuenta y el admin lista 58 modelos activos. "Ver datos de clientas": **solo Carolina y Mario**. `woo_production` creado **apagado**; `woo_staging4` como histórico apagado (para las 666 homologaciones) |
| 3 · Suite de pruebas | ◐ La suite depende de usuarias y canales de prueba que solo existen en el ambiente actual, donde pasa **999/999**. En el ensayo no aplica tal cual (falta una semilla de fixtures; ver pendientes) |
| 4 · App de clientas contra la copia | ⏳ **Pendiente**: una build de desarrollo de la app apuntando al ensayo (login, tarjeta, puntos) |
| Rollback | ✅ **Esquema:** los 61 `.down.sql` en orden inverso (en transacción) dejan `public` **idéntico** al baseline de prod (294 objetos, 0 diferencias) y quitan `f360`. **Con datos:** los rollbacks se niegan a borrar ("product prices exist"), a propósito. El rollback de una ventana real es el **respaldo de G0** |

## Lo que se construyó (repo)

| Archivo | Qué |
|---|---|
| `scripts/f360/pase_copy_master.mjs` | G8 + G9. Copia el respaldo F0 con los mismos ids en una transacción, remapea usuarios por correo, alinea "En camino", deja el canal real apagado y ajusta las secuencias. `--with-inventory` (Q7), `--dry-run`. **Solo escribe en `127.0.0.1`**; se niega con producción y con el ambiente actual |
| `scripts/f360/pase_copy_photos.mjs` | Fotos del respaldo → bucket del destino, sin sobrescribir, y verifica cada ruta. **Solo local** |

## Hallazgos

1. **"En camino"** (ubicación de tránsito): las migraciones la crean con otro id. El script la alinea al id de Carolina antes de copiar (plan §5.8). ✅ Resuelto.
2. **Columnas `id` GENERATED ALWAYS** en las tablas de historial: se copian con `OVERRIDING SYSTEM VALUE` y luego se mueven las secuencias. ✅ Resuelto.
3. **Migraciones de otras sesiones sin commitear:**
   - `20261010001100_f360_location_edit_deactivate` ya está aplicada en el ambiente actual (funciones `f360_update_location` / `f360_deactivate_location`);
   - `20261010000900_f360_opening_undo` sigue pendiente.

   **Deben commitearse antes del pase**, o producción quedaría sin funciones que el admin ya usa.
4. **Rollbacks:** casi ningún `.down.sql` borra su fila de `schema_migrations`. Si se usaran, después hay que limpiar el registro (`supabase migration repair`). No afecta al pase: su rollback es el respaldo.
5. **A2** (quitar el acceso anónimo) está aplicado en el ambiente actual pero no en producción ni en el ensayo. Se aplica por su runbook (decisión Q2).
6. **El respaldo de anoche ya quedó atrás:** hoy el ambiente actual tiene 64 modelos y 486 pares, contra 62 y 451 en el respaldo, porque Carolina sigue trabajando. **En el pase se usa un respaldo tomado al congelar la captura (F4.1).** No se pierde nada.
7. **Fuera de F360, en fuxiaballerinas.com:** el carrusel del home liga a `staging4.fuxiaballerinas.com`. Se corrige con un `wp search-replace` (Adrián, con `--dry-run` primero).

## Lo que falta para el pase real (en orden)

1. **Pre-checks de producción (P-1 a P-10).** Mario pega `docs/fuxia360/ops/PASE_F1_PRECHECK_PROD.sql` en el SQL Editor de producción. Es solo lectura, devuelve conteos y termina en ROLLBACK. Con eso se sabe si hay clientas duplicadas, teléfonos sin formato o existencias imposibles que harían abortar dos migraciones.
2. **Esquema real de producción (P-5)**, para confirmar que no difiere del baseline:
   - `supabase db dump --schema public` con la URL de producción (solo esquema, sin datos);
   - o Mario lo exporta desde el dashboard.
3. **Commitear las 2 migraciones de las otras sesiones** (hallazgo 3).
4. **Ensayo de la app (paso 4):** build de desarrollo apuntando a esta copia.
5. **Decisiones** (preguntas abiertas de F1, con la recomendación del ensayo):

| # | Decisión | Recomendación |
|---|---|---|
| Q1 | Formato del QR de tarjetas nuevas | Ya resuelto con `FX-` (migración `20261010000600`); confirmar |
| Q2 | A2 antes de G4 o GRANT de compatibilidad | Depende de la versión publicada de la app (Q8) |
| Q3 | `woo_production` activo o apagado en F4 | **Apagado** hasta F5 (así quedó el ensayo) |
| Q4 | Las 666 homologaciones | **Llevarlas** con `woo_staging4` como histórico (probado: entra sin romper FKs) y re-anclar en F5 tras la verificación 1:1 |
| Q5 | Roles | Carolina, Mario y Adrián como dueños (igual que hoy) |
| Q6 | Tiendas ligadas a canales de la app | Sin liga al inicio (así quedó el ensayo); se liga tienda por tienda en su corte |
| Q7 | ¿El inventario de Carolina viaja? | **Sí, si es real** (probado: entra cuadrado). Si es de prueba, se omite con no poner `--with-inventory` |

6. **Ventana F4** con Carolina avisada: congelar la captura → respaldo G0 → migraciones → script de copia → fotos → admin de producción en Vercel.

## Cómo repetir el ensayo

```
# base local con solo el baseline de prod + migraciones commiteadas (carpeta temporal)
supabase start                                # en la carpeta del ensayo (project_id f360-pase-ensayo)
PASE_TARGET_DB_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres \
  node scripts/f360/pase_copy_master.mjs --backup ~/fuxia360-respaldos/<día> --auth <staging_auth.json> --with-inventory
PASE_TARGET_API_URL=http://127.0.0.1:54321 PASE_TARGET_SERVICE_KEY=<local> PASE_TARGET_DB_URL=… node scripts/f360/pase_copy_photos.mjs
```

`staging_auth.json` lleva solo los ids de usuarios del ambiente actual y el correo de las 3 personas del equipo. **No se commitea.**
