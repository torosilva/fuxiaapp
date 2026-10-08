# 03 · Growth Cockpit (especificación)

**Fecha:** 2026-10-08. **Estado:** especificación. **No construido.**

**Dónde vive:** evoluciona `/growth` (pestaña "Inteligencia comercial", hoy estática: `admin-web/src/app/(app)/growth/page.tsx:29-44`). **No** se crea otro tablero (G0 #25). `/tablero` (Centro de control) sigue siendo la vista operativa del día; el cockpit es la vista de **adquisición y eficiencia**.

**Acceso:** owner / operator (`canWrite`, igual que `/growth`, `/tablero`, `/demanda`). Lectura por **un RPC agregado** sin PII (patrón de `f360_exec_dashboard`, `20261010000300:16-19`).

**Regla de UI:** cuando falta un insumo, la tarjeta muestra **DATA INCOMPLETE** + qué falta + cómo se resuelve. Nunca 0, nunca "—" sin explicación. Cada tarjeta tiene un pie con FUENTE · PERIODO · COBERTURA · CALIDAD.

---

## 1. Filtros

| Filtro | Valores | Fuente | Disponible hoy |
|---|---|---|---|
| Periodo | hoy / semana / mes / año / rango; comparación con periodo anterior | `paid_at` en CDMX | Sí |
| Mercado | MX / CO / ROW | `commerce_orders.market` | Sí |
| País | ISO-2 | `billing_country` (online); `customers.country`; `order_shipping.country` | Parcial |
| Canal | `channel_group` (`channel_rules_v1`, G2-A §1) + "Tienda física" | Vista nueva `f360.growth_order_channel` (`09_…`) sobre `commerce_woo_attribution` | No (vista por construir) |
| Campaña | `utm_campaign` normalizado; `campaign_id` cuando exista gasto | Atribución + `f360.marketing_spend_daily` (propuesta) | Parcial (solo UTM) |
| Creativo | `utm_content` / `ad_id` | Ídem | Parcial |
| Producto | modelo (`canonical_product_key`), color, talla | `commerce_order_lines` | Sí |
| Nueva vs recurrente | new / repeat / sin identidad | `02_…` §2.7 | **No** (sin historia) |

**Regla de filtros:** un filtro que el KPI no soporta **no se aplica en silencio**; la tarjeta dice "no disponible con este filtro" (p. ej. Marketing Spend filtrado por talla).

---

## 2. KPIs

Notación: `PS` = venta pagada (`status_class='countable'`); `NP` = net product (`02_…` §2.3); moneda original siempre.

### 2.1 Revenue Paid
| Campo | Valor |
|---|---|
| SOURCE | `f360.commerce_orders` (online + tienda F360) + `historical_sales_active` (marcado, solo MXN, solo vista total) |
| FORMULA | Σ `net_product` de PS en el periodo, por moneda. Variante "total cobrado" = Σ `order_total` |
| REFRESH | Online: tiempo real por webhook; **poll de 15 min no corre en prod** (`01_…` §C). Tienda: tiempo real |
| CONFIDENCE | ALTA para lo capturado; **BAJA en cobertura** hasta tener backfill y poll |
| KNOWN LIMITATIONS | Online desde 2026-10-08 (corte 5351); ventas de tienda legacy (36 de 37) fuera; no consolida monedas; pedidos de link de pago `origin_unknown` |
| DATA INCOMPLETE cuando | El periodo empieza antes del primer dato capturado del canal, o `commerce_source_health` ≠ VERIFIED |

### 2.2 Marketing Spend
| Campo | Valor |
|---|---|
| SOURCE | **Ninguna hoy.** Propuesta: `f360.marketing_spend_daily` (import de Meta Ads / Google Ads por API o CSV, `09_…`) |
| FORMULA | Σ `spend` por día × plataforma × cuenta × campaña × adset × ad, moneda de la cuenta |
| REFRESH | Diario (D+1); la plataforma ajusta 1–3 días hacia atrás → re-import de los últimos 7 días |
| CONFIDENCE | ALTA para el gasto (es la factura de la plataforma) cuando exista |
| KNOWN LIMITATIONS | Sin acceso (Meta Ads / Events Manager); Google Ads UNKNOWN; gasto de agencia, influencers o producción de contenido no está en la plataforma → `spend_source = manual` |
| DATA INCOMPLETE cuando | **Siempre hoy.** Y cuando falte cualquier día del periodo para una plataforma activa |

### 2.3 New Customers
| Campo | Valor |
|---|---|
| SOURCE | PS + clave de clienta (`02_…` §2.7) + historia |
| FORMULA | count(distinct clienta) cuya primera PS cae en el periodo |
| REFRESH | Con cada PS |
| CONFIDENCE | NINGUNA hoy |
| KNOWN LIMITATIONS | Sin historia previa a 2026-10-08; invitadas sin teléfono/correo usable; dos dispositivos/correos = dos personas |
| DATA INCOMPLETE cuando | Historia < lookback (24 m, PROPUESTA) |

### 2.4 Paid Orders
| Campo | Valor |
|---|---|
| SOURCE | `commerce_orders` |
| FORMULA | count(PS); aparte: pendientes, no pagados, cancelados, `reversed` |
| REFRESH | Igual que Revenue |
| CONFIDENCE | ALTA en lo capturado |
| KNOWN LIMITATIONS | Igual que Revenue |

### 2.5 CAC (Customer Acquisition Cost)
| Campo | Valor |
|---|---|
| SOURCE | Marketing Spend + New Customers |
| FORMULA | **Blended CAC** = Spend total ÷ New Customers (mismo mercado y moneda). **Paid CAC por canal** = Spend del canal ÷ New Customers atribuidas a ese canal (last-click first-party, `04_…`) |
| REFRESH | Diario |
| CONFIDENCE | NINGUNA hoy |
| KNOWN LIMITATIONS | Atribución last-click de sesión subestima canales de descubrimiento (Instagram orgánico, influencers); IAB rompe sesiones |
| DATA INCOMPLETE cuando | Falta Spend **o** New Customers |

### 2.6 ROAS
| Campo | Valor |
|---|---|
| SOURCE | Revenue Paid atribuido (Commerce Facts + atribución Woo) ÷ Spend de la plataforma |
| FORMULA | **F360 ROAS** = Σ NP de PS atribuidas (canal / campaña) ÷ Spend del mismo canal / campaña. **Nunca** se usa el ROAS que reporta Meta (DQ-01); si se muestra, va al lado como "ROAS reportado por la plataforma (no verificado)" |
| REFRESH | Diario |
| CONFIDENCE | NINGUNA hoy; MEDIA cuando exista gasto (la atribución first-party es last-click) |
| KNOWN LIMITATIONS | Pedidos sin UTM; IAB; link de pago sin atribución; moneda de la cuenta ≠ moneda del mercado |
| DATA INCOMPLETE cuando | Falta Spend, o moneda distinta sin FX aprobado |

### 2.7 MER (Marketing Efficiency Ratio)
| Campo | Valor |
|---|---|
| SOURCE | Revenue Paid total (todos los canales) ÷ Spend total |
| FORMULA | Σ NP de PS del mercado ÷ Σ Spend del mercado. No depende de atribución |
| REFRESH | Diario |
| CONFIDENCE | NINGUNA hoy; ALTA cuando haya gasto completo |
| KNOWN LIMITATIONS | Incluye ventas de tienda si se elige "omnicanal" (decisión: **PROPUESTA** dos variantes, `MER online` y `MER omnicanal`) |
| DATA INCOMPLETE cuando | Falta Spend; consolidado multi-moneda sin FX |

### 2.8 AOV
| Campo | Valor |
|---|---|
| SOURCE | `commerce_orders` (ya calculado en `f360_commerce_summary`: `aov_product`, `average_order_total`) |
| FORMULA | Σ NP ÷ count(PS) (AOV producto, principal). Promedio por pedido = Σ `order_total` ÷ count(PS) |
| REFRESH | Igual que Revenue |
| CONFIDENCE | ALTA en lo capturado |
| KNOWN LIMITATIONS | Muestra pequeña al inicio; por moneda |

### 2.9 Conversion Rate
| Campo | Valor |
|---|---|
| SOURCE | Numerador: Commerce Facts. Denominador: sesiones GA4 (Data API, propuesta `f360.ga4_daily_sessions`) |
| FORMULA | count(PS online) ÷ sesiones, por día × mercado (× dispositivo cuando sea posible) |
| REFRESH | Diario (GA4 procesa en 24–48 h) |
| CONFIDENCE | NINGUNA hoy; MEDIA con Data API (`CROSS_SOURCE`) |
| KNOWN LIMITATIONS | Mercado en GA4 se deriva de la ruta (`/mx/`, `/co/`) — un solo stream; zona horaria de GA4 = Tijuana; sesiones sin consentimiento |
| DATA INCOMPLETE cuando | Sin sesiones GA4 para el día/mercado |

### 2.10 Repeat Rate
| Campo | Valor |
|---|---|
| SOURCE | PS + clave de clienta + historia |
| FORMULA | (a) **Repeat customer rate** = clientas con ≥ 2 PS (en ventana de 12 m) ÷ clientas con ≥ 1 PS. (b) **Repeat order share** = PS de recurrentes ÷ PS totales del periodo |
| REFRESH | Diario |
| CONFIDENCE | NINGUNA hoy |
| KNOWN LIMITATIONS | Igual que New Customers |
| DATA INCOMPLETE cuando | Historia < ventana |

---

## 3. Qué puede mostrar el cockpit **hoy** (si se construyera con lo que existe)

| KPI | Hoy |
|---|---|
| Revenue Paid, Paid Orders, AOV | Sí, por moneda, **con banner** "online desde 2026-10-08; tienda solo ventas registradas en Fuxia 360" |
| Marketing Spend, CAC, ROAS, MER | DATA INCOMPLETE (sin gasto) |
| New Customers, Repeat Rate | DATA INCOMPLETE (sin historia) |
| Conversion Rate | DATA INCOMPLETE (sin GA4 API) |
| Ventas por canal / campaña (sin gasto) | Sí, en cuanto exista la vista de canal (G1 de `09_…`) |

---

## 4. Diseño de la respuesta del RPC (propuesta)

`public.f360_growth_cockpit(p_from date, p_to date, p_market text, p_filters jsonb)` → `jsonb`:

```
{ kind: 'ACTUAL', period, market,
  kpis: [ { key: 'revenue_paid', currency: 'MXN', value: 12345, prev: 11000,
            status: 'OK' | 'DATA_INCOMPLETE', missing: ['marketing_spend'], quality: 'VERIFIED|PARTIAL|…',
            source: 'commerce_facts', coverage: { from: '2026-10-08', note: '…' } }, … ],
  breakdowns: { by_channel: [...], by_campaign: [...], by_product: [...] },
  sources: [ { key: 'woo_production', freshness }, { key: 'meta_ads', freshness: 'NOT_CONNECTED' }, { key: 'ga4', freshness: 'NOT_CONNECTED' } ] }
```

- `status = 'DATA_INCOMPLETE'` → `value = null` (nunca 0).
- Sin PII, sin filas por pedido.
- `require_role('operator')`.
