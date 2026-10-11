# D12 · Fase B: retiro del modo anterior (NIP sin sesión) — PLAN, no ejecutado — 2026-10-11

> Mario: "Preparar el plan … No ejecutar Fase B todavía." Este documento es solo plan.
> Los datos salen de consultas de **solo lectura** en producción hechas el 2026-10-11.
> Los nombres son de personal interno; no se incluyen NIP ni teléfonos.

## 1. Qué cierra la fase B
| Política o función | Abre | Usada por |
|---|---|---|
| `staff.anon_read_active_staff` | NIP de todo el personal activo, sin sesión | `vendedora/index.tsx:132` (pantalla de NIP) |
| `offline_sales.anon_insert_offline_sales` | registrar ventas sin sesión | `vendedora/sale.tsx:190` |
| `offline_sales.anon_read_offline_sales` / `anon_read_own_sales` | leer todas las ventas sin sesión | `vendedora/home.tsx`, `sales-today.tsx` (modo anterior) |
| `channel_inventory.anon_update_inventory_sold` | cambiar `sold` y `stock` sin sesión | `vendedora/sale.tsx:162`, `vendedora/inventory.tsx:92` |
| `channel_inventory.admins_all_inventory`, `channels.admins_all_channels` | ALL con `user_metadata.phone` (falsificable; ver fase A §3) | ninguna pantalla depende de ellas: hay equivalentes con `my_role()` |
| Edge Function `claim-sale` | puntos con el total que manda el cliente, sin identificar a quien llama | `vendedora/sale.tsx` (QR) y `claim.tsx` |

## 2. Inventario: tiendas y personas que siguen en el modo anterior
Ventas de la app anterior (`created_by_rpc = false`) en los últimos 60 días:

| Canal anterior | Tipo | Ventas 60 d | Última | Quién vendió (60 d) | Personal anterior | Ubicación en F360 | Vendedoras F360 |
|---|---|---|---|---|---|---|---|
| **Guadalajara** | bazar | **27** | 2026-09-30 | Paola 24, Chelita Gómez 3 | Chelita Gómez, Mario, Paola | **no existe** | — |
| **Tienda Polanco** | tienda | 6 | 2026-10-05 | Reyna 5, Valeria 1 | Reyna, Valeria, Reyna (inactiva) | Tienda Polanco (F360; 7 ventas F360) | Carolina Muñoz, Valeria García, Valeria Pérez y Reyna Vega: activas y con cuenta |
| **Contreras** | tienda | 1 | 2026-09-17 | Dulce Sur 1 | Dulce Sur | ¿San Jerónimo Lídice? (por confirmar) | Dulce Sur: **pendiente, sin cuenta** (en San Jerónimo Lídice) |
| Monterrey | bazar | 0 | 2026-05-18 | — | Carolina Muñoz | no existe | — |
| Cali | tienda | 0 | nunca | — | Adriana | no aplica: Cali es casa matriz y no es ubicación de F360 | — |

**Dispositivos.** La app anterior no registra el dispositivo en cada venta. La identificación es por canal y por vendedora (`staff_id`). Para saber qué teléfonos o tabletas usan la pantalla de NIP hay que preguntarlo en cada tienda (checklist §4, paso 0).

**Vendedoras que hay que migrar (propuesta para que Mario la confirme):**
| Persona | Tienda | Situación | Qué falta |
|---|---|---|---|
| Paola | Guadalajara | vende por el modo anterior (24 en 60 días) | ubicación F360 de Guadalajara, alta como vendedora y cuenta propia |
| Chelita Gómez | Guadalajara | igual (3) | igual |
| Reyna | Polanco | ya tiene cuenta F360 (REYNA VEGA), pero vendió por el modo anterior hasta el 10-05 | usar solo el turno F360; quitarle la entrada al modo anterior |
| Valeria | Polanco | ya tiene cuenta F360 (Valeria García o Pérez: **¿cuál es?**) | igual |
| Dulce Sur | Contreras | alta F360 **pendiente** en San Jerónimo Lídice | confirmar que Contreras = San Jerónimo Lídice; activar la cuenta |
| Mario (personal de Guadalajara) | Guadalajara | sin ventas | ¿darlo de baja del personal anterior? |
| Carolina Muñoz (Monterrey) | Monterrey | sin ventas desde mayo; ya es vendedora F360 en Polanco | desactivar el registro anterior |
| Adriana | Cali | sin ventas | Cali no entra a F360; ¿se desactiva el registro anterior? |

## 3. Decisiones de negocio que necesita Mario (no las asumo)
1. **Guadalajara (bazar):** ¿se crea su ubicación en F360, con su inventario (conteo inicial), o deja de operar? Sin ubicación F360 no hay turno de vendedora.
2. **Contreras = San Jerónimo Lídice?** Hay que confirmarlo.
3. **Devoluciones en tienda.** Hoy no existe ningún flujo, ni en la app anterior ni en F360. Antes de probarlas hay que definir la regla:
   - ¿cambio por otra talla o reembolso?
   - ¿qué pasa con los puntos?
   - ¿quién la autoriza?
4. **Fecha de corte** a partir de la cual el modo anterior deja de funcionar.

## 4. Procedimiento por tienda (cuando Mario lo autorice)
0. **Inventario de dispositivos:** en cada tienda, anotar qué teléfono o tableta se usa para vender y si tiene la app publicada (actualización OTA `production`).
1. **Alta:** `f360_admin_seller_add` en la ubicación. La vendedora define su NIP en su primer turno. Se guarda cifrado con bcrypt, con bloqueo por intentos (`f360.seller_credentials`); nunca en texto.
2. **Cuenta propia:** la vendedora inicia sesión en la app con su teléfono, y su cuenta se vincula a `f360.sellers` (`auth_user_id`).
3. **Ensayo en staging** con la misma ubicación (la copia nocturna trae los datos de producción):
   - **Venta:** turno → venta F360 (`f360_record_store_sale`) → baja el inventario de F360 y se acreditan puntos por el servidor (`loyalty_apply`).
   - **Ajuste de inventario:** `f360_adjust_inventory` por la operadora, auditado en el ledger.
   - **Devolución:** solo cuando Mario defina la regla (§3.3).
   - **Apartado y descuento:** `f360_reservation_*` y `f360_store_discount_*` (ya probados en sus fases).
4. **Primer día en vivo** con acompañamiento. Comparar las ventas del día (F360 contra el conteo físico o la caja).
5. **Retiro del modo anterior en esa tienda:** desactivar su personal en `public.staff` (`active = false`). Así la pantalla de NIP deja de aceptarlas sin tocar todavía las políticas.

## 5. Cierre técnico (migración de la fase B, después del paso 5 en todas las tiendas)
1. Quitar `anon_read_active_staff`, `anon_insert_offline_sales`, `anon_read_offline_sales`, `anon_read_own_sales`, `anon_update_inventory_sold`, `admins_all_inventory` y `admins_all_channels`.
2. Quitar los permisos de tabla de `anon` sobre `staff`, `offline_sales`, `offline_sale_items`, `channel_inventory` y `support_tickets` (hoy tiene todos, incluido `TRUNCATE`).
3. **App** (OTA): quitar `VendedoraLoginScreen` y el botón "Usar el modo anterior". Sin sesión, /vendedora pide iniciar sesión, igual que con `F360_SELLER_SESSION`.
4. **`claim-sale`:**
   - quitar `scan_qr`: la venta con QR ya la hace `f360_record_store_sale` con `customer_qr`;
   - el reclamo por código se cambia por `f360_claim_store_sale` (con sesión, puntos calculados en el servidor);
   - después, despublicar la función.
5. Ensayo en staging con la prueba de la fase A ampliada: anónimo no ve ni escribe nada; las vendedoras F360 venden; clientas reclaman. Reversión con `.down.sql` ensayada.

## 6. Rotación de los NIP expuestos
Todos los NIP de `public.staff` se consideran comprometidos: cualquiera con la llave pública podía leerlos.
1. Los NIP del modo anterior **no se reutilizan** en F360. Cada vendedora elige uno nuevo al activar su cuenta (paso 4.1). Si alguna repite el anterior, la admin lo restablece con `f360_admin_seller_reset_pin`.
2. Mientras el modo anterior siga vivo en una tienda, la admin cambia el NIP de cada vendedora activa desde Personal en la app (admin, `staff admin write`). Se le comunica en persona, no por mensaje.
3. Al cerrar la fase B, `public.staff.pin` deja de ser legible por clientes. Si la admin ya no necesita la pantalla anterior de Personal, se sustituye por valores vacíos o con hash, y la columna se elimina en una migración posterior.

## 7. Contingencia: validación del NIP en el servidor (solo si una tienda no puede migrar a tiempo)
Diseño, no implementado:
- **`public.d12_legacy_shift_start(p_channel uuid, p_pin text)`**, `SECURITY DEFINER`:
  - compara el NIP con un **hash bcrypt** (columna nueva `staff.pin_hash`; el texto plano se borra);
  - aplica bloqueo por intentos, igual que `f360.seller_credentials`;
  - devuelve **un token de turno** de corta duración (8 h, ligado a canal y vendedora), **nunca** el NIP ni la lista del personal.
- **`public.d12_legacy_sale(p_token, p_items[{channel_inventory_id, qty}], p_payment, p_customer_qr, p_idempotency)`**, `SECURITY DEFINER`:
  - valida el token;
  - el **precio sale de `channel_inventory.price`**, no del cliente;
  - baja `sold` de forma atómica y nunca deja existencias negativas;
  - registra la venta (`created_by_rpc = true`, `price_source = 'legacy'`) y aplica los puntos con `loyalty_apply`.

  Es el mismo patrón que `f360_record_store_sale` (S0.3).
- **Ajustes de inventario** de la vendedora: solo como solicitud (`inventory_change_requests`) con el token. La aplicación sigue en `inventory-approve` (solo admin).
- **Permisos:** `anon` solo ejecuta esas dos funciones. Las políticas `anon_*` se quitan igual que en §5.

Así, aunque el modo anterior siga vivo, nadie lee NIP ni ventas y nadie escribe ventas o inventario sin un turno válido.

## 8. Plan ante fallas de autenticación (en el día de la migración)
| Falla | Respuesta |
|---|---|
| La vendedora no recuerda el NIP o está bloqueada | La admin hace `f360_admin_seller_reset_pin` desde el admin web; el NIP nuevo se le da en persona |
| No le llega el código de inicio de sesión (SMS o WhatsApp) | La operadora o dueña abre el turno en su propio teléfono para esa ubicación (ya funciona: `f360Role owner/operator`) |
| La app o Supabase no responden | Venta en papel (folio, artículos, forma de pago, teléfono de la clienta) y captura posterior por la operadora (`f360_hist_sales_save`, auditado). Los puntos se acreditan cuando la clienta reclama |
| Falla general después del cierre técnico | Reversión de la migración de la fase B (`.down.sql`, ensayada) y OTA anterior (`eas update` al grupo previo). Restablece el modo anterior el mismo día |

## 9. Criterios de cierre definitivo de D12
1. Fase A aplicada en producción y verificada (huella `af59dcb1…`).
2. 0 ventas con `created_by_rpc = false` en los 14 días previos al cierre técnico, en todas las tiendas.
3. Todas las vendedoras activas tienen cuenta F360 (`f360.sellers.status = 'activa'`, `auth_user_id` no nulo). Todo `public.staff` está desactivado, o validado en el servidor (§7) solo donde Mario lo apruebe.
4. Migración de la fase B en producción. Prueba anónima con la llave pública: 0 filas en `staff`, `offline_sales`, `support_tickets`, `channel_inventory` y `channels` (salvo los canales activos, si se decide mantenerlos) y 0 escrituras.
5. `claim-sale`: sin `scan_qr` y sin acreditar con total del cliente, o despublicada.
6. Los NIP del modo anterior están rotados o eliminados.
7. App: OTA sin la pantalla de NIP anterior, probada por una vendedora de cada tienda.
8. El hallazgo `SECURITY_FINDING_2026-10-11_LEGACY_RLS.md` queda marcado como **cerrado**, con fecha y evidencia.
