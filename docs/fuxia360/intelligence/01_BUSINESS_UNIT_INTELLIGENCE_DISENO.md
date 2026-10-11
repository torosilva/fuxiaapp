# Business Unit Intelligence · Rentabilidad por línea de negocio (diseño)

> 2026-10-11 · rama `fuxia-360` · pedido de Mario: integrar **inteligencia por unidad de negocio** al Centro de Inteligencia, Growth, CEO Cockpit y Estrategia, sin duplicar datos ni crear un sistema financiero paralelo.
> **Solo diseño.** No se creó ninguna migración ni código. No se tocó producción, staging, WooCommerce ni ninguna integración.
> Las cifras salen de consultas de **solo lectura** a producción hechas hoy (`scripts/f360/prod_read.sh`), solo agregados y sin datos personales.
> Este documento **extiende** `00_CENTRO_DE_INTELIGENCIA_DISENO.md`, con la misma capa de RPC, el mismo analista y las mismas tablas de gobierno. Sus sprints (BU0–BU6) van **después de I4** y no cambian lo que I0–I4 están construyendo.

---

## 0. Resumen para Mario (en simple)

**Qué es esto.** Hoy Fuxia 360 sabe cuánto se vende y cuánto inventario hay. Lo que pides es ver **cada línea (Ballerinas, Botas, Sandalias, Fuxia Kids) como si fuera un negocio**: cuánto vende, cuánto deja, cuánto dinero tiene amarrado en inventario y dónde conviene invertir el siguiente peso.

**Cómo se hace sin duplicar.** No se copia ninguna venta. Se agrega una **etiqueta versionada a cada modelo**: "este modelo pertenece a la línea X desde tal fecha". Todo lo demás se lee de donde ya vive:
- ventas: Commerce Facts y ventas de tienda;
- costo: `product_cost_versions`;
- inventario: el ledger;
- gasto: Meta;
- gastos fijos: el cierre mensual.

Lo que no tenga línea aparece como **"Sin línea asignada"**. Nunca se esconde.

**Lo que encontré hoy (producción, 11-oct):**

| Hecho | Número |
|---|---|
| Modelos con categoría | **72 de 72 (100%)**: Ballerinas 32, Sandalia Alta 24, Sandalia Plana 13, Botas 3 |
| "Sandalias" es **una línea** pero son **dos categorías** de Woo | `sandalia-plana` + `sandalia-alta` |
| **Fuxia Kids** | **No existe** en ningún lado: 0 modelos, 0 categoría, 0 ventas, 0 inventario |
| Ventas medidas que sí caen en una línea | **México 91.5%** del dinero (MXN 152,006 de 166,090) · **Colombia 94.8%** (COP 7,631,300 de 8,051,300) · resto del mundo 100% (USD 450) |
| Ventas **sin línea** | 6 pedidos Woo con SKU viejo o sin SKU (MXN 11,284 + COP 420,000) y la venta a distancia (MXN 2,800, texto libre) |
| Ventas de tienda viejas (18-may → 10-oct, fuera de la medición) | 36 ventas, **MXN 157,900**, **0% asignable formalmente** (solo traen el nombre del modelo en texto) |
| Inventario por línea (ledger F360) | Ballerinas **603** pares · Botas **24** · Sandalias **18** · Kids **0** (total 645) |
| Inventario a precio de venta | MXN 1,843,000 (Ballerinas 1,688,400 · Botas 100,800 · Sandalias 53,800) |
| **Costo por modelo** | **0 registros**, así que **no hay margen, COGS ni inventario a costo de ninguna línea** |
| Gastos fijos (cierre) | **0 capturas**, así que **no hay EBITDA estimado de ninguna unidad** |
| Gasto en Meta (jun–oct) | MX $38,063 · CO $28,871 (ambos en MXN). **Ninguna campaña es de una sola línea**: todo el gasto es compartido y necesita una regla de reparto |
| Botas | 0 ventas medidas desde junio y 24 pares en inventario (las tiendas viejas sugieren unas 4 ventas por nombre; sin verificar) |

**En una frase:** hoy se puede mostrar **venta e inventario por línea** con un 91–95% de cobertura. **Rentabilidad por línea no**: faltan costos (Carolina), gastos de cierre (contadora) y reglas de reparto (contadora + tú).

### Decisiones que necesito de ti

1. **Lista de líneas.** ¿Confirmas Ballerinas, Botas, Sandalias (= Sandalia Plana + Sandalia Alta) y Fuxia Kids?
2. **Unidades con P&L.** ¿Cada línea es su propia unidad con P&L, o, por ejemplo, "Adulto" (Ballerinas + Botas + Sandalias) es una unidad y **Kids otra**? Recomiendo **dos unidades: Fuxia Adulto y Fuxia Kids**, con las 3 líneas adultas como líneas comerciales. Así no se reparten gastos fijos entre líneas que comparten la misma tienda, el mismo equipo y la misma marca, y Kids, que sí tendrá costos propios, se mide aparte.
3. **Regla de reparto del gasto de Meta compartido.** Recomiendo empezar **por participación en la venta neta en línea del mismo mercado y mes**. La contadora la valida y tú la apruebas.
4. **Regla de reparto de gastos fijos** (renta, nómina, tecnología): ¿por venta neta, por pares o por inventario? Lo propone la contadora y lo apruebas tú. Mientras no exista, **no se muestra EBITDA estimado**.
5. **Fuxia Kids:**
   - quién da cada número del Business Case (ver §7: desarrollo, costo por par, precios, curva de tallas, profundidad, marketing de lanzamiento);
   - qué umbrales usarás para **escalar, ajustar o detener**. Se fijan **antes** del lanzamiento.
6. **Registro de iniciativas de Growth.** Hoy no existe (ni en el repo ni en producción). ¿Lo creamos como parte de esto (BU4)?
7. **Contadora en el sistema.** Hoy hay 2 dueñas y 3 vendedoras, sin usuario de contadora. Hay que confirmar su alta con la capacidad limitada que construye I1.

---

## 1. Diagnóstico de datos existentes

### 1.1 Producto y clasificación

| Hallazgo | Evidencia | Consecuencia |
|---|---|---|
| Existen **4 categorías**, que son las de Woo: `ballerinas`, `sandalia-plana`, `sandalia-alta`, `botas` | `supabase/migrations/20260926000100_f360_p21_product_master.sql:12-19` (tabla + INSERT) | Son configuración **de la tienda**, no de negocio. No se modifican. |
| Cada modelo tiene `category_key` (FK a `f360.categories`) | `…p21_product_master.sql:29` | **72/72 modelos clasificados**: 32 Ballerinas (4 archivadas), 24 Sandalia Alta, 13 Sandalia Plana, 3 Botas. |
| Columna vieja `products.category` (texto) | `20260925010000_f360_admin_v1_inventory_core.sql:32` | **Vacía** en los 72. No se usa. |
| Ligas categoría → Woo | `20260927010000_f360_p22_woo_publishing.sql:29-35` (`woo_category_links`) | 4 ligas en producción. |
| Variantes por categoría | prod | 1,050 variantes: Ballerinas 738, Sandalia Alta 174, Sandalia Plana 108, Botas 30 |
| Precios de lista (MXN, `products.regular_price`) | prod | Ballerinas 2,800 · Sandalia Plana 2,800 · Sandalia Alta 3,000 · Botas 4,200–4,500. Ningún modelo tiene `sale_price`. Precios COP: 56 modelos; USD: 67 (`f360.product_prices`). |
| `tier` (A/B/C) | `…inventory_core.sql:35` | Vacío en los 72. |
| **Kids** | búsqueda en nombres (`kid`, `niñ`, `mini`), categorías y docs | **0 coincidencias.** Kids es una línea **planeada**: no tiene catálogo, ventas ni inventario. |
| Otra taxonomía en el modelo de crecimiento: "Zapatos / Accesorios" | `admin-web/src/lib/growth-model.ts:51` (`shoes_pct`, `accessories_pct`) | **Contradicción menor:** no existen accesorios en el catálogo. Ver §10. |

### 1.2 Ventas: ¿llegan a un modelo y, por tanto, a una línea?

La vista de líneas `f360.commerce_order_lines` (`20261008000300_f360_g2_identity_resolution.sql:74-98`) ya resuelve cada línea Woo a su variante y modelo canónicos mediante la identidad de canal, y cada línea de tienda F360 a su variante. **Ya trae `category_key`**, así que el "puente" a la línea de negocio ya existe.

**Verificación de que la suma por línea cuadra con el pedido:** en México (Woo), la suma de `net` de las líneas pagadas es **MXN 120,890**, igual a `commerce_orders.net_product` del mismo conjunto (prod, 11-oct). Los cupones ya vienen repartidos por línea en Woo (`line.total`). Esto permite usar el **renglón del pedido** como unidad mínima sin diferencias.

**Cobertura por fuente (pedidos pagados `countable`, jun → 11-oct):**

| Fuente | Mercado / moneda | Pedidos | Pares | Venta neta | Con línea | Sin línea | Cobertura (dinero) |
|---|---|---:|---:|---:|---:|---:|---:|
| Woo | MX / MXN | 35 | 50 | 120,890 | 109,606 | 11,284 (5 pares) | **90.7%** |
| Tienda F360 (desde 8-oct) | MX / MXN | 7 | 15 | 42,400 | 42,400 | 0 | **100%** |
| Venta a distancia (`remote_sales`) | MX / MXN | 1 | 1 | 2,800 | 0 | 2,800 | **0%** |
| **Total México medido** | MXN | 43 | 66 | **166,090** | **152,006** | 14,084 | **91.5%** |
| Woo | CO / COP | 17 | 22 | 8,051,300 | 7,631,300 | 420,000 (1 par) | **94.8%** |
| Woo | ROW / USD | 1 | 3 | 450 | 450 | 0 | **100%** |
| Tiendas viejas (`public.offline_sales` sin RPC) | MX / MXN | 36 | 52 | 157,900 | — | 157,900 | **0% formal** |

Por qué queda venta sin línea:
- **Woo sin línea:** las líneas tienen el SKU viejo `BALL-PNT-TCH-NGO` o vienen sin SKU (`product_resolution = 'unresolved'`). Se arregla homologando ese SKU en la identidad de canal, que ya existe. No hace falta tocar Woo.
- **Venta a distancia:** `f360.remote_sales` guarda `product_name` en **texto libre**, sin variante ni modelo (`20261019000100_f360_remote_sales.sql:25`). Además, esa fuente **no aparece en `commerce_order_lines`** (solo en `commerce_orders`): el pedido existe, pero no tiene renglones.
- **Tiendas viejas:** `public.offline_sales.items` (jsonb) solo trae `product_name`, `color`, `size`, `quantity`, `unit_price` e `inventory_id` de la app vieja. **Diagnóstico de cobertura, no regla:** si se compara el nombre del modelo con el catálogo, 28 de 44 renglones coinciden (Ballerinas MXN 85,800 / 31 pares; Botas MXN 18,000 / 4 pares) y 16 no (MXN 54,100 / 17 pares). La asignación real se hará con la homologación de P0E, revisada por Carolina, **nunca por coincidencia automática de nombres**.
- **Diferencia de conteo que no es error:** en la medición, una venta de tienda marcada "a distancia" cuenta como **canal en línea** pero conserva su **ubicación** (tienda). Por eso "México en línea" de octubre (MXN 5,600) son 1 venta a distancia + 1 venta de tienda marcada a distancia. **En octubre no hay pedidos Woo pagados.**

### 1.3 Inventario

| Hecho | Evidencia |
|---|---|
| 645 pares en `f360.inventory_balances`; el ledger cuadra con los saldos | `docs/fuxia360/ops/INVENTARIO_CONCILIACION_2026-10-11.md` §1 |
| Por línea: Ballerinas 603 (26 modelos con existencia) · Botas 24 (2 modelos) · Sandalia Alta 17 + Sandalia Plana 1 = **Sandalias 18** (11 modelos) | prod, 11-oct |
| Por ubicación y línea: Polanco 193/7/13 (Ballerinas/Botas/Sandalias) · Bodega 162/10/2 · San Jerónimo 94/4/1 · Amsterdam 92/0/0 · La Noria 60/3/2 · En camino 2/0/0 | prod |
| **179 pares de la app vieja nunca migrados** (Contreras 153, Monterrey 19, Guadalajara 5, Polanco legacy 2) | conciliación §1 |
| **No hay conteo físico aprobado** | conciliación §1 |
| El ledger empieza el **3-oct** (cargas de arranque) | conciliación §1 |

Consecuencias para la inteligencia por línea:
- "Inventario por línea" = **saldo del ledger F360**, no conteo físico. Se etiqueta así.
- **Antigüedad del inventario: no se puede calcular hoy.** La fecha del primer movimiento es la de captura (3–8 oct), no la de compra o llegada. Hace falta un dato nuevo: **fecha de llegada o lote por modelo** (Carolina) o el conteo con fecha.
- **Sell-through y rotación por línea: INCOMPLETO.** El historial de ventas empieza en junio (Woo) y el inventario el 3-oct; mezclarlos sobreestima la salida. La fórmula solo será válida con un periodo en que ventas e inventario convivan (desde el 3-oct) o con un inventario inicial reconstruido.

### 1.4 Costos, gastos y gobierno

| Objeto | Existe | Filas en prod | Nota |
|---|---|---:|---|
| `f360.product_cost_versions` (costo por modelo, variante opcional, mercado opcional; versionado; propuesto → aprobado) | `20261014000400_f360_sg0_product_cost.sql:14-37` | **0** | Proponer: operator+ (`:63`). Aprobar: owner. Leer: operator+ (`:109`). Fuentes: `supplier_invoice`, `production_order`, `accounting`, `owner_estimate`, `other`. |
| `f360_board.monthly_close_entries` + `close_accounts` (cogs, opex_rent, opex_payroll, opex_tech, opex_logistics, opex_other, cash_*, tax_paid) | `20261015000200_f360_board_sb0_finance_foundation.sql:123-170` | **0** | `dimension_key` (texto libre validado, `:149`) permite separar un monto por dimensión **sin cambiar la tabla**. |
| `f360_board.metric_catalog` | `…finance_foundation.sql:243-279` | 22 métricas | Ya define `ebitda` como "solo si COGS y OPEX del mismo mes están cerrados" (`:269`). La versión por unidad tiene que ser **otra métrica** ("EBITDA estimado"), no esa. |
| `f360_board.budget_versions/lines` con `dim_category_key → f360.categories` | `…finance_foundation.sql:281-306` | 0 | Presupuestar "Sandalias" requiere 2 renglones (plana + alta), y **Kids no se puede presupuestar** porque no hay categoría. Ver §2.6. |
| `f360.marketing_spend_daily` | `20261014000200_f360_sg0_marketing_spend.sql:81-89` | Meta desde 1-may (API) | `platform` ya admite `tiktok` (`:19, :47`). Hay **35 campañas, ninguna de una sola línea**: los nombres son por mes, mercado y objetivo ("Agosto copia de Julio_Ventas", "MX \| VENTAS \| PROSPECTING \| ADVANTAGE+", "Colombia Catálogo Advantage+"…). |
| `f360.approval_scopes` (fx_rate \| budget \| close) | `20261024000100_f360_fx_daily.sql` (I0, **en construcción** por la sesión principal) | — | El CHECK de `scope` es una lista cerrada. Para BU se necesitan scopes nuevos, ampliando el CHECK en BU0 después de I4 (cambio aditivo). |
| Iniciativas / experimentos de Growth | — | — | **No existe ninguna tabla.** `growth/06_EXPERIMENTS.md` propone `f360.growth_experiments`. `strategy-board/05_FIVE_YEAR_PLAN.md` §3 propone `plan_initiatives`, que **no está** en la migración de plan (`20261015000300…:282-330` solo crea `plan_versions`, `plan_years`, `plan_revisions`). |
| Escenarios y compuertas (Scenario Lab, Strategic Gates) | specs `04`, `06` | — | **No implementados.** El Business Case de Kids se diseña para vivir ahí cuando existan (§7.6). |
| Comisión de pasarela por pedido | — | — | **No existe.** `commerce_woo_orders.fees_total` (`20261008000100…:39`) son cargos de Woo, no comisiones de Mercado Pago o ePayco. |
| Costo real de envío | — | — | No existe. Solo existe lo cobrado a la clienta (`shipping`, MXN 400 en MX). |
| Usuarios | `f360.user_roles` | 2 owner, 3 seller, **0 operator**, 0 contadora | — |

---

## 2. Modelo conceptual de unidades de negocio

### 2.1 Tres conceptos que no se deben mezclar

| Concepto | Qué es | Ejemplos | ¿Recibe gastos repartidos y EBITDA estimado? |
|---|---|---|---|
| **Categoría de tienda** (ya existe) | Cómo se navega la tienda en línea. Pertenece a Woo y al catálogo. | `sandalia-plana`, `sandalia-alta` | No. **No se toca.** |
| **Línea comercial** (nueva) | Cómo Fuxia **piensa y vende** su producto. Cada modelo pertenece a **exactamente una** en cada fecha. | Ballerinas, Botas, Sandalias, Fuxia Kids | **No**: llega hasta **margen de contribución**. |
| **Unidad con P&L** (nueva) | Agrupa una o más líneas que justifican su propio estado de resultados (equipo, inversión o riesgo propios). | Recomendado: **Fuxia Adulto** (Ballerinas + Botas + Sandalias) y **Fuxia Kids** | **Sí**: solo aquí se reparten gastos compartidos y se calcula el **EBITDA estimado**. |

¿Por qué separar línea y unidad? Repartir la renta de Polanco entre Ballerinas y Botas produce un número que **parece** preciso pero solo refleja la regla elegida. A nivel línea, la pregunta útil es **"¿cuánto aporta?"** (contribución). A nivel unidad, la pregunta es **"¿se sostiene sola?"** (EBITDA estimado). Si Mario decide que cada línea sea su propia unidad, el modelo lo admite: es configuración, no código.

### 2.2 Objetos propuestos (todos aditivos; ninguno copia hechos)

**En `f360` (clasificación operativa, visible a operator+ y sin dinero):**

| Objeto | Propósito | Columnas clave | Reglas |
|---|---|---|---|
| `f360.business_lines` | Catálogo de líneas comerciales | `key` (`ballerinas`, `botas`, `sandalias`, `kids`), `name`, `status` (`planned` \| `active` \| `retired`), `launch_date`, `sort` | Alta y cambio solo por RPC owner. Nunca se borra; se retira. |
| `f360.business_line_rules` | **Asignación versionada** modelo → línea | `id`, `scope_type` (`category` \| `product`), `category_key` o `product_id`, `line_key`, `effective_from`, `effective_to`, `status` (`proposed` \| `approved` \| `rejected`), `reason`, `proposed_by(_name)`, `approved_by(_name)`, `approved_at` | Mismo patrón que `product_cost_versions`: no se edita, no se borra; aprobar cierra la versión anterior del mismo alcance; sin traslapes; **quien propone no puede aprobar**. |
| `f360.business_line_of(product_id, fecha)` | Resolución única | — | 1) regla de **modelo** aprobada vigente en la fecha; 2) si no hay, regla de **categoría** aprobada vigente; 3) si no hay, **`SIN_LINEA`**. Función `STABLE`, sin escritura. |
| `f360.v_product_business_line` | Foto actual (para pantallas) | `product_id`, `line_key`, `via` (`product_rule` \| `category_rule` \| `none`) | Vista. |
| `f360.sale_line_product_links` | Vincula a un modelo los renglones que **no traen variante** (venta a distancia, tienda vieja ya importada en P0E) | `fact_ref` (`remote_sale:<id>`, `legacy_store_sale:<id>:<n>`), `product_id`, `variant_id` opcional, `reason`, `linked_by`, `approved_by` | Append-only; una corrección es una fila nueva que reemplaza a la anterior. **No modifica `remote_sales` ni `offline_sales`.** |

**Reglas iniciales propuestas** (las aprueba Mario en BU0):
- `ballerinas` → Ballerinas;
- `botas` → Botas;
- `sandalia-plana` y `sandalia-alta` → Sandalias;
- Kids: se crea en estado `planned`, sin reglas. Cuando Carolina dé de alta los modelos Kids, cada modelo se asigna con una regla de **modelo**. Si más adelante se crea una categoría `kids` en la tienda (por el flujo normal), se agrega su regla de categoría.

**En `f360_board` (financiero, solo consejo con scope FINANCIAL + MFA, o la contadora en su alcance):**

| Objeto | Propósito |
|---|---|
| `f360_board.pnl_units` | Unidades con P&L (`adulto`, `kids`) + `status`. |
| `f360_board.pnl_unit_lines` | Línea → unidad, **versionado con vigencia** (Kids nace en su propia unidad). |
| `f360_board.allocation_policies` + `allocation_policy_versions` | Reglas de reparto: bolsa de costo, generador (driver), parámetros, vigencia, estado (`draft` → `validated` por la contadora → `approved` por Mario \| `rejected`), motivo. Append-only. |
| `f360_board.cost_rate_assumptions` | Supuestos de costo variable sin fuente transaccional (comisión de pasarela %, costo de envío por pedido, empaque por par), por mercado y vigencia, con `basis` (`contrato`, `factura_muestra`, `estimacion`) y aprobación. Todo lo que salga de aquí se etiqueta **ESTIMADO**. |
| `f360_board.campaign_line_tags` | Campaña de Meta/TikTok → una o varias líneas (con peso explícito), versionado. Sin etiqueta, la campaña es **compartida**. |
| `f360_board.allocation_runs` + `allocation_results` | Ejecución de reparto de un mes: insumos (hash), versiones de política usadas, resultado por `unidad × mercado × moneda × bolsa`. Inmutable; repetir la corrida crea una **nueva** que sustituye a la anterior. |
| `f360_board.business_cases` + `business_case_versions` | Business Case de líneas nuevas (Kids). Ver §7. |
| `f360.growth_initiatives` + `growth_initiative_lines` | Registro de iniciativas y sus líneas (§2.7). Va en `f360` porque Growth lo opera con rol operator+; **sin montos de costo**. |

### 2.3 Cómo llega cada hecho a una línea (y a una unidad)

| Hecho | Fuente única (no se copia) | Llave hacia la línea | Si no resuelve |
|---|---|---|---|
| Venta online (renglón Woo) | `f360.commerce_order_lines` (source `woo`) + `commerce_orders` (estado, fecha, mercado) | `product_id` → `business_line_of(product_id, fecha de pago)` | `SIN_LINEA`, a la bandeja "Resolver identidad" (homologar SKU) |
| Venta de tienda F360 | `commerce_order_lines` (source `f360_store`) | `variant_id → product_id` | Imposible hoy: la RPC exige variante |
| Venta a distancia | `commerce_orders` (source `f360_remote`) + `sale_line_product_links` | vínculo manual aprobado | `SIN_LINEA` (hoy 1 venta) |
| Venta de tienda vieja | `measurement_sales` (legacy, tras P0E) + `sale_line_product_links` | vínculo aprobado por Carolina | `SIN_LINEA` (hoy 36 ventas, fuera de la medición) |
| Resúmenes históricos (bazares) | `f360.historical_sales_active` | No tienen producto | **Siempre** `SIN_LINEA`, salvo que se capturen por línea |
| COGS | `product_cost_effective` (vigente en la fecha de la venta, del modelo, variante o mercado más específico) × pares del renglón | la línea del renglón | Renglón **sin costo**: COGS de la línea INCOMPLETO, con % de cobertura |
| Inventario | `inventory_balances` (sin tránsito, como `metric_catalog`) | `variant → product → línea` | — (hoy 100% del inventario tiene línea) |
| Inventario a costo | balances × costo vigente hoy | ídem | Sin costo: INCOMPLETO |
| Gasto de marketing | `marketing_spend_daily` | `campaign_line_tags` (directo) o política `marketing_shared` (repartido) | Sin etiqueta y sin política: "gasto compartido sin repartir", que se muestra **solo en el total** |
| Gastos fijos del mes | `monthly_close_entries` | `dimension_key = 'bu:<unidad>'` (directo a la unidad) o `''`/total (compartido, se reparte por política) | Sin política: la unidad se queda en **contribución**; no hay EBITDA estimado |
| Comisiones y envío real | `cost_rate_assumptions` (tasa aprobada) × base | la línea del renglón | Sin tasa: FALTA |

**"Sin línea asignada" es una línea más en todas las pantallas.** Suma al total, se muestra con su monto y su % y tiene un botón "resolver" que lleva a la bandeja. Las pruebas exigen que **Σ líneas + Sin línea = total de Commerce Facts** del mismo filtro.

### 2.4 Grano, medidas y anti-doble conteo

**Grano de hechos de venta:** `renglón de pedido × variante × día de negocio (CDMX) × ubicación × canal × mercado × moneda`. Es la vista `f360.v_bu_sales_lines`, que **lee y no copia**: une `commerce_order_lines` y `commerce_orders` y agrega `line_key`, la unidad y el costo vigente.

| Medida | ¿Se puede sumar entre dimensiones? | Regla |
|---|---|---|
| Pares, venta bruta, descuento, venta neta, COGS, contribución | **Sí** (dentro de una moneda) | Se suman renglón por renglón; nunca se suman monedas distintas. |
| Envío cobrado, cargos del pedido | Sí, pero **a nivel pedido** | No se reparten a renglones; van a "otros ingresos del pedido" de la unidad (por el mercado del pedido). |
| Margen %, ticket promedio, rotación, sell-through, ROAS/MER, precio promedio | **No** | Se recalculan desde sus sumas en cada corte, nunca se promedian. |
| Inventario (pares, a costo) | **No es aditivo en el tiempo** | Es un saldo: se toma al cierre o a la fecha y nunca se suma entre meses. Sí se suma entre ubicaciones y líneas. |
| Gasto repartido, gasto fijo repartido | Sí, **solo en el nivel en que se repartió** | Ver abajo. |

**Reglas anti-doble conteo:**
1. **Un renglón pertenece a una sola línea** en su fecha, porque la resolución es una función determinista con vigencias que no se traslapan.
2. **Cada dimensión tiene un solo valor por renglón:** un canal, una ubicación, un mercado. El caso "venta de tienda marcada a distancia" es canal = en línea y ubicación = Polanco. En la vista **por canal** aparece en "en línea"; en la vista **por ubicación**, en Polanco. Nunca en dos canales.
3. **El reparto se hace una vez, en un solo nivel:** `unidad con P&L × mercado × mes`. **No se baja** a canal, tienda, modelo ni talla. Al hacer drill-down debajo de la unidad, la pantalla muestra hasta **margen de contribución** y oculta las filas de gastos repartidos, con la leyenda "los gastos compartidos se reparten solo a nivel unidad".
4. **Gasto de marketing:** cada fila de `marketing_spend_daily` va a **uno** de dos destinos:
   - **directo:** campaña etiquetada a una o varias líneas, con pesos que suman 100%;
   - **bolsa compartida:** se reparte con la política vigente.

   La corrida guarda qué filas consumió (`import_id + row_no`), y una prueba verifica que Σ repartido + Σ directo = Σ gasto del mes y mercado.
5. **Iniciativas de Growth:** una venta puede pertenecer a varias iniciativas que se traslapan (por ejemplo, "TikTok Shop MX" y "Campaña Día de las Madres"). Por eso **las iniciativas no se suman entre sí**. La pantalla lo dice ("las iniciativas pueden traslaparse; el total del negocio está en Unidades").
6. **Históricos:** se aplica la regla de `f360_exec_dashboard` (un periodo histórico no se suma con pedidos del mismo periodo), heredada de `02_MEASUREMENT_TRUTH.md` §3.
7. **Devoluciones y cambios:** Fuxia opera con cambios. Un reembolso con detalle de renglón se descuenta de su renglón. Sin detalle, se reparte pro rata a la venta neta de los renglones del pedido (política `refund_split_v1`, documentada). Un cambio no altera la venta original (G1B §8).

### 2.5 Moneda

Igual que I0 y `02_MEASUREMENT_TRUTH.md` §2.5:
- **la vista principal es en moneda original;**
- el consolidado MXN usa solo `fx_rate_for_report` con tasa **aprobada** y muestra la tasa usada;
- los pedidos con moneda sospechosa sin conciliar (por ejemplo, el #2095) quedan "excluidos del consolidado".

**Caso especial de contribución en Colombia:** el gasto de Meta CO se paga en **MXN** y la venta es en **COP**. La contribución de una línea en CO **requiere** tipo de cambio aprobado; sin él, el renglón de gasto aparece en MXN junto al COP, sin restar ("INCOMPLETO: falta tipo de cambio").

### 2.6 Presupuesto, plan y escenarios por línea (sin romper I1)

- `budget_lines.dim_category_key` sigue como está. **Propuesta aditiva (BU1, después de I4):** columna nula `dim_business_line_key → f360.business_lines(key)`, con CHECK "no ambas". Así se puede presupuestar "Sandalias" o "Kids" sin inventar categorías.
  - **Coordinar con I1**, que está construyendo versiones de presupuesto. Si I1 ya expone `dim_category_key` en su RPC, el contrato no cambia: se agrega un parámetro opcional.
- `plan_years.category_targets` (spec `05` §3) ya prevé "categorías nuevas como etiqueta". Se usa `line_key` como etiqueta.

### 2.7 Iniciativas de Growth ↔ líneas

`f360.growth_initiatives`:
- `code`, `name`, `market`, `status` (`idea`, `active`, `paused`, `closed`), `owner_name`, `start_date`, `end_date`, `hypothesis`;
- **alcance** (`scope jsonb` validado), que es lo que define qué ventas y qué gasto "son" de la iniciativa:
  - `{channel_keys[], sales_target_keys[], utm_campaigns[], spend_campaign_ids[], locations[], date_window}`.

`f360.growth_initiative_lines`: `(initiative_id, line_key)`. Ejemplo: TikTok Shop México → Ballerinas + Sandalias.

**Resultados por iniciativa × línea** = renglones que cumplen el alcance **y** pertenecen a la línea, más el gasto de las campañas del alcance. Se muestran:
- venta, pares y contribución (cuando haya costo);
- gasto directo, MER y CPA;
- rotación del inventario de esas líneas en el periodo.

Las líneas asociadas que **no** venden en la iniciativa se muestran en 0, con "sin ventas en el alcance".

**TikTok Shop no existe hoy.** Para medirlo hace falta una fuente de pedidos (sales target o canal propio) y gasto con `platform = 'tiktok'`, que ya está permitido. Sin esa fuente, la iniciativa existe pero sus resultados dicen **FALTA fuente de ventas**.

`growth_experiments` (spec 06) se liga opcionalmente a una iniciativa (`initiative_id`). No se duplica.

---

## 3. Diccionario financiero y fórmulas

**Convenciones:**
- todo por `unidad o línea × mercado × moneda original × periodo`;
- "renglones" = renglones `countable` de `v_bu_sales_lines`.

**Etiquetas:**

| Etiqueta | Significado |
|---|---|
| **REAL** | Todos los insumos son hechos confirmados: venta pagada, costo aprobado con fuente transaccional (`supplier_invoice`, `production_order`, `accounting`) y cierre aprobado. |
| **ESTIMADO** | Usa al menos un costo `owner_estimate`, una tasa de `cost_rate_assumptions`, un reparto o una tasa FX provisional. |
| **INCOMPLETO** | Falta al menos un insumo. Se muestra el dato parcial con "falta X (de quién)", o **no se muestra cifra** si el faltante es material (umbral propuesto: cobertura < 95% del insumo). |

**Siempre "EBITDA estimado por unidad".** Nunca "EBITDA" a secas.

| # | Métrica | Fórmula | Fuente | Etiqueta máxima posible |
|---|---|---|---|---|
| 1 | Venta bruta | Σ `gross` (subtotal antes de cupones) | `commerce_order_lines` | REAL |
| 2 | Descuentos | Σ (`gross − net`) | ídem | REAL |
| 3 | Devoluciones / reembolsos | Σ reembolso de producto asignado al renglón (§2.4 regla 7) | `commerce_woo_refunds` | REAL (detalle) / ESTIMADO (pro rata) |
| 4 | **Venta neta** | 1 − 2 − 3 | — | REAL. **IVA:** se muestra como se cobró hasta que la contadora defina el tratamiento (`20261016000200_f360_sg0_tax_pending.sql`). |
| 5 | COGS | Σ pares × costo vigente en la fecha de la venta (variante > modelo; mercado > sin mercado) | `product_cost_effective` | REAL si todo el costo es transaccional; ESTIMADO si hay `owner_estimate` |
| 5a | Cobertura de costo | pares con costo ÷ pares vendidos | — | (calidad) |
| 6 | Utilidad bruta | 4 − 5 | — | hereda |
| 7 | Margen bruto % | 6 ÷ 4 | — | no aditiva |
| 8 | Costos comerciales variables | comisión pasarela (tasa × base) + envío no cobrado + empaque + comisión de marketplace + **marketing directo** (campañas etiquetadas) | `cost_rate_assumptions`, `campaign_line_tags` | ESTIMADO (tasas); REAL (marketing directo) |
| 9 | **Margen de contribución** | 6 − 8 | — | hereda; **es el último renglón por línea, canal, tienda, modelo y talla** |
| 10 | Margen de contribución % | 9 ÷ 4 | — | no aditiva |
| 11 | Marketing compartido repartido | bolsa compartida (mercado, mes) × driver de la unidad ÷ Σ driver | `allocation_results` | ESTIMADO |
| 12 | Gastos operativos directos | `monthly_close_entries` con `dimension_key = 'bu:<unidad>'` | cierre | REAL si el mes está cerrado |
| 13 | Gastos compartidos repartidos | cuentas opex con `dimension_key = ''` × política | cierre + `allocation_results` | ESTIMADO |
| 14 | **EBITDA estimado por unidad** | 9 − 11 − 12 − 13 (+ otros ingresos del pedido: envío cobrado) | — | **Siempre ESTIMADO o INCOMPLETO**, aunque todos sus insumos sean reales, porque contiene repartos. Solo a nivel unidad × mercado × mes (o la suma de meses). |
| 15 | Margen EBITDA estimado | 14 ÷ 4 | — | no aditiva |
| 16 | Inventario en pares | Σ `on_hand` (sin tránsito) a la fecha | `inventory_balances` | REAL (ledger, no conteo físico; leyenda) |
| 17 | Inventario a costo | Σ pares × costo vigente a la fecha | ídem + costo | según costo |
| 18 | Inventario a precio de venta | Σ pares × `regular_price` | ídem | REAL (rótulo "no es costo") |
| 19 | Rotación (veces) | COGS del periodo ÷ inventario a costo **promedio** del periodo (inicio + fin) / 2 | — | INCOMPLETO hasta tener costo e inventario inicial |
| 19b | Días de inventario | días del periodo ÷ rotación | — | ídem |
| 20 | Sell-through | pares vendidos ÷ (pares vendidos + pares disponibles al final), en el **mismo periodo y ubicaciones** | ledger + ventas | INCOMPLETO si el periodo empieza antes del 3-oct-2026 |
| 21 | Antigüedad del inventario | Σ pares × días desde llegada ÷ Σ pares (y buckets 0–90, 91–180, 181–365, >365) | **requiere fecha de llegada o lote** (no existe) | FALTA |
| 22 | Capital invertido en inventario | = 17 (a la fecha) | — | según costo |
| 23 | **Retorno sobre inversión en inventario (GMROI)** | utilidad bruta del periodo (anualizada si se indica) ÷ inventario a costo promedio | — | según costo |
| 24 | Capital amarrado de riesgo | inventario a costo de variantes con 0 ventas en N días (N lo fija Mario; propuesta 90) | — | según costo |
| 25 | Crecimiento | venta neta del periodo ÷ mismo periodo anterior − 1, por moneda | — | REAL; "sin base" si el anterior < umbral |
| 26 | MER por línea (solo marketing directo) | venta neta de la línea ÷ marketing directo de la línea | — | REAL / INCOMPLETO |

**Registro en el vocabulario único:** se agregan al `f360_board.metric_catalog` (sin tocar las existentes) llaves como `bu_revenue_net`, `bu_cogs`, `bu_contribution`, `bu_contribution_pct`, `bu_ebitda_estimated`, `bu_inventory_cost`, `bu_gmroi`, `bu_sell_through`, `bu_inventory_age`, con `availability` calculada. **`ebitda` sigue reservado** para el EBITDA de empresa con cierre (definición actual, `:269`).

---

## 4. Matriz de disponibilidad de datos (hoy, por métrica y línea)

Estados: **DISPONIBLE** · **PARCIAL** (con aviso) · **FALTA** (no se muestra cifra).

| Métrica | Ballerinas | Botas | Sandalias | Kids | Qué falta y de quién |
|---|---|---|---|---|---|
| Venta bruta / descuentos / neta | **PARCIAL** | **PARCIAL** (0 ventas medidas) | **PARCIAL** | **FALTA** (no existe) | Homologar 2 SKUs viejos (Carolina/sistema); vincular la venta a distancia (Carolina); P0E tiendas viejas (Carolina) |
| Devoluciones | DISPONIBLE (0 reembolsos) | ídem | ídem | — | — |
| COGS / utilidad bruta / margen bruto | **FALTA** | **FALTA** | **FALTA** | FALTA | **Costo por modelo** (Carolina propone, owner aprueba) |
| Costos comerciales variables | **FALTA** | FALTA | FALTA | FALTA | Tasa de comisión Mercado Pago / ePayco / terminal (Carolina, con contrato); costo de envío y empaque (Carolina); validación (contadora) |
| Marketing directo por línea | **FALTA** | FALTA | FALTA | FALTA | Ninguna campaña es de una línea. Etiquetar las campañas futuras (agencia, con convención de nombre) |
| Margen de contribución | FALTA | FALTA | FALTA | FALTA | COGS + variables |
| Marketing compartido repartido | FALTA | FALTA | FALTA | — | Política `marketing_shared` (contadora valida, Mario aprueba) |
| Gastos directos / compartidos | FALTA | FALTA | FALTA | FALTA | Cierre mensual (contadora) + política de reparto |
| EBITDA estimado (por unidad) | FALTA | — | — | FALTA | Todo lo anterior |
| Inventario en pares | **DISPONIBLE** (603) | **DISPONIBLE** (24) | **DISPONIBLE** (18) | DISPONIBLE (0) | Leyenda: ledger, sin conteo físico; 179 pares viejos sin migrar (Mario: ¿Contreras existe?) |
| Inventario a precio de venta | DISPONIBLE | DISPONIBLE | DISPONIBLE | — | — |
| Inventario a costo / capital invertido | FALTA | FALTA | FALTA | — | Costo por modelo |
| Rotación / días de inventario / GMROI | FALTA | FALTA | FALTA | — | Costo + inventario inicial |
| Sell-through (desde el 3-oct) | **PARCIAL** | PARCIAL | PARCIAL | — | Historia corta (8 días de convivencia) |
| Antigüedad | FALTA | FALTA | FALTA | — | Fecha de llegada o lote por modelo (Carolina) |
| Crecimiento | **PARCIAL** (en línea MX desde junio) | PARCIAL | PARCIAL | — | Tienda solo desde el 8-oct |
| Por país | MX, CO, ROW en moneda original | ídem | ídem | — | Consolidado: tasa aprobada (I0, Mario) |
| Por canal (online / tienda / a distancia) | PARCIAL | PARCIAL | PARCIAL | — | Tienda desde el 8-oct; TikTok Shop no existe |
| Por tienda (ubicación) | PARCIAL (desde 8-oct) | PARCIAL | PARCIAL | — | P0E |
| Por modelo / variante / talla | DISPONIBLE (venta e inventario) | ídem | ídem | — | — |
| Presupuesto por línea | FALTA | FALTA | FALTA | FALTA | Presupuesto (Mario) + columna `dim_business_line_key` (BU1) |
| Business Case | — | — | — | **FALTA** (todos los insumos) | Ver §7 |

---

## 5. Diseño de pantallas

Todas viven en el panel, bajo **/direccion** (cockpit) y **/estrategia** (con MFA, como hoy). Las cifras de los dibujos son **símbolos**, no datos.

### 5.1 Unidades de negocio: vista general (`/direccion/unidades`)

```
┌ Unidades de negocio ── Periodo [Oct 2026 ▾] ── Mercado [MX ▾] ── Moneda [Original | MXN*] ── Actualizado 08:15 ┐
│                                                                                                                  │
│  UNIDAD FUXIA ADULTO                                   │  UNIDAD FUXIA KIDS                                       │
│  Venta neta  $A   ▲ x% vs sep                          │  Estado: PLANEADA · Business Case v2 (borrador)          │
│  Contribución  INCOMPLETO ⓘ falta costo (Carolina)     │  Punto de equilibrio: INCOMPLETO ⓘ 6 supuestos sin dueño │
│  EBITDA estimado  FALTA ⓘ cierre + reparto             │  [Ver Business Case]                                     │
│  Inventario 645 pares · a costo FALTA                  │                                                          │
├─────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ Línea          Venta neta   %    Pares   Contribución    Inventario (pares)  Capital a costo   Calidad           │
│ Ballerinas     $B           86%  57      FALTA           603                 FALTA             PARCIAL           │
│ Sandalias      $C            5%   3      FALTA            18                 FALTA             PARCIAL           │
│ Botas          $0            0%   0      FALTA            24                 FALTA             PARCIAL           │
│ Kids           —             —    —      —                 0                 —                 PLANEADA          │
│ Sin línea      $D            8%   6      —                 —                 —                 [Resolver 7 →]    │
│ ──────────────────────────────────────────────────────────────────────────────────────────────────────────────  │
│ Total          $T (= Commerce Facts ✔)                                                                          │
└─ * consolidado solo con tasa aprobada · Fuente: commerce_order_lines + inventory_balances · Etiquetas: REAL/ESTIMADO/INCOMPLETO ┘
```

### 5.2 P&L por línea / unidad (`/direccion/unidades/[key]/pnl`)

```
┌ P&L · Fuxia Adulto · México (MXN) · Oct 2026 ── [Línea: Todas ▾]  [Ver como: Unidad | Línea] ── Política v1 ✔ ┐
│ Renglón                              Monto        % venta   Etiqueta     Fuente / falta                         │
│ Venta bruta                          $           —          REAL         commerce_order_lines                   │
│ − Descuentos                         $                      REAL                                                │
│ − Devoluciones                       $                      REAL                                                │
│ = Venta neta                         $           100%       REAL                                                │
│ − COGS                               FALTA                  —            ⓘ 0 de 40 modelos con costo · Carolina │
│ = Utilidad bruta                     FALTA                                                                       │
│ − Comisiones de pago                 FALTA                  —            ⓘ tasa por pasarela · Carolina         │
│ − Envío/empaque no cobrado           FALTA                                                                       │
│ − Marketing directo                  $0                     REAL         ninguna campaña etiquetada             │
│ = MARGEN DE CONTRIBUCIÓN             FALTA       ← tope para líneas, canales, tiendas, modelos                  │
│ ─ solo en vista "Unidad" ───────────────────────────────────────────────────────────────────────────────────────│
│ − Marketing compartido repartido     FALTA                  ESTIMADO     ⓘ política marketing_shared sin aprobar│
│ − Gastos directos de la unidad       FALTA                               ⓘ cierre de oct · contadora            │
│ − Gastos compartidos repartidos      FALTA                  ESTIMADO     ⓘ política opex_shared                 │
│ = EBITDA ESTIMADO DE LA UNIDAD       FALTA                                                                       │
│ [Ver cálculo] [Ver qué falta y de quién] [Exportar]                                                             │
└────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

### 5.3 Drill-down multidimensional (`/direccion/unidades/explorar`)

```
┌ Explorar ── Medida [Margen de contribución ▾] ── Moneda: original ───────────────────────────────────────────────┐
│ Filtros:  Línea [Ballerinas]  País [MX]  Canal [TikTok Shop]  Tienda [—]  Periodo [Q4 2026]                      │
│ Desglosar por:  ( ) Canal  ( ) Tienda  (•) Modelo  ( ) Color  ( ) Talla  ( ) Mes                                  │
│ Modelo        Pares   Venta neta   COGS   Contribución   MC%    Inventario   Sell-through   Calidad              │
│ Model A       n       $            $      $              x%     n            x%             ESTIMADO (costo est.)│
│ Model B       …                                                                                                  │
│ Total = suma de filas ✔ (medidas aditivas) · MC% y sell-through recalculados, no promediados                     │
│ ⓘ Debajo de la unidad no se muestran gastos repartidos ni EBITDA.                                                │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

Responde preguntas como "margen de contribución de Ballerinas vendidas en TikTok Shop México". Si el canal no existe, aparece **"FALTA fuente de ventas de TikTok Shop"**.

### 5.4 Asignación de modelos a líneas (`/catalogo/lineas`, Carolina)

```
┌ Líneas de negocio ── [+ Nueva línea]  ─────────────────────────────────────────────────────────────────────────┐
│ Reglas por categoría (aprobadas)                                                                              │
│   Ballerinas      ← categoría Ballerinas             desde 2026-06-01   aprobó Mario                          │
│   Sandalias       ← Sandalia Plana, Sandalia Alta    desde 2026-06-01   aprobó Mario                          │
│   Botas           ← Botas                            desde 2026-06-01                                          │
│   Kids            (planeada · sin modelos)                                                                    │
│ Excepciones por modelo   [+ Asignar modelo a otra línea]  (requiere motivo; aprueba otra dueña)               │
│ Pendientes de aprobar (1)  ·  Historial  ·  Bandeja "Sin línea" (7) → [SKU viejo BALL-PNT-TCH-NGO: homologar] │
│                                                                    [Venta a distancia: elegir modelo]         │
└───────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

Es una operación sencilla para Carolina: elegir la línea en una lista. No muestra dinero.

### 5.5 Políticas de reparto (`/estrategia/politicas`, contadora + Mario)

```
┌ Políticas de reparto ─────────────────────────────────────────────────────────────────────────────────────────┐
│ Bolsa                  Generador (driver)                 Vigencia     Estado                Validó / Aprobó   │
│ Marketing compartido   % venta neta en línea, mismo mes   oct-2026 →   VALIDADA (contadora)  — / pendiente     │
│                        y mercado                                                                               │
│ Renta tiendas          % venta neta de tienda por unidad  —            BORRADOR                                │
│ Nómina                 % pares vendidos                   —            BORRADOR                                │
│ [Simular con datos de sep] → muestra el resultado SIN publicarlo, con la leyenda "simulación"                  │
│ Cada cambio = versión nueva con motivo. Nada se edita ni se borra.                                             │
└───────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

### 5.6 Business Case Fuxia Kids (`/estrategia/kids`)

```
┌ Fuxia Kids · Business Case v2 (BORRADOR) ── Escenario [Conservador | Base | Optimista] ──────────────────────────┐
│ SUPUESTOS                         Valor      Estado       Dueño        Fuente                                     │
│ Precio de lista por par           P          SIN DATO     Mario        —                                          │
│ Costo de producción por par       C          SIN DATO     Carolina     cotización fábrica                         │
│ Desarrollo (hormas, muestras)     D          SIN DATO     Carolina                                                │
│ … (ver §7)                                                                                                        │
│ RESULTADOS (calculados en servidor)                                                                               │
│ Margen de contribución por par    INCOMPLETO (faltan P, C, …)                                                     │
│ Punto de equilibrio (pares)       INCOMPLETO                                                                      │
│ Capital requerido                 INCOMPLETO                                                                      │
│ COMPUERTAS: G1 Desarrollo ○  G2 Producción ○  G3 Lanzamiento ○  G4 Revisión 90 días ○                             │
│ [Proyección vs real] (activo cuando Kids tenga ventas)                                                            │
└───────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

### 5.7 Lo que se agrega al CEO Cockpit y a Growth

**CEO Cockpit** (`/direccion`). Dos tarjetas nuevas después de las 8 de I2. No cambian las existentes.

```
│ 9 Rentabilidad por unidad          │ 10 Capital e inversión                 │
│   Adulto: venta $A · MC FALTA ⓘ    │   Inventario a costo: FALTA ⓘ          │
│   Kids: PLANEADA                   │   Riesgo: n pares sin venta 90 días    │
│   Sin línea: 8% ⚠                  │   Oportunidad: ver analista →          │
```

**Growth · iniciativa** (`/growth/iniciativas/[code]`):

```
┌ TikTok Shop México · activa · líneas: Ballerinas, Sandalias ─────────────────────────────────────┐
│ Línea        Venta   Pares   Gasto directo   MER   Contribución   Rotación de la línea   Calidad │
│ Ballerinas   …                                                                                    │
│ Sandalias    …                                                                                    │
│ ⓘ Las iniciativas pueden traslaparse: no se suman entre sí.                                      │
└──────────────────────────────────────────────────────────────────────────────────────────────────┘
```

**Celular:**
- tarjetas en una columna;
- las tablas se convierten en lista de tarjetas por línea (nombre, venta, etiqueta) con "ver más";
- el P&L se muestra como acordeón por bloque (venta / contribución / unidad);
- el drill-down limita a 1 dimensión de desglose;
- sin desbordamiento horizontal: pruebas E2E a 390 px, como I2;
- la bandeja "Sin línea" se puede resolver desde el celular.

---

## 6. Ejemplo de P&L por línea con datos reales (jun → 11-oct-2026)

> Solo hechos de producción del 11-oct. **No se convierte ninguna moneda**: no hay tasa aprobada. Cada faltante dice de quién depende.
> "FALTA" significa que no se muestra cifra. Nada de esto es EBITDA.

### 6.1 México (MXN): online Woo + tienda F360 (desde el 8-oct) + a distancia

| Renglón | Ballerinas | Sandalias | Botas | Kids | Sin línea | **Total** | Etiqueta / falta |
|---|---:|---:|---:|---:|---:|---:|---|
| Pares vendidos | 57 | 3 | 0 | — | 6 | **66** | REAL |
| Venta bruta | 149,940 | 8,800 | 0 | — | 15,120 | **173,860** | REAL |
| − Descuentos | 6,734 | 0 | 0 | — | 1,036 | **7,770** | REAL |
| − Devoluciones | 0 | 0 | 0 | — | 0 | **0** | REAL |
| **= Venta neta** | **143,206** | **8,800** | **0** | — | **14,084** | **166,090** | REAL (IVA sin separar: contadora) |
| Participación | 86.2% | 5.3% | 0% | — | 8.5% | 100% | |
| − COGS | FALTA | FALTA | — | — | FALTA | FALTA | Costo por modelo: **Carolina** (0 versiones) |
| − Comisiones de pago | FALTA | FALTA | — | — | FALTA | FALTA | Tasa por pasarela: **Carolina**; criterio: **contadora** |
| − Envío / empaque no cobrado | FALTA | FALTA | — | — | FALTA | FALTA | **Carolina** |
| − Marketing directo | 0 | 0 | 0 | — | — | 0 | No hay campañas por línea |
| **= Margen de contribución** | **FALTA** | **FALTA** | — | — | — | **FALTA** | |
| Envío cobrado (nivel pedido) | | | | | | 400 | REAL (Woo) |
| Meta MX (jun–oct), **compartido** | sin repartir | | | | | **38,063.25** | REAL; reparto: política (contadora + Mario) |
| Gastos fijos | | | | | | **FALTA** | Cierre mensual: **contadora** (0 capturas) |
| **EBITDA estimado (unidad)** | | | | | | **FALTA** | |
| Inventario hoy (pares) | 603 | 18 | 24 | 0 | — | **645** | REAL (ledger, sin conteo físico) |
| Inventario a precio de venta | 1,688,400 | 53,800 | 100,800 | 0 | — | **1,843,000** | REAL ("no es costo") |
| Inventario a costo | FALTA | FALTA | FALTA | — | — | FALTA | Costo: **Carolina** |

Desglose de la venta neta de México:
- **Woo:** Ballerinas 106,806 (44 pares) · Sandalia Plana 2,800 (1) · sin línea 11,284 (5).
- **Tienda F360:** Ballerinas 36,400 (13) · Sandalia Alta 6,000 (2).
- **A distancia:** sin línea 2,800 (1).

**Fuera de la medición** (tiendas viejas, 18-may → 10-oct, pendiente P0E): 36 ventas, 52 pares, MXN 157,900. Se muestran **aparte** y no se suman al total hasta que P0E las importe.

### 6.2 Colombia (COP), solo Woo

| Renglón | Ballerinas | Sandalias | Botas | Sin línea | **Total** | Etiqueta |
|---|---:|---:|---:|---:|---:|---|
| Pares | 16 | 5 | 0 | 1 | **22** | REAL |
| Venta bruta | 6,247,000 | 2,100,000 | 0 | 420,000 | **8,767,000** | REAL |
| − Descuentos | 589,700 | 126,000 | 0 | 0 | **715,700** | REAL |
| **= Venta neta** | **5,657,300** | **1,974,000** | **0** | **420,000** | **8,051,300** | REAL |
| Contribución | FALTA | FALTA | — | — | FALTA | Costo + comisión ePayco + **tipo de cambio** (el costo y el gasto son en MXN) |
| Meta CO (jun–oct) | | | | | **MXN 28,871.40** | En MXN junto a COP, **sin restar** hasta tener tasa aprobada |

**Resto del mundo (USD):** Ballerinas, 3 pares, USD 450.

### 6.3 Lo que este ejemplo enseña

1. Hoy el P&L por línea **llega hasta venta neta**. El primer bloqueo es el **costo por modelo**: con costos de los 40 modelos con venta o existencia ya se tendría margen bruto y capital en inventario.
2. **Botas:** 24 pares (MXN 100,800 a precio de venta) y 0 ventas medidas desde junio. Las tiendas viejas sugieren unas 4 ventas por nombre, sin verificar. Es el primer candidato a **riesgo de inventario**, pero **no se concluye** sin P0E y conteo.
3. Hoy no se puede saber qué línea "consume" el gasto de Meta: **100% es compartido**.

---

## 7. Business Case de Fuxia Kids (plantilla; sin cifras inventadas)

### 7.1 Principios

- **Todo insumo es un supuesto con nombre, unidad, dueño, fuente y estado** (`SIN DATO` → `PROPUESTO` → `APROBADO`). Sin un insumo, los resultados que dependen de él dicen **INCOMPLETO**.
- **Proyección y real nunca se mezclan.** La proyección vive en `business_case_versions`; lo real se lee de `v_bu_sales_lines` cuando la línea `kids` tenga ventas. La pantalla los pone lado a lado.
- **Versionado:** cada cambio de supuesto crea una versión con motivo. Una versión aprobada por Mario queda congelada (mismo patrón que `plan_versions`).
- **Tallas:** la curva de tallas Kids la define Carolina. No se deriva de la curva adulta ni de conversiones (regla de Mario: no inventar conversiones de talla).

### 7.2 Insumos (supuestos) y dueños

| Código | Supuesto | Unidad | Dueño (captura) | Aprueba |
|---|---|---|---|---|
| K-P | Precio de lista por par, por mercado | moneda/par | Mario | Mario |
| K-d | Descuento promedio esperado | % | Mario | Mario |
| K-IVA | Tratamiento de IVA en el precio | regla | Contadora | Contadora |
| K-C | Costo de producción por par (por modelo si difiere) | moneda/par | Carolina (cotización) | Mario |
| K-L | Flete, aduana y logística de entrada por par | moneda/par | Carolina | Mario |
| K-E | Empaque por par | moneda/par | Carolina | — |
| K-f | Comisión de pago | % de la venta neta | Carolina (contrato) | Contadora |
| K-S | Envío no cobrado por pedido ÷ pares por pedido | moneda/par | Carolina | — |
| K-D | Desarrollo: hormas, muestras, diseño, fotos | moneda | Carolina | Mario |
| K-M | Marketing de lanzamiento | moneda | Mario / agencia | Mario |
| K-F | Gastos fijos **directos** mensuales de Kids (si los hay: persona, espacio) | moneda/mes | Mario | Contadora |
| K-N | Modelos × colores al lanzamiento | conteo | Carolina | Mario |
| K-T | Curva de tallas y profundidad por talla | pares por talla | Carolina | Mario |
| K-MOQ | Mínimo de fábrica por modelo y color | pares | Carolina | — |
| K-A | Anticipo a fábrica y plazo de pago | % y días | Carolina | Contadora |
| K-V | Ventas esperadas por mes (por escenario) | pares/mes | Mario | Mario |
| K-W | Meses de capital de trabajo a cubrir | meses | Mario | Contadora |
| K-B | Colchón | % | Mario | — |
| K-canib | Canibalización esperada de líneas adultas | % de la venta Kids | Mario | Mario |

### 7.3 Fórmulas (calculadas en el servidor)

```
P_n   = K-P × (1 − K-d)  [÷ (1 + IVA) si K-IVA indica que el precio incluye IVA]   ← precio neto por par
CV    = K-C + K-L + K-E + K-f × P_n + K-S                                           ← costo variable por par
MC_u  = P_n − CV                                                                    ← margen de contribución por par
MC_%  = MC_u ÷ P_n

CF_lanz = K-D + K-M                                                                 ← costos fijos de lanzamiento (una vez)
CF_mes  = K-F + (marketing recurrente de Kids, si se define)

Punto de equilibrio de lanzamiento (pares)  = CF_lanz ÷ MC_u
Punto de equilibrio mensual (pares/mes)     = CF_mes ÷ MC_u
Meses para recuperar el lanzamiento         = mínimo m tal que Σ_{1..m} (K-V_mes × MC_u − CF_mes) ≥ CF_lanz
   (si MC_u ≤ 0 o K-V × MC_u ≤ CF_mes → "NO SE RECUPERA con estos supuestos")

Inventario inicial (pares) = Σ_modelos Σ_colores Σ_tallas profundidad(talla)   (≥ K-MOQ por modelo y color)
Capital en inventario      = Inventario inicial × (K-C + K-L + K-E)
Capital requerido          = K-D + Capital en inventario + K-M + K-W × CF_mes + K-B × (todo lo anterior)
   (el anticipo K-A define CUÁNDO sale el dinero: flujo mensual, no cambia el total)

Sell-through proyectado al mes m = Σ_{1..m} K-V ÷ Inventario inicial
Contribución neta de canibalización = Σ venta Kids × MC_% − (Σ venta Kids × K-canib) × MC_% adulto
```

### 7.4 Escenarios (simbólicos)

| Variable | Conservador | Base | Optimista | Regla |
|---|---|---|---|---|
| Ventas/mes (K-V) | V_c | V_b | V_o | V_c ≤ V_b ≤ V_o; las fija Mario |
| Descuento promedio (K-d) | d_c | d_b | d_o | d_c ≥ d_b ≥ d_o |
| Costo por par (K-C) | C_c | C_b | C_o | sale de cotizaciones reales; el escenario conservador usa la cotización más alta |
| Marketing de lanzamiento (K-M) | M | M | M | igual en los 3 (se decide, no se proyecta) |
| **Resultados** | PE, meses, capital | ídem | ídem | calculados |

**Formato de un ejemplo trabajado sin números:** "Si P_n = P y CV = C, cada par deja P − C. Con un lanzamiento de D + M, el equilibrio es (D + M) ÷ (P − C) pares. Con V pares al mes y sin gastos fijos mensuales, se recupera en ⌈(D + M) ÷ (V × (P − C))⌉ meses."

**No se publica ninguna cifra** mientras un insumo esté en `SIN DATO`.

### 7.5 Compuertas: escalar, ajustar o detener

**Los umbrales numéricos (X, Y, Z…) los fija Mario antes de cada compuerta** y quedan congelados en la versión aprobada, como en `06_EXPERIMENTS.md` (umbrales antes de empezar).

| Compuerta | Cuándo | Criterio medible (insumos) | Decisión |
|---|---|---|---|
| **G1 Desarrollo** | antes de pagar hormas y muestras | K-C, K-D, K-P aprobados; MC_% proyectado (base) ≥ **X%** | seguir / rediseñar / no seguir |
| **G2 Producción** | antes de la orden a fábrica | capital requerido (conservador) ≤ **capital disponible aprobado**; señal de demanda previa (lista de espera, favoritos o "Avísame" de Kids, preventa) ≥ **Y** | producir / reducir profundidad / esperar |
| **G3 Lanzamiento** | día 0 | inventario recibido y contado; precios publicados; campañas etiquetadas a la línea `kids` (para medir marketing directo) | lanzar |
| **G4 Revisión 30/60/90 días** | después del lanzamiento | sell-through real ≥ **S%**; MC_% real ≥ **M%**; reemplazos y cambios ≤ **R%**; CPA de Kids ≤ **A**; canibalización observada ≤ **K%** | **Escalar** (todos se cumplen) / **Ajustar** (1–2 no se cumplen) / **Detener** (MC_u real ≤ 0 o sell-through < S_min) |

Cada evaluación se registra con evidencia (las cifras con su fuente y etiqueta) y la decisión de Mario va al registro de decisiones del consejo (`f360_board.decisions`, ya existe en `20261015000300…:27`).

### 7.6 Dónde vive

- **Ahora (BU5):** `f360_board.business_cases` y `business_case_versions`:
  - `inputs jsonb` validado: cada insumo con `value`, `unit`, `currency`, `status`, `owner`, `source`, `approved_by`;
  - `outputs jsonb` calculado en el servidor;
  - `scenario` (`conservador` \| `base` \| `optimista`).
- **Después:** cuando exista el Scenario Lab (spec `04`, que ya prevé "nueva categoría" en §3), el Business Case se **importa** como escenario CUSTOM (`imported_from = business_case:<id>:<v>`), y las compuertas se ligan a `strategic_gates` (spec `06`). No se duplica: el caso sigue siendo la fuente y el escenario es una copia versionada para comparar.

---

## 8. Plan de implementación (sprints BU0–BU6, después de I4)

**No bloquean I0–I4.** Todo empieza en staging. Producción solo con diseño aprobado y autorización de Mario. Cada sprint tiene migración aditiva y rollback `supabase/rollbacks/*.down.sql`.

| Sprint | Alcance | Depende de (personas / datos) | Pruebas | Rollback |
|---|---|---|---|---|
| **BU0 Catálogo y asignación** | `business_lines`, `business_line_rules`, `business_line_of()`, `v_product_business_line`; RPCs propose/decide/list; ampliar `approval_scopes.scope` con `business_line_map`, `allocation_policy`, `business_case`, `cost_assumption` (solo amplía el CHECK de I0); pantalla 5.4 (sin dinero) | Mario: lista de líneas y unidades (decisiones 1–2). Carolina: revisar 72 modelos | Cada modelo resuelve exactamente a 1 línea o a SIN_LINEA; sin traslapes; quien propone ≠ quien aprueba; sin borrar ni editar; vendedora → 42501 | DROP de las tablas y funciones nuevas; restaurar el CHECK de I0 |
| **BU1 Hechos por línea** | `v_bu_sales_lines` (vista, sin copia); inventario por línea; `sale_line_product_links` + bandeja "Sin línea"; RPCs `f360_bu_summary/explore` con el sobre `meta` de I1; columna nula `budget_lines.dim_business_line_key` (coordinada con I1) | P0E (Carolina: bazares); homologación del SKU viejo | **Σ líneas + Sin línea = Commerce Facts** por mercado y moneda; la venta de tienda marcada a distancia no se duplica entre canales; medidas no aditivas recalculadas; periodo vacío sin división entre cero | DROP de vista, tabla y columna (está vacía) |
| **BU2 Costo y contribución** | COGS por renglón desde `product_cost_effective`; cobertura de costo; `cost_rate_assumptions`; `campaign_line_tags`; contribución por línea, canal, tienda, modelo y talla; inventario a costo, GMROI, capital en riesgo | **Carolina: costos** (≥ 95% de los pares vendidos para mostrar cifra); tasas de pasarela; contadora: criterio de IVA | COGS usa el costo vigente en la fecha de la venta; un costo `owner_estimate` produce ESTIMADO; sin costo produce INCOMPLETO; el costo nunca aparece en RPC de seller/viewer | DROP de tablas nuevas; las vistas vuelven a BU1 |
| **BU3 Reparto y P&L por unidad** | `pnl_units`, `pnl_unit_lines`, `allocation_policies/_versions`, `allocation_runs/_results`; simulación; P&L por unidad con EBITDA estimado | **Contadora:** cierre mensual + validar políticas. **Mario:** aprobar | Σ repartido = bolsa (por mercado, mes y moneda), con redondeo asignado a una unidad fija; una sola corrida vigente por mes; repetir la corrida sustituye; ningún gasto repartido aparece debajo de la unidad; "EBITDA" nunca aparece sin "estimado" | DROP de las tablas `f360_board` nuevas |
| **BU4 Pantallas + Growth** | Pantallas 5.1–5.3, 5.5, tarjetas 9–10 del cockpit; `growth_initiatives` + `growth_initiative_lines` + vista de iniciativa | I2 (cockpit) terminado; Mario: decisión 6 | E2E a 1440 y 390 px; "las iniciativas no se suman"; permisos por rol | Revertir el panel + DROP de las tablas de iniciativas |
| **BU5 Business Case Kids** | `business_cases/_versions`, cálculo en servidor, compuertas, proyección vs real; pantalla 5.6 | Dueños de §7.2; Mario: umbrales | Sin insumo → INCOMPLETO (nunca 0); fórmulas con casos de prueba simbólicos y extremos (MC_u ≤ 0, V = 0); versión aprobada congelada | DROP de las tablas |
| **BU6 Analista** | 6 herramientas `f360_ai_bu_*` (lista blanca, JWT de quien pregunta) + set de evaluación con las 6 preguntas (§9.4) y preguntas trampa ("¿cuál es el EBITDA de Botas?" debe responder "falta…"); verificador de números | I3–I4 | Cada respuesta cita fuente, periodo, moneda, supuestos y calidad; nunca "EBITDA" sin "estimado"; sin PII | Quitar las herramientas de la lista blanca |

Orden mínimo con valor: **BU0 → BU1** (venta e inventario por línea, que ya es útil hoy) → **BU2** cuando Carolina capture costos → BU3 cuando haya cierre.

---

## 9. Gobierno, seguridad y analista

### 9.1 Quién hace qué (mapeado a piezas existentes)

| Persona | Captura / propone | Valida | Aprueba | Pieza existente |
|---|---|---|---|---|
| **Carolina** | Costos por modelo (con `source` y notas: factura, orden de producción, estimación); reglas modelo → línea; vínculos de "Sin línea"; tasas de pasarela, envío y empaque; insumos operativos de Kids | — | Reglas de línea **propuestas por Mario** (y viceversa: nunca su propia propuesta) | `product_cost_versions` (`…sg0_product_cost.sql`), `business_line_rules` |
| **Contadora** | Cierre mensual (gastos por cuenta, `dimension_key = 'bu:<unidad>'` cuando un gasto es directo); propuesta de políticas de reparto | Políticas de reparto, criterio de IVA, tasas de costo variable | — | `monthly_close_entries`, capacidad de contadora de I1, `allocation_policy_versions.validated_by` |
| **Mario** | Supuestos estratégicos (precios, volúmenes y umbrales de Kids, reparto de marketing) | — | Políticas de reparto, escenarios, Business Case, prioridades de inversión, tasa FX (I0) | `approval_scopes` (nuevos scopes), `f360_board.decisions` |

**Reglas comunes:**
- versiones append-only;
- `reason` obligatorio;
- quien propone ≠ quien aprueba;
- registro de accesos (`f360_board.access_log`);
- MFA (`require_aal2`, `20261016000100_f360_board_mfa_required.sql`) para todo lo de `/estrategia`;
- un dato aprobado no se edita: se sustituye con una versión nueva.

### 9.2 Quién ve qué

| Rol | Ve | No ve nunca |
|---|---|---|
| Vendedora (`seller`) | Nada de este módulo. Si acaso, el nombre de la línea del producto en el POS | Costos, márgenes, contribución, reparto, EBITDA, Business Case |
| Operador (`operator`, hoy 0 usuarios) | Líneas, asignaciones, venta e inventario por línea; captura de costo (ya puede leer el costo por `:109`) | Márgenes por unidad, reparto, EBITDA, Business Case. **Ver contradicción 4 (§10).** |
| Contadora | P&L por unidad **agregado**, cierre, políticas, tasas | PII de clientas, cap table, valuación, investor room, Business Case y escenarios (salvo que Mario los comparta) |
| Dueñas / consejo (FINANCIAL + MFA) | Todo | — |
| Analista IA | Lo mismo que quien pregunta (JWT), solo agregados | PII, texto libre de terceros, SQL arbitrario |

### 9.3 Analista: herramientas nuevas (lista blanca, solo lectura)

`f360_ai_bu_summary(periodo, mercado)`, `f360_ai_bu_pnl(unidad|línea, periodo, mercado)`, `f360_ai_bu_growth(periodo_a, periodo_b)`, `f360_ai_bu_capital(fecha)`, `f360_ai_bu_inventory_risk(días_sin_venta)`, `f360_ai_bu_business_case(key, escenario)`.

Todas devuelven el sobre de I1: `{data, meta: {fuente, periodo, moneda, actualizado_al, calidad, disponibilidad, faltantes[], supuestos[], politicas[]}}`.

### 9.4 Las seis preguntas y cómo responden hoy

| Pregunta | Respuesta hoy | Qué la completa |
|---|---|---|
| ¿Qué línea es más rentable? | "No se puede decir: falta costo por modelo (Carolina). En **venta neta**, Ballerinas concentra 86% de México." | BU2 |
| ¿Cuál crece más rápido? | Parcial: solo en línea en MX y CO desde junio; tienda desde el 8-oct; muestra la tasa con "base pequeña" | Más historia + P0E |
| ¿Cuál consume más capital? | En **pares y a precio de venta**: Ballerinas (603 pares). A costo: "falta costo" | BU2 |
| ¿Dónde invertir el siguiente peso? | **Recomendación** marcada como opinión, solo con contribución y GMROI disponibles. Hoy: "no hay base de rentabilidad; la inversión de mayor valor informativo es capturar costos" | BU2–BU3 |
| ¿Qué línea tiene mayor riesgo de inventario? | Hecho: Botas, 24 pares y 0 ventas medidas desde junio. Con la advertencia: "sin conteo físico; ventas de tiendas viejas fuera de la medición" | P0E + conteo + antigüedad |
| ¿Cuál es el punto de equilibrio de Kids? | "INCOMPLETO: faltan K-P, K-C, K-D, K-M… (dueños)". Nunca una cifra | BU5 + insumos |

---

## 10. Riesgos y contradicciones

### 10.1 Contradicciones entre documentos y repositorio (regla 14)

1. **"Sandalias" vs. categorías:** Mario habla de 3 líneas adultas, y la tienda tiene 4 categorías (Sandalia Plana y Sandalia Alta separadas). Se resuelve con la capa de líneas **sin tocar las categorías**.
2. **Taxonomía "Zapatos / Accesorios"** en el modelo de crecimiento (`admin-web/src/lib/growth-model.ts:51`, `shoes_pct`/`accessories_pct`): no hay accesorios en el catálogo y no coincide con las líneas. Propuesta: dejarla como está (es un supuesto del plan) y, cuando se apruebe BU1, que el plan use `line_key`. **Decisión de Mario.**
3. **Dónde vive el costo:** `strategy-board/13_DATA_MODEL.md` §2 proponía `product_cost_versions` en `f360_board` con lectura FINANCIAL. La realidad es `f360.product_cost_versions` (S-G0), legible por **operator+** (`…sg0_product_cost.sql:109`). Hoy no hay operadores, así que el riesgo es latente. Recomendación: **no cambiar** el contrato de S-G0; si se da de alta un operador que no deba ver costos, decidirlo entonces.
4. **`remote_sales.market` admite `'US'`** (`20261019000100_f360_remote_sales.sql:31`), mientras todo lo demás usa `'ROW'`. Hoy no afecta (1 venta MX). Hay que normalizarlo en la vista de BU1 (US → ROW) y documentarlo; no se cambia la tabla.
5. **`plan_initiatives`** (spec 05) y **`growth_experiments`** (spec 06) están especificados y **no existen**. Las iniciativas de BU4 deben ser la primera implementación, compatible con ambos specs, y no una tercera tabla.
6. **Métrica `ebitda` del catálogo** (`…finance_foundation.sql:269`) es de empresa y con cierre. La de unidad debe ser otra llave (`bu_ebitda_estimated`) para no confundir REAL con ESTIMADO.
7. **Cifras del pedido vs. hoy:** el contexto decía 71 modelos, 1,044 variantes y 122 precios; hoy hay **72, 1,050 y 123**. Es el catálogo vivo, no un error. Todas las cifras de este documento llevan fecha.

### 10.2 Riesgos de asignación contable

| Riesgo | Mitigación |
|---|---|
| Un reparto arbitrario hace que una línea parezca no rentable y se cierre por error | Reparto solo a nivel **unidad**; líneas evaluadas por **contribución**; toda cifra repartida lleva la etiqueta ESTIMADO y muestra la política |
| Cambiar la política cambia la historia | Versiones con vigencia; una corrida guarda las versiones usadas; repetir la corrida no borra la anterior; la pantalla dice "corrida v3, política v2" |
| Gasto contado dos veces (directo y repartido; o total y por unidad en el cierre) | Reglas §2.4.4; validación: para una cuenta y un mes, **o** se captura total (`''`) **o** por `bu:*` (más `bu:shared`), nunca ambos; pruebas de suma |
| Kids absorbe o esconde costos de Adulto (o al revés) | Gastos directos de Kids capturados como `bu:kids` desde el día 1; compuerta G3 exige campañas etiquetadas |
| Costos estimados presentados como reales | `source = owner_estimate` siempre produce ESTIMADO; la cobertura de costo se muestra |
| IVA mal tratado (venta con IVA vs. costo sin IVA) | Hasta la decisión de la contadora, venta "como se cobró" y leyenda; margen marcado ESTIMADO |
| Colombia: costo y gasto en MXN, venta en COP | Contribución CO solo con tasa aprobada (I0) |

### 10.3 Riesgos de seguridad

| Riesgo | Mitigación |
|---|---|
| Vendedora ve márgenes o costos | RPCs `f360_bu_*` financieras con `require_board_member('FINANCIAL')`; pruebas 42501 por rol (seller, viewer, anon) |
| Contadora accede a PII o estrategia | Capacidad limitada de I1, con RPCs propias y agregadas, sin `customer_pii_viewers` ni scopes CAP_TABLE, VALUATION o INVESTOR_ROOM |
| El analista filtra datos o inventa | Herramientas en lista blanca con JWT de quien pregunta; solo agregados; verificador de números; set de preguntas trampa |
| Aprobación por la misma persona | CHECK proponente ≠ aprobador en reglas, políticas y casos |
| Rutas de escritura con service role desde el panel | No: todas las escrituras van por RPC `SECURITY DEFINER` con rol; el panel no tiene secretos (`env-guard.ts`) |

### 10.4 Riesgos de calidad de datos

| Riesgo | Hoy | Mitigación |
|---|---|---|
| Venta sin línea | MX 8.5%, CO 5.2% | Bandeja "Sin línea"; meta ≥ 98%; indicador visible en cada pantalla |
| Tiendas viejas fuera de la medición | MXN 157,900 | P0E + vínculos aprobados (no coincidencia automática de nombres) |
| Inventario sin conteo físico; 179 pares viejos | 645 en ledger | Leyenda "ledger"; conteo físico; decisión sobre Contreras |
| Sin antigüedad real | — | Capturar fecha de llegada o lote en recepciones nuevas; para el arranque, Carolina estima por modelo (ESTIMADO) |
| Historia corta de tienda (desde 8-oct) | — | Crecimiento y sell-through PARCIAL hasta P0E |
| Caída de septiembre en ecommerce MX | 5,320 vs 56,364 | Ya señalada en el Centro de Inteligencia §8: revisar antes de usar como base de líneas |
| Campañas sin línea | 35/35 | Convención de nombre o etiqueta para campañas nuevas (agencia); las viejas quedan como compartidas |

---

**Siguiente paso: nada se implementa.** Primero espero tu aprobación del modelo (líneas vs. unidades), las decisiones de §0 y el orden de los sprints BU0–BU6, que empiezan **después de I4**.
