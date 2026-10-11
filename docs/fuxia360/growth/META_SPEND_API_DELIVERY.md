# Gasto de Meta Ads por API — entrega en PRODUCCIÓN (2026-10-11)

**Decisión:** Mario, 2026-10-10/11 ("en producción", "tomemos todo el historial", "si dale").
**Estado:** en vivo. El historial cargado va del 2026-05-01 al 2026-10-10. Hay una lectura diaria a las 02:30 CDMX y la fuente `meta_ads` está en **HEALTHY**.

## 1. Qué hace
- **Origen:** Meta Marketing API, en **solo lectura**. Usa el token del usuario del sistema `fuxia360-lectura` (portafolio *Fuxia Ballerinas*), con permiso "Ver rendimiento" sobre la cuenta **CP - Fuxia Ballerinas** (`act_966161362834783`, MXN, America/Mexico_City). La app de Meta es **FUXIA 360** (1110931044753045).
- **Grano:** campaña × día × mercado. El **mercado** sale del **país que Meta reporta para las impresiones**: MX → MX, CO → CO, cualquier otro → ROW. Así una misma campaña que pauta en los dos países se reparte bien, sin depender de su nombre.
- **Destino:** las mismas tablas que la importación CSV (`f360.marketing_spend_imports` / `_rows`), con `source = 'api'`. El panel lee `f360.marketing_spend_daily`, que toma la importación más reciente de cada día.
- **Días sin gasto:** reciben una fila explícita en 0 (campaña `sin_gasto`), porque Meta confirmó que no hubo gasto. Un día sin ninguna fila sigue significando "desconocido", nunca 0.
- **Lectura diaria:** el cron `f360-meta-spend` (`30 8 * * *` UTC) vuelve a leer los **últimos 7 días completos**, porque Meta corrige los días recientes, y la importación más nueva reemplaza esos días.
- **Fallos:** si Meta rechaza la lectura (token revocado, caída), queda un registro en `f360.measurement_runs` con `ok = false` y la fuente pasa a **ERROR** en el semáforo. Si pasan 36 h sin una lectura correcta, pasa a **STALE**.

## 2. Archivos
| Archivo | Qué |
|---|---|
| `supabase/migrations/20261023000100_f360_meta_spend_api.sql` | `public.f360_marketing_spend_api_import` y `public.f360_measurement_run_failed` (solo `service_role`), `f360.meta_spend_tick()` y el cron |
| `supabase/rollbacks/20261023000100_f360_meta_spend_api.down.sql` | quita el cron y las funciones, y regresa `meta_ads` a NOT_CONFIGURED (el gasto ya cargado se queda; se anula con `f360_marketing_spend_void`) |
| `fuxia-native/supabase/functions/f360-meta-spend/` | `meta.ts` (transformación pura y GET paginado), `handler.ts` (autenticación, ventanas, RPC), `index.ts`, `meta.test.ts` |
| `scripts/f360/deploy_prod_function.sh` | agrega `f360-meta-spend`; el token se toma de `~/.fuxia-meta-ads.token` (chmod 600, nunca se imprime) |
| `supabase/pase/20261011_meta_gasto_api.sql` | la migración y su fila en `schema_migrations`, con chequeos posteriores |
| `supabase/pase/20261011_meta_gasto_api_historial.sql` | encola una sola llamada de carga histórica, vía pg_net y el vault |
| `supabase/pase/20261011_meta_gasto_api_activar.sql` | marca `meta_ads` como CONFIGURED solo si el historial está cargado y la última lectura salió bien |
| `supabase/staging/test_meta_spend_api.sql` | ensayo M1–M7 (solo `--dry-run`) |

## 3. Seguridad
- **Token:** solo existe como secreto `META_ADS_TOKEN` en Supabase producción y en `~/.fuxia-meta-ads.token`. Nunca se registra, y los mensajes de error de Meta no lo incluyen (lo comprueba una prueba).
- **Quién puede ejecutar la función:** `F360_SYNC_SECRET` (el cron) o un **owner**. Sin credencial responde 401 (verificado al desplegar).
- **Quién puede escribir:** la importación por API solo la ejecuta `service_role`. `anon` y `authenticated` no tienen EXECUTE (lo revisa el pase). La validación de filas es la misma del CSV y es del servidor: cuenta y moneda únicas, fechas dentro de la ventana y no futuras, montos ≥ 0 con 2 decimales.
- **Datos personales:** ninguno. Solo agregados por campaña.
- **⚠ Pendiente:** el token actual tiene más permisos de los necesarios (`ads_management` y `business_management`, además de `ads_read`), y se compartió por chat. En la práctica solo puede *ver* la cuenta publicitaria, porque el permiso del activo es "Ver rendimiento". Aun así hay que regenerarlo **solo con `ads_read`**, guardarlo en `~/.fuxia-meta-ads.token` y volver a correr `scripts/f360/deploy_prod_function.sh f360-meta-spend`. Después se revoca el anterior en Business → Usuarios del sistema → fuxia360-lectura.

## 4. Verificación
- **Unitarias:** `node --test fuxia-native/supabase/functions/f360-meta-spend/meta.test.ts` → **7/0**. Cubren el mercado por país, la suma en centavos, las ventanas, la fecha CDMX, la autenticación (401/405/400), la lectura diaria (7 días y moneda de la cuenta) y el error de Meta (se registra, responde 502 y no expone el token).
- **Contra el Meta real, con la base simulada:** 6 ventanas, 526 filas, **$76,933.84 MXN**.
- **Ensayo en producción** (`prod_sql.sh --dry-run test_meta_spend_api.sql`): **OK**. Cubre M1 (aceptado, MX y CO el mismo día, 2 días en 0), M2 (duplicado), M3 (Meta corrige un día y gana el más nuevo, sin tocar los demás), M4 (otra moneda rechazada), M5 (repetido rechazado), M6 (fuera de ventana o ventana futura rechazados) y M7 (fallo registrado). Al ensayo anterior a este lo detuvo una variable ambigua; se corrigió antes de aplicar.
- **Producción, después de la carga:** 6 importaciones aceptadas, 0 lecturas fallidas, **163 días**, total **$76,933.84** = Meta. Por mes: may 9,999.07 · jun 8,879.60 · jul 17,449.24 · ago 20,888.57 · sep 17,473.19 · oct (1–10) 2,244.17. Por mercado: **MX 46,363.99 · CO 30,569.73 · ROW 0.12**.
- **Semáforo:** `meta_ads` = HEALTHY. `marketing_spend` = DEGRADED **solo** por `platforms_with_unknown_spend:google`; sigue abierta la pregunta de si hay gasto en Google Ads.

## 5. Criterios de aceptación
- [x] El gasto de Meta desde la creación de la cuenta (2026-05-01) está en producción y coincide con Ads Manager.
- [x] Cada fila tiene mercado MX/CO según el país de Meta, y nada queda en UNKNOWN salvo los días en 0.
- [x] La lectura diaria corre sola y deja rastro, con ERROR o STALE si falla.
- [x] Sin datos personales; el token no queda en el repo ni en los registros.
- [ ] Token regenerado solo con `ads_read` (Mario/Adrián).

## 6. Contradicciones y decisiones abiertas
1. **Moneda de Colombia:** el gasto de Colombia se paga en **MXN** (la cuenta es MXN) y la venta de Colombia es en **COP**. El ROAS de Colombia necesita una tasa COP/MXN aprobada (`f360.fx_rates`, todavía vacía). Hasta entonces el panel lo marca como dato incompleto.
2. **Ventas en producción:** Commerce Facts tiene **1 pedido**, porque el historial Woo (P0D, 84 pedidos) sigue pendiente. Sin eso no hay ROAS real en el panel de producción. El cruce manual del 2026-10-10 está en la conversación con Mario: ROAS 2.3 en total, julio–agosto 4–6×, septiembre 0.6–0.7×.
3. **Google Ads:** ¿hay gasto? Hoy figura como desconocido, nunca $0.
