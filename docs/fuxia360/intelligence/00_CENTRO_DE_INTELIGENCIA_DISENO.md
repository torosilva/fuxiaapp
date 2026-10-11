# Centro de Inteligencia de Fuxia 360 · Diseño (primera entrega)

> 2026-10-11 · rama `fuxia-360` · pedido de Mario: CEO Cockpit + AI Business Analyst (Claude, separado de Hilo) + consolidación de monedas.
> **Solo diseño. No se implementó nada, no se creó ninguna migración y no se tocó producción, WooCommerce ni las pasarelas.**
> Todas las cifras salen de consultas de **solo lectura** a producción hechas hoy (`scripts/f360/prod_read.sh`). Las pendientes de seguridad y aislamiento no se modifican.

## 0. Resumen

- **De los 8 indicadores, 1 se puede mostrar completo hoy (KPI 2), 5 a medias (KPI 1, 3, 5, 6, 8) y 2 no tienen fuente (KPI 4, 7).** Lo que más falta:
  - **presupuesto:** `f360_board.budget_versions` = 0;
  - **costo por modelo:** `product_cost_versions` = 0;
  - **caja y gastos:** `monthly_close_entries` = 0;
  - **ventas de tienda anteriores al 8 de octubre:** siguen en `public.offline_sales`, fuera de la medición (pase P0E);
  - **visitas:** GA4 sin permiso todavía.
- **El analista se puede construir ya.** No se "entrena": lee los datos en el momento, con funciones fijas de solo lectura, y cita cada número. Contesta bien 4 de las 10 preguntas y a medias otras 4. Las 2 restantes deben responder "falta fuente" hasta que exista esa fuente.
- **Contradicción con el diseño previo (spec 12 §4).** El diseño previo ponía el chatbot dentro del panel (Next.js). El guard del panel (`admin-web/src/lib/env-guard.ts`) **impide** desplegar el panel con secretos de servidor, y la llave de Claude lo es. **Propuesta:** el orquestador vive en una Edge Function propia (`f360-analyst`), con la llave como secreto de la función. Así no hay que debilitar el guard.
- **Dato que conviene revisar antes de fijar metas:** ecommerce México, venta neta pagada en MXN.

  | Jun | Jul | Ago | Sep | Oct (al 11) |
  |---|---|---|---|---|
  | 2,800 | 56,406 | 56,364 | **5,320** | 5,600 |

  - Septiembre cayó un 90% mientras Meta MX gastaba $7,202.
  - Puede ser real o un hueco de datos, por ejemplo ventas que entraron por otro sitio durante el cambio de tienda. **No lo asumo.** Es la primera pregunta que el cockpit debe ayudar a explicar.
  - La meta de $300,000 MXN/mes es unas 5.3 veces el mejor mes registrado.

### Decisiones que necesito de Mario
1. **Presupuesto:** ¿quién captura el presupuesto mensual 2026–2027 por país y canal, y en qué formato? Sin eso, los KPI 1 y 8 no tienen contra qué compararse.
2. **Costos:** ¿Carolina captura el costo por modelo? Es necesario para el margen (KPI 4).
3. **Cierre mensual:** ¿la contadora captura cada mes caja, bancos y gastos en el cierre que ya existe (`/estrategia/cierre`)? Es necesario para el KPI 7.
4. **Tipo de cambio:** ¿qué fuente diaria? Opciones en §5. "Google" no ofrece una fuente que un sistema pueda leer.
5. **Llave de Claude:** cuenta en console.anthropic.com a nombre de Fuxia, con tope de gasto mensual.

---

## 1. Matriz de disponibilidad de los ocho KPIs

Estados:
- **DISPONIBLE:** se puede mostrar hoy con datos confiables.
- **PARCIAL:** se muestra, pero con aviso visible de qué falta.
- **FALTA:** no se muestra ninguna cifra, solo la explicación de qué falta.

| # | Indicador | Estado | Qué hay hoy (producción, 2026-10-11) | Qué falta y de quién |
|---|---|---|---|---|
| 1 | Ventas netas semanales y mensuales contra presupuesto | **PARCIAL** (venta) · **FALTA** (presupuesto) | **En línea:** 84 pedidos Woo, jun–oct (P0D); en `measurement_sales`. **Tienda:** solo desde el 8-oct (6 ventas). **Remotas:** 1. | **Presupuesto:** `budget_versions` = 0 (Mario). **Ventas de tienda previas:** 43 en `public.offline_sales` (18-may → 10-oct) fuera de la medición, necesitan P0E (Carolina decide bazares). **IVA:** tratamiento pendiente de la contadora; hoy los montos se muestran tal como se cobraron. |
| 2 | Avance de ecommerce México hacia $300,000 MXN/mes | **DISPONIBLE** | Venta neta pagada en línea MX por mes (tabla de §0), al día cada 15 min (cron de conciliación). | Registrar la meta en el sistema: hoy no está en ninguna tabla. Solo existe `growth_plans` 2027 = 15,000,000 MXN anual. |
| 3 | Ventas por país y canal | **PARCIAL** | En línea MX / CO / resto completo desde junio. Tienda MX desde el 8-oct. | P0E para tienda antes del 8-oct. Colombia no tiene tiendas en Fuxia 360. **Pregunta:** ¿Colombia vende por otro canal que debamos medir? |
| 4 | Margen de contribución por país y canal | **FALTA** | Venta neta y gasto de Meta por país. | **Costo por modelo** (`product_cost_versions` = 0, Carolina). **Comisión de pasarela:** Woo no la da, hay que definir tasa o fuente. **Costo de envío real.** **Tipo de cambio** para Colombia. |
| 5 | Inversión, ROAS, MER, CPA y CAC | **PARCIAL** | **Gasto:** Meta por país desde el 1-may, diario; Google Ads = sin gasto. **MER y CPA** calculables: MX ya; CO necesita tipo de cambio, porque gasta en MXN y vende en COP. | **ROAS atribuido:** necesita atribución propia (UTM + GA4); nunca el ROAS que reporta Meta. **CAC:** necesita identidad de clienta nueva, y los pedidos de invitada no siempre la tienen. **GA4:** permiso pendiente (Adrián). |
| 6 | Inventario disponible, rotación y baja salida en México | **PARCIAL** | **Saldo vivo:** 645 pares en ubicaciones (ledger F360), por modelo, talla y tienda. **Inventario a precio de venta:** disponible. | **Rotación y baja salida** necesitan historial de ventas por variante: en línea desde junio, tienda solo desde el 8-oct, mejora con P0E. **Inventario a costo:** necesita costos. |
| 7 | Caja, entradas, salidas y compromisos | **FALTA** | Las cuentas de cierre existen (`close_accounts`: bancos, efectivo en tiendas, gastos), pero sin capturas (`monthly_close_entries` = 0). | **Captura mensual de cierre** (contadora/Mario). **Compromisos:** no existe ninguna fuente (pagos a fábrica, rentas, nómina por venir). Hay que definir dónde se registran. **No hay conexión bancaria** y no la propongo en esta etapa. |
| 8 | Pronóstico de cierre y brecha contra objetivos | **PARCIAL** | Se puede calcular la **proyección por ritmo** (venta del mes ÷ días transcurridos × días del mes), etiquetada como cálculo y no como pronóstico. | **Pronóstico formal:** `forecast_versions` = 0. **Objetivos por mes:** ver KPI 1. **Brecha** solo contra metas registradas (hoy: la de $300k, si se registra). |

---

## 2. Las diez preguntas ejecutivas

> **Aviso:** en esta conversación no quedaron escritas diez preguntas. Las de abajo son una **propuesta** basada en tu objetivo, en tus 8 indicadores y en el spec `strategy-board/12_AI_BOARD_ANALYST.md` §2. Cámbialas o apruébalas.

| # | Pregunta | Viabilidad hoy | Funciones de lectura que usaría | Qué la completa |
|---|---|---|---|---|
| 1 | ¿Cómo vamos esta semana y este mes en ventas, por país y canal, contra el presupuesto? | **Parcial:** venta sí; presupuesto no; tienda solo desde el 8-oct | `ventas_periodo`, `presupuesto_periodo` | Presupuesto + P0E |
| 2 | ¿Cuánto falta para los $300,000 de ecommerce MX este mes y qué ritmo diario necesito? | **Sí** | `ventas_periodo`, `meta_mensual` | Registrar la meta |
| 3 | ¿Qué país o canal subió o bajó contra el periodo anterior, y fue por número de pedidos o por ticket promedio? | **Sí** (en línea) · parcial (tienda) | `ventas_comparadas` | P0E |
| 4 | ¿Cuál es el margen de contribución por país y canal? | **No** (responde "falta costo") | `margen_contribucion` | Costos + comisiones + tipo de cambio |
| 5 | ¿Cuánto vendimos por cada peso invertido en Meta, por país y por campaña? | **Sí** MER/CPA en MX · CO con tipo de cambio · ROAS atribuido no | `marketing_resumen`, `ventas_periodo` | Tipo de cambio (I0) + GA4/UTM |
| 6 | ¿Dónde se pierde la venta en línea: visitas → producto → carrito → pago → compra? | **Parcial:** solo la parte de pago (pedidos creados, fallidos, cancelados, cobrados) | `embudo_pago`, `embudo_visitas` | GA4 (Adrián) |
| 7 | ¿Cuántos pagos no se completan, con qué pasarela y cuánto dinero representan? | **Sí** (Conciliación + Commerce Facts, sin datos personales) | `pagos_no_completados` | — |
| 8 | ¿Qué modelos y tallas tienen baja salida en México y cuánto inventario está detenido? ¿Qué se está agotando? | **Parcial:** saldo sí; rotación con historial corto | `inventario_mx`, `rotacion_variantes` | P0E + costos (para "detenido a costo") |
| 9 | ¿Cuánto cerraremos el mes con el ritmo actual y cuál es la brecha contra la meta? | **Parcial:** proyección por ritmo, etiquetada como cálculo | `proyeccion_ritmo`, `meta_mensual` | Presupuesto / pronóstico |
| 10 | ¿Cuánta caja tenemos, qué entró y salió, y qué compromisos vienen? | **No** (responde "falta captura de cierre") | `caja_cierre` | Cierre mensual + registro de compromisos |

**Regla común:** cuando una pregunta depende de una fuente que no existe, el analista lo dice y nombra la fuente faltante. Nunca estima "para rellenar".

---

## 3. Arquitectura del AI Business Analyst

```
Panel /inteligencia (Carolina, Mario)
   │  pregunta + sesión de la usuaria (JWT)
   ▼
Edge Function f360-analyst (servidor; secreto ANTHROPIC_API_KEY; nada en el navegador)
   ├─ 1. valida sesión → f360_me() → solo dueñas/miembros del consejo (mismo permiso que el cockpit)
   ├─ 2. revisa topes de consumo (por usuaria/día y presupuesto mensual) → si excede, no llama al modelo
   ├─ 3. bucle con el proveedor (interfaz AnalystModel) ── herramientas = lista blanca fija
   │        └─ cada herramienta = UNA función RPC de solo lectura f360_ai_<nombre>(parámetros tipados)
   │           llamada CON EL JWT DE LA USUARIA (aplican require_role y RLS; nunca service role)
   ├─ 4. verificador: cada número de "Hechos" debe existir en lo que devolvieron las herramientas; si no → "no verificado"
   └─ 5. auditoría append-only f360.ai_queries (sin datos personales) → respuesta
```

**Requisito por requisito:**

| Requisito | Cómo se cumple |
|---|---|
| Datos actuales con funciones autorizadas | 10–12 RPC `f360_ai_*`, `SECURITY DEFINER` + `require_role('owner')`, `STABLE`, solo `SELECT`. Leen las mismas vistas que el cockpit (una sola fuente de verdad). |
| Permisos por usuario | Las RPC se llaman con el JWT de quien pregunta. Una vendedora recibe 42501 igual que en el panel. |
| Fuente, periodo, moneda y fecha | Cada RPC devuelve `{data, meta: {fuente, periodo, moneda, actualizado_al, calidad, disponibilidad, faltantes[]}}`. La respuesta muestra esos campos debajo de cada cifra. |
| Hechos, cálculos y recomendaciones separados | Formato obligatorio en tres bloques. **Hechos:** cifras tal cual, con cita. **Cálculos:** fórmula + insumos citados, por ejemplo "ritmo necesario = (meta − venta) ÷ días restantes". **Recomendaciones:** marcadas como opinión del analista. El verificador revisa los Hechos. |
| No inventar | Si `meta.disponibilidad = FALTA`, la instrucción del sistema obliga a responder "falta" + `faltantes[]`. Pruebas automáticas con preguntas trampa. |
| Sin SQL arbitrario | El modelo **solo** ve las herramientas declaradas con parámetros tipados: fechas, `market ∈ {MX, CO, ROW}`, `channel ∈ {online, store, remote}`, límite. No existe una herramienta de SQL ni de texto libre. |
| Proveedor desacoplado | Interfaz `AnalystModel.run(messages, tools, limits)`. Implementación inicial: `ClaudeModel`. Proveedor y modelo por configuración (`F360_AI_PROVIDER`, `F360_AI_MODEL`); cambiar de proveedor es una implementación nueva, sin tocar herramientas ni auditoría. |
| Hilo separado | Otra función, otro secreto, otras tablas. No comparte el canal HiloLabs → service role ni la bandeja de clientas. Hilo no puede llamar al analista ni al revés. |
| Auditoría sin datos personales | `f360.ai_queries` (append-only): quién, cuándo, la pregunta (con correos y teléfonos enmascarados antes de guardar), herramientas y parámetros, fuentes citadas, tokens, costo estimado, modelo, duración, resultado y números no verificados. **No guarda** las respuestas crudas de las herramientas; son agregados sin datos personales, y la respuesta final se puede reconstruir. Retención propuesta: 12 meses. |
| Datos que salen al proveedor | Solo agregados (totales, conteos, modelos y tallas). Ninguna herramienta devuelve nombres, correos, teléfonos ni direcciones de clientas. Política del proveedor (uso para entrenamiento y retención): confirmarla en la cuenta de API antes de producción. |
| Inyección de instrucciones | Las herramientas no devuelven texto libre escrito por terceros, como notas de pedidos o reseñas. Nombres de producto y campañas van como datos, nunca como instrucciones. Pruebas con nombres de campaña maliciosos. |

**Pantalla:** `/inteligencia`, con un chat y, debajo de cada respuesta, las fuentes en chips de "fuente · periodo · moneda · actualizado". Tiene un botón "ver cálculo" y "copiar como resumen semanal".

---

## 4. Diseño del CEO Cockpit

**Ruta:** `/direccion`. Solo dueñas/consejo, con la misma regla que `/estrategia` (incluye MFA).

**Estructura:** 8 tarjetas en una cuadrícula, 2 columnas en escritorio y 1 en celular, en el orden de tus 8 indicadores.

```
┌ Semana 41 · 5–11 oct ── [Moneda original | Consolidado MXN*] ── Actualizado 08:15 ─┐
│ 1 Ventas vs presupuesto      │ 2 Ecommerce MX → $300k              │
│   MX $45,200 · CO $0 · …     │   $5,600 / $300,000 (1.9%)          │
│   Presupuesto: FALTA ⓘ        │   Ritmo necesario: $14,750/día      │
├──────────────────────────────┼─────────────────────────────────────┤
│ 3 País × canal (tabla)       │ 4 Margen de contribución            │
│                              │   FALTA: costo por modelo ⓘ          │
├──────────────────────────────┼─────────────────────────────────────┤
│ 5 Inversión / MER / CPA      │ 6 Inventario MX                     │
│   MER MX 3.2 · CPA $870 …    │   645 pares · baja salida: 12 mod.  │
├──────────────────────────────┼─────────────────────────────────────┤
│ 7 Caja y compromisos         │ 8 Cierre proyectado (ritmo)          │
│   FALTA: cierre mensual ⓘ     │   $X proyectado · brecha −$Y        │
└──────────────────────────────┴─────────────────────────────────────┘
* el consolidado solo aparece si hay tipo de cambio aprobado para ese mes
```

(Las cifras del dibujo son ilustrativas; no son datos.)

**Reglas de la pantalla:**
- Cada tarjeta muestra un sello **Completo / Parcial / Falta fuente**. Al tocar ⓘ se ve qué falta y de quién depende. Una tarjeta en FALTA **no muestra cifra**.
- **Moneda original por defecto.** El modo "Consolidado MXN" convierte con el tipo de cambio aprobado del mes, muestra la tasa usada y excluye de la conversión los pedidos con moneda sospechosa no conciliada (ver §5).
- **Periodo** semanal (lunes a domingo, hora de CDMX) y mensual. La comparación es contra el periodo anterior y, cuando exista, contra el presupuesto.
- **Una sola fuente de verdad:** el cockpit y el analista leen las mismas RPC. Nada se recalcula en el navegador.
- El pie de cada tarjeta muestra la fuente y la fecha de actualización (la misma salud de fuentes de Medición).
- Las cifras en línea siguen las reglas de `growth/02_MEASUREMENT_TRUTH.md`: pedidos pagados y venta neta de producto. Las exclusiones de Conciliación se muestran aparte, nunca restadas en silencio.

---

## 5. Tipo de cambio: propuesta de consolidación MXN / COP / USD (primero en staging)

**Lo que ya existe** (`20261014000300_f360_sg0_fx_rates.sql`): `f360.fx_rates` **mensual**, base MXN, con flujo propuesto → aprobado → anulado, fuente obligatoria, sin borrado y con `fx_rate_for(moneda, mes)`. **En producción tiene 0 filas.**

**Propuesta (aditiva, no cambia lo existente):**
1. **Nueva tabla `f360.fx_observations`** (append-only): `fecha, moneda, base 'MXN', tasa, fuente, referencia de la fuente, leída_en, run_id`. Una fila por día y moneda. Las correcciones son una fila nueva y nunca se edita una existente.
2. **Lectura diaria automática** (función + cron, igual que Meta): COP y USD contra MXN. Si la fuente falla, la salud de la fuente `fx_rates` pasa a ERROR, y a STALE tras 36 h.
3. **Tasa mensual derivada:** promedio de las observaciones del mes, que se **propone** sola en `fx_rates` con fuente "promedio diario de <fuente>, N días". Queda **propuesta** hasta que una dueña la apruebe (decisión: ¿o se aprueba sola?). La consolidación solo usa tasas aprobadas.
4. **Arranque:** tu cifra de hoy (1 COP = 0.0057 MXN) se registra como observación manual con fuente "Mario 2026-10-11 (Google)", para tener trazabilidad.
5. **Siempre se guarda la moneda original.** Ningún pedido cambia; la conversión solo ocurre al mostrar el consolidado.
6. **Anomalías:** un pedido con `MONEDA_SOSPECHOSA` sin conciliar **no se convierte**; aparece como "excluido del consolidado: moneda por conciliar". El #2095, una vez corregido en Conciliación, usa su moneda corregida (COP). Como nunca se cobró, igual no suma a ventas.

**Fuente diaria (decisión):**

| Opción | Pros | Contras |
|---|---|---|
| **Banxico (SIE API)** | Oficial en México; USD FIX es la referencia fiscal | Requiere un token gratuito. **Por verificar** si publica COP diario. |
| Servicio público gratuito (p. ej. open.er-api.com) | COP y USD diario, sin llave | No oficial; cifras de mercado parecidas a las de Google |
| Combinación (**recomendada**) | USD de Banxico (oficial) + COP del servicio público, cada uno con su fuente registrada | Dos lecturas que vigilar |

---

## 6. Dependencias y plan de sprints

**Dependencias de personas:**

| Qué | Quién | Desbloquea |
|---|---|---|
| Presupuesto mensual por país y canal | Mario / Carolina | KPI 1, 8 · preguntas 1, 9 |
| Meta $300k registrada (y otras metas) | Mario | KPI 2, 8 |
| Costo por modelo | Carolina | KPI 4, 6 (a costo) · pregunta 4 |
| Cierre mensual (bancos, efectivo, gastos) y dónde registrar compromisos | Contadora / Mario | KPI 7 · pregunta 10 |
| Decisiones de bazares para P0E (ventas de tienda previas) | Carolina | KPI 1, 3, 6 |
| Permiso Lector de GA4 al usuario de sistema (ya creado) | Adrián | KPI 5 (atribución) · pregunta 6 |
| Cuenta de API de Anthropic con tope mensual | Mario | Analista |
| Tratamiento de IVA | Contadora | Etiqueta "neto de IVA" en ventas |

**Sprints (todos primero en staging; producción solo con diseño aprobado y tu autorización):**

| Sprint | Contenido | Duración aprox. | Bloqueado por |
|---|---|---|---|
| **I0** | Tipo de cambio: `fx_observations`, lectura diaria, tasa mensual propuesta, salud de la fuente, pruebas | 1–2 días | Elegir fuente |
| **I1** | Capa de métricas: RPC `f360_ai_*` / cockpit de solo lectura con `meta` de disponibilidad, para KPI 1, 2, 3, 5, 6, 8 (+ los "FALTA" de 4 y 7). Pruebas SQL de permisos y de "no inventa". | 2–3 días | — |
| **I2** | CEO Cockpit `/direccion` en staging, con E2E en escritorio y celular | 2 días | I1 |
| **I3** | Analista MVP: `f360-analyst`, interfaz de proveedor, 10 herramientas, auditoría, topes de consumo, pantalla `/inteligencia` | 3 días | I1 + llave de API |
| **I4** | Endurecimiento: verificador de números, pruebas de inyección, set de evaluación con las 10 preguntas (respuestas esperadas y "falta" donde corresponde), costos reales medidos | 2 días | I3 |
| **I5** | Pase a producción (migraciones + función + panel) con checklist | ½ día | Tu aprobación |

Los sprints I0 e I1 pueden ir en paralelo. El analista y el cockpit comparten I1, así que avanzan juntos sin duplicar cálculos.

---

## 7. Costo de uso de IA y controles de consumo

**Supuestos por pregunta:**
- 3 a 5 llamadas al modelo (pregunta → herramientas → respuesta);
- unos 6,000 tokens fijos (instrucciones + catálogo de herramientas), cacheables;
- 2,000 a 5,000 tokens por resultado de herramienta (agregados);
- unos 1,500 tokens de respuesta.

En total, de **25,000 a 40,000 tokens de entrada** y unos **2,000 de salida** por pregunta.

**Estimación** (con un modelo de gama media de Claude; **precios por confirmar** en la página de precios de Anthropic antes de aprobar; ejemplo con USD 3 por millón de entrada y USD 15 por millón de salida):

| Uso | Preguntas/mes | Costo aprox./mes |
|---|---|---|
| Ligero (2 personas × 5 al día) | ~300 | USD 30–45 |
| Normal (2 × 15 al día) | ~900 | USD 90–135 |
| Con caché de instrucciones | — | 30–40% menos |

El cockpit **no usa IA**: es consulta directa y no tiene costo por uso.

**Controles (en la función, antes de llamar al modelo):**
1. **Tope diario por usuaria** (propuesto: 40 preguntas). Al llegar al tope, la respuesta dice "llegaste al límite de hoy".
2. **Presupuesto mensual duro** (propuesto: USD 100). Se calcula con los tokens registrados en `ai_queries`. Al 80% se avisa en la bandeja y al 100% se detiene. Además se configura un tope en la consola de Anthropic como segunda barrera.
3. **Límites por pregunta:** máximo 6 llamadas a herramientas, respuesta de máximo 1,500 tokens y 60 s de tiempo.
4. **Modelo por configuración:** uno de gama media por defecto; el más grande solo si se aprueba.
5. **Reporte mensual** en `/inteligencia`: preguntas, tokens, costo y costo por persona.

---

## 8. Riesgos y contradicciones señalados

1. **Guard del panel vs. llave de IA** (§0): se resuelve con la Edge Function. No propongo relajar el guard.
2. **Caída de septiembre en ecommerce MX:** posible hueco de datos. Revisar con Woo y el historial de webhooks antes de fijar metas o presupuestos con esa base.
3. **Ventas de tienda:** hasta P0E, cualquier total "México" mezcla tienda medida desde el 8-oct con tienda sin medir. El cockpit lo marca como PARCIAL.
4. **ROAS:** el que reporta Meta nunca se mostrará como si fuera nuestro. Mientras no haya atribución propia se muestran **MER** y **CPA**, que no dependen de atribución.
5. **Monedas:** sin tasa aprobada no hay consolidado. Colombia se muestra en COP y su gasto en MXN, lado a lado y sin dividir.

**Siguiente paso: nada. Espero tu aprobación** del diseño, de las 10 preguntas (o tus cambios) y de las decisiones de §0 y §5 antes de crear cualquier migración o función.
