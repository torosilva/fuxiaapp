# 06 · Experimentos de Growth

**Fecha:** 2026-10-08. **Estado:** especificación. **Hoy no existe** ningún registro de experimentos en el repo ni en producción (búsqueda en migraciones y `information_schema`: sin tablas `experiment*`). Lo más cercano: `f360.growth_plan_changes` (bitácora del Plan 2027) y `f360.reported_figures` (0 filas).

---

## 1. Principio

```
HYPOTHESIS → CREATIVE → TEST → SIGNAL → WINNER → PAID AMPLIFICATION → PAID SALE → SCALE / ITERATE / KILL
```

1. **Hipótesis primero**, escrita antes de gastar: "Si mostramos X a Y en Z, esperamos que el KPI W suba de A a B".
2. **Un experimento = una variable principal.** Si cambian dos cosas, se registra como dos o como "multivariable / inconcluso por diseño".
3. **La señal temprana** (CTR, favoritos, ATC) sirve para elegir un ganador de **creativo**; **el veredicto final se toma con PAID SALE** (Commerce Facts) cuando el experimento busca ventas.
4. **Umbrales antes de empezar:** `success_threshold` y `kill_threshold` se fijan en DRAFT y no se editan después de RUNNING (se registran cambios).
5. **Nada se borra:** un experimento perdedor es aprendizaje.
6. **Sin PII:** audiencias se describen, no se listan.

---

## 2. Tabla propuesta `f360.growth_experiments` (sin migración)

| Campo | Tipo | Regla |
|---|---|---|
| `id` | uuid PK | — |
| `code` | text único | `EXP-2026-001` (legible) |
| `name` | text | — |
| `hypothesis` | text NOT NULL | Formato §1.1 |
| `market` | text | `MX` / `CO` / `ROW` / `ALL` (mismo vocabulario que `commerce_orders.market`) |
| `channel` | text | `channel_group` de `channel_rules_v1` o `store` / `crm_whatsapp` / `crm_email` / `onsite` |
| `audience` | text | Descripción (p. ej. "lookalike compradoras MX 25-44"); **nunca** lista de personas |
| `product_key` | text NULL | `F360-{MODELO}` (FK lógica a `f360.products.code`) |
| `product_id` | uuid NULL FK → `f360.products(id)` | — |
| `creative_ref` | text NULL | ID de creativo / `utm_content` / `ad_id` |
| `primary_variable` | text NOT NULL | Qué cambia (creativo, precio mostrado, oferta, audiencia, landing, copy, orden de tienda…) |
| `start_date`, `end_date` | date | `end_date` planeada; real en `ended_at` |
| `budget` | numeric NULL + `budget_currency` | Moneda original |
| `primary_kpi` | text NOT NULL | De la lista de `03_…` (p. ej. `paid_orders`, `roas_f360`, `cac`, `favorites`, `atc_rate`) |
| `secondary_kpis` | text[] | — |
| `success_threshold` | jsonb | `{kpi, op, value, min_sample}` |
| `kill_threshold` | jsonb | Ídem |
| `status` | text CHECK | §3 |
| `result` | jsonb | Valores observados de los KPIs al cierre, **con fuente y calidad** (snapshot, no recalculado) |
| `learning` | text | Qué aprendimos |
| `decision` | text CHECK | `SCALE` / `ITERATE` / `KILL` / `NONE` |
| `created_by` | uuid FK → `auth.users` | Del JWT, nunca del cliente |
| `approved_by` | uuid NULL | Owner; distinto de `created_by` cuando haya más de un owner (PROPUESTA) |
| `created_at`, `approved_at`, `started_at`, `ended_at` | timestamptz | — |
| `utm_campaign` / `campaign_ids` | text / text[] | Llave para unir con atribución y gasto |

**Tabla de bitácora** `f360.growth_experiment_changes` (append-only, patrón de `growth_plan_changes`): `experiment_id`, `from_status`, `to_status`, `field`, `old`, `new`, `actor`, `at`, `reason`.

---

## 3. Estados y transiciones

| Estado | Significado | Desde | Quién |
|---|---|---|---|
| `DRAFT` | Hipótesis escrita, umbrales definidos | — | operator / owner |
| `APPROVED` | Aprobado para gastar/ejecutar | DRAFT | **owner** |
| `RUNNING` | En curso | APPROVED | operator / owner |
| `WINNER` | Cumplió `success_threshold` con muestra mínima | RUNNING | owner |
| `LOSER` | Cumplió `kill_threshold` | RUNNING | owner |
| `INCONCLUSIVE` | Terminó sin cruzar umbrales o con muestra insuficiente | RUNNING | owner |
| `STOPPED` | Detenido antes de tiempo por motivo externo (stock, error, presupuesto) | APPROVED / RUNNING | owner / operator |
| `ARCHIVED` | Cerrado y documentado | WINNER / LOSER / INCONCLUSIVE / STOPPED | owner |

**Reglas:** RUNNING exige `start_date`, `primary_kpi`, `success_threshold`, `kill_threshold`. WINNER/LOSER/INCONCLUSIVE exigen `result` y `learning`. ARCHIVED exige `decision`. Umbrales inmutables desde RUNNING (cualquier cambio se rechaza; se crea un experimento nuevo).

---

## 4. Seguridad

| Aspecto | Regla |
|---|---|
| RLS | Tabla sin acceso directo (`REVOKE … FROM anon, authenticated`), igual que Commerce Facts |
| Escritura | RPCs `f360_experiment_save` / `f360_experiment_transition` con `require_role('operator')`; aprobación y veredicto con `require_role('owner')` |
| Lectura | `f360_experiments_list` (operator+). Sellers y viewers no ven presupuestos (D-G1-05) |
| Identidad | `created_by` / `approved_by` del `auth.uid()`; nunca del payload |
| Resultados | `result` se calcula en el servidor desde Commerce Facts / gasto al cerrar; el cliente no envía números |

---

## 5. Cómo se mide un experimento (con lo que hay)

| Tipo de experimento | KPI principal | ¿Medible hoy? |
|---|---|---|
| Creativo en Meta (A/B) | `paid_orders` atribuidas por `utm_content` | PARCIAL: atribución sí; gasto no → sin ROAS |
| Oferta / cupón | PS con cupón (`coupon_count > 0`), AOV | Sí, en cuanto haya pedidos |
| Orden de la tienda / destacados (`f360-orden-tienda`) | PS por modelo, favoritos | Parcial (sin vistas GA4) |
| Avísame / sobre pedido | Conversión NOTIFY_ME → PURCHASE | Cuando Avísame esté en prod |
| CRM WhatsApp | PS de clientas contactadas vs control | Requiere consentimiento de marketing (0 hoy) y grupo control |
| Tienda física (vendedora, exhibición) | PS por ubicación | Sí (ventas por RPC) |

**Muestra mínima:** con el volumen online observado en el clon de staging4 (≈ 54 pedidos pagados en ~3.5 meses, `G1B` §5) un A/B sobre pedidos pagados tarda meses en ser concluyente. Por eso: **señal temprana para elegir creativo, venta pagada para decidir presupuesto**, y `INCONCLUSIVE` es un resultado válido.

---

## 6. UI (propuesta mínima)

Pestaña `/growth?vista=experimentos`: lista con estado, mercado, KPI, umbrales y resultado; formulario de 1 pantalla para DRAFT; botón "Aprobar" solo para owner. Sin gráficos predictivos.
