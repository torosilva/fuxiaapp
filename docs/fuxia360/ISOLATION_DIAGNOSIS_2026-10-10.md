# Aislamiento producción ↔ staging + moneda del #2095 — diagnóstico y propuesta (2026-10-10)

> **Solo lectura.** No se desactivó ni editó ningún webhook, no se rotaron secretos, no se tocó producción, WooCommerce ni las pasarelas, no se ejecutó P0D y no se desplegó Growth.
> Sin credenciales: los secretos se compararon por huella (sha256); de WooCommerce solo se pidieron campos sin secreto (`_fields`).
> **Incidente de privacidad durante el diagnóstico:** al leer los metadatos de los pedidos en USD, un filtro amplio dejó pasar el campo `_ppcp_paypal_payer_email` del pedido #3151, y el **correo de una clienta** quedó en la salida de la sesión (transcripción local y conversación). No es una credencial. No se copió a ningún archivo ni a git. Las lecturas siguientes se limitaron a id, moneda, país y precios.

## FASE 1 — Diagnóstico

### 1. Webhooks de WooCommerce producción (fuxiaballerinas.com)
Fuente: `GET /wp-json/wc/v3/webhooks?_fields=id,name,status,topic,delivery_url,…` (llave REST de solo lectura).

| # | Estado | Tema | Nombre | Destino | Creado (UTC) |
|---|---|---|---|---|---|
| 1 | activo | order.created | Fuxia Loyalty Sync | **producción** `tgzg…/functions/v1/woocommerce-webhook` | 2026-08-19 |
| 2 | activo | order.updated | Fuxia App — Order Updated | **producción** `tgzg…/woocommerce-webhook` | 2026-08-19 |
| **3** | **activo** | order.created | Fuxia 360 staging — order.created | **STAGING** `faltxpkaicwpnlqaxrdu…/functions/v1/f360-woo-orders` | **2026-10-06 00:52** |
| **4** | **activo** | order.updated | Fuxia 360 staging — order.updated | **STAGING** `faltxpkaicwpnlqaxrdu…/f360-woo-orders` | **2026-10-06 00:53** |
| 5 | activo | order.created | Fuxia 360 · pedidos (creado) | **producción** `tgzg…/f360-woo-orders` | 2026-10-08 15:10 |
| 6 | activo | order.updated | Fuxia 360 · pedidos (actualizado) | **producción** `tgzg…/f360-woo-orders` | 2026-10-08 15:10 |

### 2. Historial de entregas
Fuente: WooCommerce Action Scheduler (`woocommerce_deliver_webhook_async`), SELECT por SSH. Solo ids de webhook, ids de pedido, estado y fecha; nunca el contenido.

| Webhook | Entregas | Primera | Última (UTC) | Pedidos |
|---|---|---|---|---|
| 1 | 6 completas | 2026-09-12 | 2026-10-08 14:14 | 3525, 3529, 5347, 5351, 3565, 3579 |
| 2 | 19 completas | 2026-09-12 | 2026-10-08 15:11 | los mismos |
| **3 (staging)** | **2 completas** | 2026-10-08 13:56 | 2026-10-08 14:14 | **5347, 5351** |
| **4 (staging)** | **6 completas** | 2026-10-08 13:56 | 2026-10-08 15:11 | **5347, 5351** |
| 6 | 2 completas | 2026-10-08 15:11 | 2026-10-08 15:11 | 5351 |
| 5 | 0 | — | — | (creado después del último pedido) |

WooCommerce purga las tareas completadas después de unos 30 días, por eso el historial empieza el 12 de septiembre.

**Cruce con staging** (`f360.woo_webhook_deliveries`): staging registró exactamente **8 entregas** de producción, ids 1798–1805, del 8 de octubre de 13:56 a 15:11, de los pedidos #5347 y #5351. Coincide 1 a 1 con 2 + 6 de los webhooks #3 y #4.

### 3. Causa (evidencia)
- Los webhooks #3 y #4 se crearon el **6 de octubre** con el nombre "Fuxia 360 staging" y destino staging, es decir, **en staging4**.
- El 8 de octubre se promovió staging4 a producción "tal cual" (decisión del 5 de octubre). La base de WordPress de staging4 llegó a producción **con esos dos webhooks activos y con su secreto de staging**.
- Por eso la función de staging aceptó la firma y registró los pedidos reales como si fueran de `woo_staging4`.
- El mismo día se crearon los webhooks correctos #5 y #6 hacia producción (`prod_woo_order_webhooks.sh`). El script solo busca webhooks con **su propia** URL, así que no detectó los de staging.

### 4. ¿Sigue activo el flujo?
**Sí.** Los webhooks #3 y #4 siguen activos. No ha habido entregas después del 8 de octubre solo porque **no ha habido pedidos en línea en producción desde el #5351**; la lista de Woo, Commerce Facts y los webhooks coinciden. **El próximo pedido real llegará también a staging**, con importes, productos y estado. No llegan datos de envío ni de la clienta, porque `f360-woo-orders` solo guarda la lista blanca de campos.

### 5. Otras rutas producción → staging
| Ruta | Resultado | Fuente |
|---|---|---|
| Cron de la base de producción (7 jobs) | Ninguno menciona staging. URLs en Vault: `f360_sync_url` y `f360_whatsapp_url`, ambas a **producción** | `cron.job`, `vault.decrypted_secrets` (solo host) |
| Funciones SQL / servidores externos en producción | 0 menciones de staging · 0 foreign servers | `pg_proc`, `pg_foreign_server` |
| Destinos de canal en producción | `woo_production` (pedidos on), `woo_staging4` (todo off, inactivo) | `f360.sales_targets` |
| Variables de las Edge Functions de producción | `SUPABASE_URL`, `WOO_BASE_URL`, `WC_URL`, `WOO_TARGET_KEY` y `F360_STOREFRONT_TARGET` apuntan a producción | huellas de `supabase secrets list` |
| Variables de staging | Apuntan a staging4. `WC_URL` es `https://woo.staging.invalid/…` (no llega a ninguna tienda real) | huellas |
| Llaves compartidas entre ambientes | **Ninguna**: Woo, webhooks, sync y OTP son distintos en cada proyecto | comparación de huellas |
| WordPress producción: opciones y `wp-config.php` | 0 menciones de staging | SELECT de nombres, `grep -c` |
| **WordPress producción: contenido de Bricks** | **3 páginas (#8, #3648, #3655)** tienen la URL de `f360-store-reserve` de **staging** en su contenido. El mu-plugin `f360-un-solo-origen.php` la reescribe a producción al mostrar la página. Hoy no sale nada a staging, pero si se borra el mu-plugin, la tienda vuelve a llamar a staging | `postmeta`, mu-plugin |
| App móvil | `EXPO_PUBLIC_SUPABASE_URL` = producción | `fuxia-native/.env` (solo host) |
| Admin (Vercel) | `env-guard.ts` impide en runtime y en build que un deployment mezcle ambientes | `admin-web/src/lib/env-guard.ts` |

### 6–7. Secretos expuestos y sus dependencias
El inventario completo está en `SECURITY_EXPOSURE_2026-10-10.md`. Dependencias verificadas:

| Secreto (producción) | Lo valida | Lo envía | Si se rota a medias |
|---|---|---|---|
| `F360_SYNC_SECRET` | `f360-woo-sync` (env) | Vault `f360_sync_secret`, usado por `f360.commerce_poll_tick()` (cron cada 15 min) y el tick de stock. El admin no lo usa (usa el JWT de la persona) | El cron recibe 401: se detiene la conciliación de pedidos cada 15 min y el push de stock (hoy el stock está apagado en producción) |
| `WOO_WEBHOOK_SECRET` | `f360-woo-orders` (env) | Webhooks #5 y #6 de WooCommerce | Los pedidos nuevos se rechazan por firma; la conciliación cada 15 min los recupera (si sync funciona) |
| `F360_HILO_SECRET` | `f360-hilo-intake` (env) | Backend de HiloLabs (`F360_INTAKE_SECRET`, Railway) | Los escalamientos de Hilo a la bandeja de clientas se pierden hasta que coincidan |
| Contraseña Postgres (`~/.fuxia-db-url`) | Supabase | Scripts locales antiguos; los vigentes usan `~/.fuxia-prod.env`, con otra contraseña | Nada si está obsoleta |
| Token personal de Supabase | — | — | Ya inválido (401) |

Los secretos de staging (incluido el secreto de los webhooks #3 y #4) **no se expusieron** y no comparten valor con producción.

## FASE 2 — Propuesta de corrección (nada ejecutado)

### Cambios necesarios
1. **C1 · Pausar los webhooks #3 y #4** en WooCommerce producción (`status = paused`; no borrarlos para conservar la evidencia). Detiene el envío de pedidos reales a staging.
2. **C2 · Endurecer staging:** `f360-woo-orders` de staging rechaza (y registra) pedidos cuyo `_links`/`store` o origen no sea `staging4.fuxiaballerinas.com`. Cambio de código solo en staging; evita que una copia de la base vuelva a abrir la ruta.
3. **C3 · Corregir el script de webhooks:** `prod_woo_order_webhooks.sh` reporta y aborta si encuentra **cualquier** webhook de pedidos con destino distinto de producción.
4. **C4 · Datos de producción en staging (#5347, #5351):** dejarlos como evidencia marcada, o borrarlos de staging. Son solo cifras, sin datos personales. Decide Mario.
5. **C5 · Bricks:** reemplazar en origen la URL de staging en las páginas #8, #3648 y #3655 (Bricks → elemento Code). Después el mu-plugin `f360-un-solo-origen.php` se puede retirar. Toca contenido de WordPress producción.
6. **C6 · Rotación coordinada** (orden y pasos en `SECURITY_EXPOSURE_2026-10-10.md`): Supabase PAT → contraseña Postgres (si sigue vigente) → `F360_SYNC_SECRET` (Edge env + Vault en la misma ventana) → `F360_HILO_SECRET` (con HiloLabs) → `WOO_WEBHOOK_SECRET` (env + webhooks #5 y #6 vía script). Esta última toca WooCommerce.

### Orden exacto de ejecución
| Paso | Qué | Dónde | Quién / autorización |
|---|---|---|---|
| 0 | Foto previa: lista de webhooks (como en §1) + último id de pedido en producción y en staging | lectura | Claude |
| 1 | **C1** pausar #3 y #4 (`wp wc webhook update 3 --status=paused`, ídem 4) | Woo producción | **Autorización expresa** |
| 2 | Verificar: listar webhooks (3 y 4 = paused; 1, 2, 5 y 6 = active) | lectura | Claude |
| 3 | **C3** script (solo repo) + **C2** función de staging (deploy a staging) | repo / staging | autorización de staging |
| 4 | **C6** rotación, en ventana tranquila, un secreto a la vez, verificando cada uno (cron 200, webhook de prueba, Hilo) | Supabase prod / HiloLabs / Woo | **Autorización expresa** + Adrián para Hilo |
| 5 | **C5** Bricks y retiro del mu-plugin | WordPress producción | **Autorización expresa** |
| 6 | **C4** decisión sobre #5347 y #5351 en staging | staging | Mario |

### Riesgos, impacto y rollback
| Cambio | Impacto esperado | Riesgo | Rollback |
|---|---|---|---|
| C1 | Staging deja de recibir pedidos reales. Producción no cambia (los webhooks #5 y #6 siguen) | Muy bajo: pausar no afecta a los demás webhooks | `wp wc webhook update 3 --status=active` (ídem 4) |
| C2 | Staging solo acepta pedidos de staging4 | Rechazar por error un pedido legítimo de staging4 | Redeploy anterior (`deploy_woo_functions.sh`) |
| C3 | Ninguno en ejecución | — | Revertir el commit |
| C5 | La tienda llama directo a producción | Romper el bloque de búsqueda o reservas de /tienda/ si se edita mal | Revisión de Bricks / restaurar la página; el mu-plugin se queda hasta verificar |
| C6 | Se cierran los secretos expuestos | Cortes de cron, pedidos o Hilo si se hace a medias | Volver al valor anterior en el mismo lugar (está en los archivos locales hasta confirmar) |

### Verificación posterior
- Webhooks: #3 y #4 `paused`; #1, #2, #5 y #6 `active`.
- Con el próximo pedido real: aparece en producción (`f360.woo_webhook_deliveries` y `commerce_woo_orders`) y **no** en staging (`woo_webhook_deliveries` de staging sin filas nuevas con id > 5351). En Action Scheduler, entregas solo para los webhooks 1, 2, 5 y 6.
- Cron `f360-commerce-poll` responde 200 y la salud de Commerce Facts sale OK. Después de la rotación: Hilo crea un escalamiento de prueba.
- Repetir la búsqueda de rutas de §5 (cero menciones de staging en producción, salvo el mu-plugin hasta C5).

---

## Pedido #2095 — moneda (Mario: es COP 405,000, no USD)
> La confirmación de Mario es sobre la **moneda**. No es evidencia de cobro: el pedido está **cancelado y sin pago** (`ever_paid = false`).

### Diagnóstico
| Dónde | Moneda | Importe | Otros datos |
|---|---|---|---|
| WooCommerce producción (`GET /orders`, campos sin datos personales) | **USD** | 405,000 (línea 380,000 + envío) | País de facturación **CO**; PayPal (`ppcp-gateway`); cancelado; entrada por **`nuevo.fuxiaballerinas.com/finalizar-compra/`** (19 jun) |
| Fuxia 360 staging (Commerce Facts, copia de staging4) | USD | 405,000 | `market = ROW`, `market_source = currency`, `market_conflict = false`, `billing_country = CO` |
| Fuxia 360 producción | — | — | No está (P0D no ejecutado) |

**Por qué aparece en USD:**
1. El pedido se creó el 19 de junio desde el dominio de lanzamiento `nuevo.`, con PayPal. La tienda guardó el código de moneda USD pero dejó los precios colombianos: 380,000 por un par. *Hipótesis no comprobada:* en ese momento el selector de moneda o la configuración de PayPal en `nuevo.` cambió el código a USD sin convertir. **Corrección del 10 oct:** no es cierto que PayPal no acepte COP; staging4 tiene pedidos en COP completados con PayPal (#3593).
2. Fuxia 360 asigna el mercado **por moneda** (USD → ROW). Solo marca conflicto si la ruta de entrada dice `/co/` o `/mx/`, y aquí la entrada no la tiene. El país de facturación (CO) se guarda pero **no se usa** para detectar conflictos.

**¿Hay otros pedidos colombianos así?** No. De 84 pedidos desde el 1 de junio, los 32 con facturación CO son 31 en COP más **solo el #2095** en USD. Los otros 4 en USD son reales (precio 150 USD; Estados Unidos y Chile). Ningún MXN o COP tiene precios fuera de rango.

**¿Distorsiona Growth hoy?** Los **ingresos pagados no**, porque está cancelado y nunca contó. Sí distorsiona:
- los **conteos de checkout por mercado**: un pedido creado y no pagado aparece en "Resto del mundo" y no en Colombia;
- cualquier **suma de importes creados** en USD (por ejemplo, el resumen de `P0D_PREFLIGHT.md` muestra "USD 405,795 cancelados");
- la Conciliación, que lo lista como USD 405,000.

### Plan de corrección (staging primero; no ejecutado)
- **No se toca** WooCommerce, el importe (405,000) ni el estado financiero (cancelado, sin cobro).
- **R1 · Corrección auditada de moneda/mercado**, separada del dato de Woo (mismo patrón que las exclusiones):
  - tabla append-only `f360.commerce_currency_corrections`: pedido, moneda y mercado originales, moneda y mercado corregidos, motivo, evidencia (país CO, precio de línea, confirmación de Mario), quién y cuándo, y a qué corrección reemplaza;
  - RPC solo para Carolina y Mario.
- **R2 · `f360.commerce_orders`** mantiene `currency_original` (USD, lo que dice Woo) y agrega `currency_reporting` / `market_reporting` con la corrección vigente. El War Room, la Conciliación y `measurement_sales` agrupan por los campos *reporting*. Los importes no se convierten: 405,000 se lee como COP.
- **R3 · Regla de detección** (sin corregir automáticamente): marcar `market_conflict` también cuando el país de facturación no coincide con el mercado por moneda y el precio unitario está fuera del rango de esa moneda. Así un caso nuevo aparece en Conciliación como "Moneda sospechosa", para que una persona lo confirme.
- **R4 · P0D:** importar el #2095 tal como está en Woo (USD) y aplicar R1 encima, para conservar la verdad de la fuente. El preflight se vuelve a correr para mostrar el resumen ya con la moneda corregida.
- **Pruebas:**
  - el importe y el estado no cambian;
  - los ingresos pagados de CO y ROW quedan idénticos (es un pedido cancelado);
  - los conteos de checkout pasan 1 pedido de ROW a CO;
  - revertir la corrección regresa al estado original;
  - sin permiso, rechazado;
  - historial inmutable.
- **Rollback:** registrar una corrección inversa (evento nuevo), o el `.down.sql` que borra la tabla y deja la vista como antes.

---

## EJECUCIÓN — 2026-10-10 (autorizada por Mario)

### 1. Webhooks (WooCommerce producción): HECHO
- **Antes (21:21 UTC, REST de solo lectura):** igual que el diagnóstico. #1, #2, #5 y #6 activos → producción; #3 y #4 activos → staging.
- **Cambio:** un script con protección (aborta si algún webhook no apunta a `faltxpkaicwpnlqaxrdu` o no está activo) puso **#3 y #4 en `paused`**. No se borró nada. `date_modified` de ambos: 2026-10-10T21:21:45.
- **Después (REST + wp-cli):**

| # | Estado | Destino | Tema |
|---|---|---|---|
| 1 | active | producción | order.created |
| 2 | active | producción | order.updated |
| 3 | **paused** | staging | order.created |
| 4 | **paused** | staging | order.updated |
| 5 | active | producción | order.created |
| 6 | active | producción | order.updated |

- **Reactivar si hiciera falta:** `wp wc webhook update 3 --status=active --user=<admin>` (ídem 4).

### 2. Rotación de secretos de producción
Herramienta: `scripts/f360/rotate_prod_secret.sh` (en el repo, sin valores). Los valores viajan por archivos `chmod 600` y nunca se imprimen. Cada rotación verifica y, si falla, vuelve sola al valor anterior.

| Secreto | Estado | Verificación |
|---|---|---|
| `F360_SYNC_SECRET` (env de `f360-woo-sync` + Vault `f360_sync_secret`) | **ROTADO** ~21:23 UTC | Valor nuevo → 200; anterior → 401. **Cron de las 21:30 OK desde Vault** (última conciliación buena 21:30:02). Las 11 llamadas de cron desde la rotación respondieron 200. Valor anterior borrado. |
| `WOO_WEBHOOK_SECRET` (env de `f360-woo-orders` + webhooks #5 y #6) | **ROTADO** ~21:33 UTC | Entrega firmada de prueba (tema que no es pedido, no escribe nada) con el valor nuevo → 200; con el anterior → 401. En el servidor, los webhooks #5 y #6 firman con el secreto nuevo (comparación `hash_equals`, sí/no). Valor anterior borrado. |
| `F360_HILO_SECRET` | **PENDIENTE: coordinar con Adrián** (HiloLabs, `F360_INTAKE_SECRET`). No se tocó. | — |
| Contraseña Postgres de `~/.fuxia-db-url` | **PENDIENTE (Mario):** revisar si sigue vigente (comando en `SECURITY_EXPOSURE_2026-10-10.md` §4.2) | — |
| Token personal de Supabase | Ya inválido (401). Recomendado: revocarlo en el panel (Mario) | — |

Incidente durante la ejecución, sin impacto: el primer intento de rotar sync abortó **antes de cambiar nada**, por un error de sintaxis del script (`$NAME…`). Solo creó las copias locales, que se borraron; se comprobó que el valor vigente seguía respondiendo 200. Se corrigió el script y se volvió a correr.

### 3. Controles preparados (NO aplicados)
- **Bloqueo de origen** en `f360-woo-orders`: con la variable `WOO_EXPECTED_SOURCE` definida, la función rechaza (403) y registra cualquier entrega cuyo `x-wc-webhook-source` no sea esa tienda, aunque traiga firma válida. Sin la variable, todo sigue igual que hoy. Prueba nueva en `commerce.test.ts`; Node 72/72. **No desplegado.** Activarlo en staging = deploy + `WOO_EXPECTED_SOURCE=staging4.fuxiaballerinas.com`; en producción, `fuxiaballerinas.com`.
- **Bricks:** `scripts/f360/prod_bricks_staging_urls.sh`. Simulación de solo lectura: páginas 8 (Tienda), 3648 (Tienda) y 3655, 1 referencia cada una. `apply` respalda cada valor en el servidor antes de reemplazar solo esa URL; `restore` lo regresa. **No ejecutado.**

### 4. #5347 y #5351 en staging: conservados y marcados
Migración `20261022000500_f360_environment_foreign_events.sql`: tabla append-only `f360.environment_foreign_events` y marca **"Evento de producción"** en Conciliación. Los datos se cargan con `supabase/staging/mark_foreign_events.sql`, que aborta si la base no es staging, con las 2 y 6 entregas de evidencia. Los registros originales no se tocan.
