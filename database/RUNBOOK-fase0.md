# Runbook Fase 0 — Deploy de seguridad + conexión web↔app

Cambios listos en la rama `fase0-hardening`. Este runbook te lleva de "código escrito" a "deployado y verificado". El **orden importa**: primero base de datos, luego edge functions, luego la app.

> Todo lo de Supabase requiere tu sesión del CLI (`npx supabase login`) o el SQL Editor del dashboard. Yo no puedo deployar por ti; esto lo corres tú o Claude Code local.

---

## Qué incluye este cambio

**Seguridad (P0)**
- RLS + `auth_user_id` en todas las tablas de clienta (nadie puede ya leer datos ajenos ni auto-editarse puntos con la anon key).
- Proxy de WooCommerce: se quitó `orders` de la whitelist (ya no se filtran pedidos de toda la tienda).
- Webhook: firma HMAC **obligatoria** (antes aceptaba órdenes sin firma).
- OTP: límite de 5 intentos por código + código generado con CSPRNG.

**Conexión web↔app definitiva**
- Webhook reescrito (ya compila — el anterior tenía funciones duplicadas): acredita al confirmar pago (`processing`), revierte en reembolso/cancelación, lee umbrales de `tier_config`, 100 pts/par.
- `unmatched_orders` + `link-orders`: compras web previas al registro se acreditan retroactivamente.
- `my-orders`: rastreo de pedidos seguro (JWT del usuario, server-side).
- Fix bug: `useAuth` ahora sí trae `wc_customer_id`.

---

## Paso 0 — Pre-flight (5 min)

1. **Backup de la base** (Supabase Dashboard → Database → Backups, o `pg_dump`). Las migraciones son idempotentes, pero un backup antes de tocar RLS es obligatorio.
2. Confirmá que el secret `OTP_SALT` está seteado con un valor fuerte:
   ```bash
   npx supabase secrets list --project-ref tgzgiwfzddsghnxgkcqd | grep OTP_SALT
   # si no está: npx supabase secrets set OTP_SALT=$(openssl rand -hex 32) --project-ref tgzgiwfzddsghnxgkcqd
   ```

## Paso 1 — Migraciones SQL (en este orden)

En el SQL Editor de Supabase (o `psql`), corré:

1. `database/points_orders_migration.sql` — tier_config a 300/900, `unmatched_orders`, columnas de reversa, `attempts` en OTP.
2. `database/rls_migration.sql` — `auth_user_id` + backfill + RLS.

Verificá el backfill (debe dar 0 filas sin vincular, salvo cuentas sin auth user):
```sql
SELECT count(*) FROM customers WHERE auth_user_id IS NULL;
```

> **Si algo se rompe en producción:** el bloque de rollback está comentado al final de `rls_migration.sql` (deshabilitar RLS por tabla). Deshabilitá, avisá, y diagnosticamos.

## Paso 2 — Edge functions

```bash
cd fuxia-native
# webhook: público, sin verify-jwt (lo llama WooCommerce)
npx supabase functions deploy woocommerce-webhook --no-verify-jwt --project-ref tgzgiwfzddsghnxgkcqd
# proxy: igual que antes
npx supabase functions deploy woocommerce-proxy --project-ref tgzgiwfzddsghnxgkcqd
# nuevas: CON verify-jwt (default) — exigen sesión del usuario
npx supabase functions deploy my-orders   --project-ref tgzgiwfzddsghnxgkcqd
npx supabase functions deploy link-orders --project-ref tgzgiwfzddsghnxgkcqd
# otp: con el límite de intentos nuevo
npx supabase functions deploy whatsapp-otp --project-ref tgzgiwfzddsghnxgkcqd
```

Confirmá que `RESEND_API_KEY` y `TWILIO_WELCOME_CONTENT_SID` están seteados si querés el correo/WhatsApp de bienvenida (opcionales; si faltan, simplemente no se manda).

## Paso 3 — App (EAS Update)

Los cambios de la app son solo JS → OTA, no requieren rebuild:
```bash
cd fuxia-native
npx eas update --branch preview --message "fase0: RLS + my-orders + retro-credito"
```
(Para producción usá el branch/canal que corresponda.)

## Paso 4 — Checkout de WooCommerce (para que el matching no pierda compras)

En WordPress:
1. WooCommerce → Ajustes → **hacer el teléfono obligatorio** en el checkout.
2. (Recomendado) Snippet que normalice el teléfono a `+52...` antes de guardar la orden, para que matchee con el formato de la app.
3. Confirmá qué plugin de guías usás y que escriba una de estas meta keys: `_tracking_number` / `_aftership_tracking_number`. Si usa otra, decime cuál y la agrego a `my-orders`.

---

## Verificación de humo (hacela toda antes de anunciar)

1. **RLS bloquea lo ajeno:** con la anon key (sin login), intentá `select * from customers` desde un cliente REST → debe volver vacío/denegado.
2. **Registro nuevo:** onboarding completo → se crea customer con `auth_user_id`, tarjeta visible.
3. **Compra web → puntos:** hacé una compra real, marcala `processing` → llega push "Ganaste 100 puntos", se ve en la tarjeta.
4. **Reembolso:** reembolsá esa orden en WC → los puntos se restan.
5. **Retro-crédito:** hacé una compra web con un teléfono NO registrado → registrate con ese teléfono → al abrir la app, los puntos aparecen.
6. **Rastreo:** entrá a "Seguimiento" → ves solo TUS pedidos con estado (y guía si el plugin la escribe).
7. **OTP brute-force:** meté 6 códigos malos → al 6º responde "Demasiados intentos".

---

## Gap conocido que queda para Fase 1 (decisión tuya)

Las tablas operativas (`staff`, `offline_sales`, `channel_inventory`, `channels`, `support_tickets`) hoy quedan con **lectura para cualquier usuario autenticado**. Esto cierra el hueco grande (acceso anónimo con la anon key), pero un usuario logueado todavía podría leerlas — incluido `staff.pin`. El fix correcto es mover la validación de PIN de vendedora a una edge function y restringir estas tablas por rol (`customers.role`). No lo incluí en este lote porque cambiarlo sin saber cómo mapean las vendedoras a cuentas podría romper el flujo de tienda justo antes del lanzamiento. **Decisión pendiente:** ¿lo hacemos antes de septiembre o en la 1.1? Si me confirmás cómo se autentican las vendedoras, lo dejo cerrado.
