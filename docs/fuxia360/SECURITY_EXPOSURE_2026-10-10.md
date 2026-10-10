# Exposición de secretos en una sesión de Claude Code — 2026-10-10

> Este documento **no contiene ningún valor secreto**. Las verificaciones se hicieron comparando huellas (sha256) o contando coincidencias, sin imprimir valores.
> **No se rotó nada.** Las credenciales productivas se rotan solo con coordinación y autorización expresa de Mario.

## 1. Qué pasó
Al buscar las credenciales de WooCommerce de staging4, Claude listó los archivos `~/.fuxia-*`. El comando intentaba ocultar los valores con `sed 's/=.*/=…/'`, pero ese filtro solo actúa en líneas con `=`. Cinco archivos guardan el valor solo, sin `NOMBRE=`, y se imprimieron completos en la salida de la sesión.

## 2. Inventario de secretos afectados
| # | Archivo local | Qué es | Dónde se usa (verificado por huella) | Estado hoy | Riesgo |
|---|---|---|---|---|---|
| 1 | `~/.fuxia-sb-token` | Token personal de acceso de Supabase (cuenta) | Supabase CLI / API de administración | **Ya inválido**: la API respondió 401 (solo se pidió el código de estado) | Bajo, pero revocarlo en el panel igualmente |
| 2 | `~/.fuxia-db-url` | URL de Postgres de **producción** con usuario `postgres` y contraseña | Scripts locales antiguos | La contraseña **no coincide** con la de `~/.fuxia-prod.env` (la vigente en los scripts). Probablemente obsoleta, pero **no se probó la conexión** para no conectarse a producción con una credencial expuesta. También aparece en una sesión anterior (14 ago 2026). | Alto si sigue vigente: acceso total a la base de producción |
| 3 | `~/.fuxia-sync.secret` | `F360_SYNC_SECRET` de **producción** | Función `f360-woo-sync` + secreto de Vault `f360_sync_secret`, que usa el cron cada 15 min | Vigente | Medio: permite pedir a la función que reconcilie o haga push (no expone datos de clientas) |
| 4 | `~/.fuxia-woo-orders.secret` | `WOO_WEBHOOK_SECRET` de **producción** | Función `f360-woo-orders` + firma de los webhooks "Fuxia 360 · pedidos" en fuxiaballerinas.com | Vigente | Medio: permite enviar pedidos falsos firmados a Fuxia 360 |
| 5 | `~/.fuxia-hilo-intake.secret` | `F360_HILO_SECRET` de **producción** | Función `f360-hilo-intake`; HiloLabs lo guarda como `F360_INTAKE_SECRET` | Vigente | Medio: permite meter escalamientos falsos en la bandeja de clientas |

**No se expusieron:** `~/.fuxia-prod.env`, `~/.fuxia-staging.env` y `~/.fuxia-woo-prod.env`. En esos tres el filtro sí ocultó los valores.

## 3. Dónde quedó cada valor (verificación)
| Lugar | Resultado |
|---|---|
| Git: historial completo de todas las ramas, todos los árboles y archivos de trabajo | **0 coincidencias** para los 5 valores (y para la contraseña de la #2 sola) |
| Scratchpad de la sesión, capturas, `test-results` | 0 |
| Historial de zsh/bash, snapshots del shell de Claude | 0 |
| Transcripción local de **esta** sesión (`~/.claude/projects/…/373ab37e-….jsonl`) | Contiene los 5 |
| Transcripción local de la sesión `c72b5584-….jsonl` (14 ago 2026) | Contiene la #2 (exposición anterior) |
| Servicio del modelo | La salida de la herramienta se envió como parte de la conversación: tratar los 5 como **expuestos fuera de la Mac** |
| Logs de Supabase / Vercel | No aplican: nada se envió a esos servicios con los valores |

## 4. Pasos de rotación segura (para coordinar, NO ejecutados)
Orden sugerido: 1 → 2 → 3 → 5 → 4. Conviene hacerlo en una ventana tranquila, porque las rotaciones 3 y 4 cortan integraciones si se hacen a medias.

1. **Token de Supabase (inválido):** supabase.com → Account → Access Tokens → revocar cualquier token que no reconozcas. Si se necesita uno nuevo: crearlo, `supabase login` y guardarlo en `~/.fuxia-sb-token` (`chmod 600`). Sin impacto en la operación.
2. **Contraseña de Postgres de producción:**
   - Revisar si la de `~/.fuxia-db-url` todavía sirve (Mario, en su terminal; no imprime nada): `! /opt/homebrew/opt/libpq/bin/psql "$(cat ~/.fuxia-db-url)" -Atc "select 1" >/dev/null 2>&1 && echo VIGENTE || echo NO-SIRVE`.
   - Si está vigente: Dashboard → Project Settings → Database → Reset database password. Actualizar `~/.fuxia-prod.env` (`PROD_DB_URL`) y borrar `~/.fuxia-db-url`.
   - Las Edge Functions usan su propia conexión y no se afectan.
   - Si no sirve: solo borrar `~/.fuxia-db-url`.
3. **`F360_SYNC_SECRET` (cron de pedidos y stock):**
   - Generar uno nuevo (`openssl rand -hex 32 > ~/.fuxia-sync.secret.new`).
   - En la misma ventana: `supabase secrets set --project-ref tgzg… F360_SYNC_SECRET=…` y actualizar el secreto de Vault `f360_sync_secret` (`select vault.update_secret(id, '<nuevo>') from vault.secrets where name = 'f360_sync_secret'`, vía `prod_sql.sh`).
   - Verificar el siguiente tick del cron (respuesta 200) y sustituir el archivo local.
   - Riesgo: si solo se cambia uno de los dos lados, el cron responde 401 y se detiene la conciliación de pedidos.
4. **`WOO_WEBHOOK_SECRET` (webhooks de pedidos):** **requiere tocar WooCommerce producción** (el secreto vive también en los 2 webhooks). Hay que coordinarlo, porque implica una autorización explícita sobre WooCommerce.
   - Generar uno nuevo.
   - `supabase secrets set … WOO_WEBHOOK_SECRET`.
   - De inmediato, `scripts/f360/prod_woo_order_webhooks.sh`, que reescribe el secreto de los webhooks existentes sin duplicarlos.
   - Durante el cambio, un pedido podría rechazarse por firma; la conciliación cada 15 min lo recupera.
5. **`F360_HILO_SECRET`:** coordinar con HiloLabs (Adrián). Generar uno nuevo, cargarlo en HiloLabs (`F360_INTAKE_SECRET`) y en `supabase secrets set … F360_HILO_SECRET` al mismo tiempo. Mientras no coincidan, los escalamientos de Hilo no llegan.

Después de rotar: borrar o archivar las transcripciones locales que contienen los valores (`~/.claude/projects/…/373ab37e-….jsonl` y `c72b5584-….jsonl`), si Mario lo decide.

## 5. Para que no se repita
- Nunca listar archivos de credenciales con `cat` o `sed`. Para ver nombres: `grep -o '^[A-Z_]*='`. Para ver valores: solo longitud o huella.
- Los archivos de un solo valor (`*.secret`, `*-token`, `*-db-url`) no se leen con herramientas que muestran contenido.
