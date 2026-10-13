# Staging = producción (copia nocturna anonimizada)

**Decisión de Mario, 2026-10-11:** staging (`faltx…`) debe ser siempre una copia de producción (`tgzg…`), renovada cada noche, con los datos de las clientas anonimizados. Cada copia reemplaza staging por completo.

Esto reemplaza la regla anterior de "nunca resembrar `faltx…`". Los datos que Carolina capturó en staging ya están en producción desde el pase del 8 de octubre.

## Cómo funciona

`scripts/f360/staging_refresh/nightly.sh` corre todos los días a las 3:30 en la Mac de Mario. Lo lanza `launchd` (`com.fuxia.staging-refresh.plist`); si la Mac está dormida, corre al despertar.

macOS no deja que `launchd` lea `~/Documents` ("Operation not permitted"; así fallaron en silencio las noches del 12 y 13 de octubre). Por eso `launchd` corre `~/.fuxia360/staging-nightly.sh` (copia de `launcher.sh`). Ese arranque pone un clon propio, `~/.fuxia360/staging-refresh-repo`, en `origin/fuxia-360` y corre desde ahí `nightly.sh`. Así la copia nocturna siempre usa el código publicado, nunca cambios locales sin subir. El registro queda en `~/fuxia360-respaldos/staging-refresh/launchd.log`.

Primero copia la tienda real a staging4 (`woo_refresh.sh --apply`, sección WooCommerce). Si salió bien, copia Supabase con `refresh.sh --apply --woo-mirrored`: el destino de venta de prod se vuelve el de staging4, porque staging4 ya tiene los mismos IDs de producto que la tienda real. Si la tienda falló (y se restauró sola), Supabase se copia igual, sin esa conexión.

Pasos de la copia de Supabase (`refresh.sh`):

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
   - **Permisos exactos de prod.** Cada tabla, vista, secuencia y función recibe exactamente los permisos que tiene en prod para PUBLIC, `anon`, `authenticated` y `service_role` (revoke + grant). Sin esto, los permisos por defecto de staging se sumaban; por ejemplo, `offline_sale_items` quedaba abierta a `anon`.
   - El esquema (~7,000 sentencias) se envía en modo *pipeline* de psql 18. La transacción completa dura ~1.5 min (ensayo del 2026-10-11); sin pipeline eran ~12 min con staging bloqueado.
4. **Migraciones.** Reaplica las migraciones de `origin/fuxia-360` que prod todavía no tiene (`supabase db push --include-all`, desde un worktree limpio, de modo que las migraciones locales sin publicar nunca entran). Así staging ensaya cada noche lo que irá a producción.
   Luego corre, en orden, los SQL de `scripts/f360/staging_refresh/after_refresh.list` (datos propios de staging que no vienen de prod, p. ej. los de Inteligencia). Cada uno trae su BEGIN/COMMIT; si uno falla se reporta y la copia sigue.
5. **Fotos.** Copia de `product-images` lo que falte o haya cambiado. No borra nada. Las fotos de clientas (`avatars`, `tryon-temp`) no se copian.
6. Manda un aviso de macOS con el resultado. El registro queda en `<fecha>/refresh.log`.

## Historial

- **2026-10-11 09:10:** primera copia real. Resultado: 70 clientas anonimizadas, 5 migraciones del repo reaplicadas, 83 fotos copiadas, conteos iguales a prod. Falló el seed `intel_goal_300k.sql` (lo corrige la sesión de Inteligencia). Tarea nocturna instalada (`launchctl print gui/$(id -u)/com.fuxia.staging-refresh`).

## WooCommerce (staging4)

Decisión de Mario (2026-10-11): staging4 también se copia de producción cada noche. Lo hace `scripts/f360/staging_refresh/woo_refresh.sh --apply` por SSH en SiteGround, donde viven los dos sitios:

1. **Respaldo de staging4:** la base completa, sus webhooks y claves API de Woo, sus opciones propias (Mercado Pago de prueba, GTM, `noindex`) y sus mu-plugins. Queda en `~/f360-backups/staging4-refresh/<fecha>/` en el servidor, 7 días.
2. **Guardia primero** (`f360-guardia-staging4.php`): desde ese momento ningún correo sale y ninguna llamada HTTP llega a Supabase de prod, a la tienda real, a Meta ni a Google Merchant. Staging4 entra en modo mantenimiento.
3. **Copia:** la base de la tienda real (leída en una transacción) y los temas, plugins y fotos.
4. **Direcciones:** la tienda real pasa a staging4 y Supabase de prod pasa a staging (URL y claves públicas). La URL de Hilo se reemplaza por `hilo.staging.invalid`, porque Hilo solo existe en prod.
5. **Lo propio de staging4 vuelve:** sus opciones, sus webhooks (todos apuntan a Supabase de staging) y sus claves API.
   - Se apagan PayPal (los dos plugins), ePayco, Google Listings & Ads, Facebook for WooCommerce, Cart Abandonment y Clarity.
   - Solo queda Mercado Pago, en modo prueba.
6. **Anonimiza** (`woo_anonymize.sql`):
   - Usuarias, pedidos, direcciones, índice de clientas, reseñas y notas de pedido.
   - Los valores serializados que tengan un correo se borran.
   - Se vacían leads, avisos de stock, carritos abandonados, sesiones, tokens de pago, registros y tareas pendientes.
   - **Verificación:** si queda un correo real, dice en qué tabla y qué campos (nunca valores), restaura y falla.
7. **mu-plugins:** se instalan los espejos de prod de `tools/storefront/mu-plugins/staging4-espejo/`, generados con `node scripts/f360/build_staging4_mirror_mu.mjs`, más la guardia. `f360-hilo.php` no se espeja.
8. **Prueba:** que `home` sea staging4, que ningún webhook apunte a prod (lista cada webhook con su estado y destino) y que `/mx/` responda http 200.

Ante cualquier fallo después del respaldo, staging4 se restaura solo y el error dice la línea donde falló. `RESTORE_FROM=<fecha>` restaura desde el respaldo de otra corrida, por ejemplo si la anterior dejó staging4 a medias.

```
scripts/f360/staging_refresh/woo_refresh.sh --rehearsal   # solo revisa: nada cambia
scripts/f360/staging_refresh/woo_refresh.sh --apply
```

Necesita la llave SSH de SiteGround cargada en el agente (`ssh-add -l`). Sin ella, la tienda falla y Supabase se copia igual, sin `--woo-mirrored`.

- **Primera copia exitosa:** 2026-10-11 12:43 (corrida 124304).
- **Mientras staging4 tiene los IDs de prod pero Supabase de staging aún no (antes de la primera copia con `--woo-mirrored`):** las tallas aparecen sin disponibilidad. Las consultas de existencias van a Supabase de staging, que todavía conoce los IDs viejos de staging4.

## Coordinación con otras sesiones

Un ensayo bloquea staging ~1.5 min. Avisa a las sesiones que trabajen en staging antes de correrlo. Las migraciones que no estén en `origin/fuxia-360` se pierden en cada copia.

## Uso manual

```
scripts/f360/staging_refresh/refresh.sh --rehearsal   # ensayo completo, termina en ROLLBACK: staging no cambia
scripts/f360/staging_refresh/refresh.sh --apply       # copia real
scripts/f360/staging_refresh/nightly.sh               # lo mismo que la noche: tienda + Supabase
```

Requiere `brew install libpq` (pg_dump/psql 17+), `node`, la CLI de Supabase con sesión iniciada, y los archivos `~/.fuxia-prod.env` y `~/.fuxia-staging.env`.

## Por qué en la Mac y no en GitHub Actions

El repositorio es **público**. Los registros de Actions se ven públicamente, y la copia necesita la URL de la base de producción y guarda respaldos con datos personales. En la Mac, las credenciales y los respaldos no salen de donde ya están.

## Consecuencias aceptadas

- Los datos de prueba que existan solo en staging se pierden en cada copia (queda el respaldo de 7 días).
- Los datos de prueba de staging4 (pedidos, clientas, productos creados solo ahí) se pierden en cada copia.
- Si una migración pendiente falla, staging queda con el esquema de prod y el aviso dice "migraciones fallaron".

## Seguridad

- Las barreras abortan si las URLs no son exactamente las de prod y staging (por ref), o si la de staging menciona prod. Los archivos SQL de staging verifican `fuxia.target_ref`.
- Prod solo se lee.
- Las contraseñas de las bases van en un `.pgpass` temporal (modo 600, se borra al terminar), nunca en argumentos de procesos (`ps`).
- No se imprimen credenciales ni datos. El registro solo tiene conteos.
- Los respaldos tienen modo 600 (umask 077), en `~/fuxia360-respaldos/`.

## Reversión

- **Una copia:** `pg_restore --clean` de `staging_before_app.dump` y `staging_before_auth.dump` de la fecha anterior.
- **staging4:** `RESTORE_FROM=<fecha> woo_refresh.sh --apply` o, a mano en el servidor, `gunzip -c ~/f360-backups/staging4-refresh/<fecha>/staging4_before.sql.gz | wp db import -`.
- **Apagar la copia nocturna:** `launchctl bootout gui/$(id -u)/com.fuxia.staging-refresh`.

## Verificación

- Ensayo `--rehearsal` sin errores y con "Verificación OK".
- Después de `--apply`: los conteos de pedidos, inventario y productos de staging son iguales a los de prod; ningún destino de venta de prod está activo; los usuarios demo entran; Mario y Carolina entran con su usuario de prod.
