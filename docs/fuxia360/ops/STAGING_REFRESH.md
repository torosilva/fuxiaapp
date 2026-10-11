# Staging = producción (copia nocturna anonimizada)

**Decisión de Mario, 2026-10-11:** staging (`faltx…`) debe ser siempre una copia de producción (`tgzg…`), renovada cada noche, con los datos de las clientas anonimizados. Cada copia reemplaza staging por completo.

Esto reemplaza la regla anterior de "nunca resembrar `faltx…`". Los datos que Carolina capturó en staging ya están en producción desde el pase del 8 de octubre.

## Cómo funciona

`scripts/f360/staging_refresh/refresh.sh --apply` corre todos los días a las 3:30 en la Mac de Mario. Lo lanza `launchd` (`com.fuxia.staging-refresh.plist`); si la Mac está dormida, corre al despertar.

1. **Respaldo de staging.** Guarda los esquemas de la app y los usuarios en `~/fuxia360-respaldos/staging-refresh/<fecha>/`. Se conservan 7 días.
2. **Lee producción.** `pg_dump` siempre lee en una transacción de solo lectura. Lee el esquema de `public`, `f360` y `f360_board`; los datos; `auth.users`, `auth.identities` y la historia de migraciones; y las políticas de `storage`.
   Hay datos que **nunca salen de producción**: `push_tokens`, `otp_verifications`, `seller_sessions`, `reserve_codes` y las bandejas de salida de WhatsApp, correo y push.
3. **Reemplaza staging en UNA transacción** (`pre_restore.sql` → esquema y datos de prod → `post_restore.sql`):
   - **Anonimiza a las clientas.** Los teléfonos pasan a `+1 555 019 NNNN`, de forma consistente en todas las tablas, para que las uniones por teléfono sigan funcionando. Los correos pasan a `clienta N@staging.invalid`; los de inicio de sesión por teléfono, a `<teléfono ficticio>@fuxia.app`. Los nombres pasan a "Clienta N". La dirección se vuelve de prueba. El cumpleaños conserva día y mes, con año 2000. Se borran la foto, las transcripciones y las notas libres.
   - **Las internas se conservan tal cual**, para poder entrar a staging con su usuario de prod: el equipo con rol en el admin, las vendedoras, la junta y los clientes con rol `staff` o `admin`.
   - **Staging conserva su configuración:** los destinos de venta (staging4), `notification_recipients`, los usuarios demo `@staging.invalid` y sus roles. Los destinos de prod (tienda real) quedan **apagados** y con URL `.staging.invalid`.
   - **No se tocan:** `vault` (URLs y secretos de staging), `cron` (tareas de staging), los archivos de `storage`, `realtime` y `net`.
   - **Se reescriben las URLs** del proyecto de prod que estén guardadas en los datos, para que apunten al proyecto de staging.
   - **Verificación final.** Si queda cualquier teléfono, correo o nombre completo de una clienta de prod, o cualquier correo que no sea ficticio, interno o de la empresa, la transacción se deshace y staging queda como estaba.
   - El esquema (~7,000 sentencias) se envía en modo *pipeline* de psql 18. La transacción completa dura ~1.5 min (ensayo del 2026-10-11); sin pipeline eran ~12 min con staging bloqueado.
4. **Migraciones.** Reaplica las migraciones de `origin/fuxia-360` que prod todavía no tiene (`supabase db push --include-all`, desde un worktree limpio, de modo que las migraciones locales sin publicar nunca entran). Así staging ensaya cada noche lo que irá a producción.
   Luego corre, en orden, los SQL de `scripts/f360/staging_refresh/after_refresh.list` (datos propios de staging que no vienen de prod, p. ej. los de Inteligencia). Cada uno trae su BEGIN/COMMIT; si uno falla se reporta y la copia sigue.
5. **Fotos.** Copia de `product-images` lo que falte o haya cambiado. No borra nada. Las fotos de clientas (`avatars`, `tryon-temp`) no se copian.
6. Manda un aviso de macOS con el resultado. El registro queda en `<fecha>/refresh.log`.

## Pendiente: WooCommerce (staging4)

Decisión de Mario (2026-10-11): staging4 también se copia de producción cada noche, con limpieza (Mercado Pago en modo prueba, sin correos, webhooks y endpoints a staging, clientas anonimizadas, sin medición, `noindex`). Inventario de solo lectura: `scripts/f360/wp_inventory.sh` (requiere acceso SSH a producción aprobado por Mario).

## Coordinación con otras sesiones

Un ensayo bloquea staging ~1.5 min. Avisa a las sesiones que trabajen en staging antes de correrlo. Las migraciones que no estén en `origin/fuxia-360` se pierden en cada copia.

## Uso manual

```
scripts/f360/staging_refresh/refresh.sh --rehearsal   # ensayo completo, termina en ROLLBACK: staging no cambia
scripts/f360/staging_refresh/refresh.sh --apply       # copia real
```

Requiere `brew install libpq` (pg_dump/psql 17+), `node`, la CLI de Supabase con sesión iniciada, y los archivos `~/.fuxia-prod.env` y `~/.fuxia-staging.env`.

## Por qué en la Mac y no en GitHub Actions

El repositorio es **público**. Los registros de Actions se ven públicamente, y la copia necesita la URL de la base de producción y guarda respaldos con datos personales. En la Mac, las credenciales y los respaldos no salen de donde ya están.

## Consecuencias aceptadas

- Los datos de prueba que existan solo en staging se pierden en cada copia (queda el respaldo de 7 días).
- Los IDs de producto de la tienda staging4 dejan de coincidir con el catálogo, que ahora es el de prod.
- Si una migración pendiente falla, staging queda con el esquema de prod y el aviso dice "migraciones fallaron".

## Seguridad

- Las barreras abortan si las URLs no son exactamente las de prod y staging (por ref), o si la de staging menciona prod. Los archivos SQL de staging verifican `fuxia.target_ref`.
- Prod solo se lee.
- Las contraseñas de las bases van en un `.pgpass` temporal (modo 600, se borra al terminar), nunca en argumentos de procesos (`ps`).
- No se imprimen credenciales ni datos. El registro solo tiene conteos.
- Los respaldos tienen modo 600 (umask 077), en `~/fuxia360-respaldos/`.

## Reversión

- **Una copia:** `pg_restore --clean` de `staging_before_app.dump` y `staging_before_auth.dump` de la fecha anterior.
- **Apagar la copia nocturna:** `launchctl bootout gui/$(id -u)/com.fuxia.staging-refresh`.

## Verificación

- Ensayo `--rehearsal` sin errores y con "Verificación OK".
- Después de `--apply`: los conteos de pedidos, inventario y productos de staging son iguales a los de prod; ningún destino de venta de prod está activo; los usuarios demo entran; Mario y Carolina entran con su usuario de prod.
