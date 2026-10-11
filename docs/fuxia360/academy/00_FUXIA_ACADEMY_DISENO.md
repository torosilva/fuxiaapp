# Fuxia Academy · Diseño v2: dos escuelas (Sales P0 · Ejecutiva P1)

> 2026-10-11 · rama `fuxia-360` · revisión de Mario a b9abba4: **cambio de prioridad**.
> - **Fuxia Sales Academy (P0):** capacitar a las vendedoras en producto y técnicas de venta.
> - **Fuxia Executive Academy (P1):** el programa de 30 clases de Mario, conservado en `01_ESCUELA_EJECUTIVA.md`.
>
> **Solo diseño.** Sin migraciones, sin código, sin despliegues. No se tocó producción, staging, WooCommerce ni Hilo.
> Las cifras de producto y vendedoras vienen de **una** consulta agregada de solo lectura a producción, hecha hoy con `scripts/f360/prod_read.sh` (sin datos personales). Una segunda consulta de detalle fue bloqueada por permisos y queda como tarea de A0 (§9.1).
> **A0 no está autorizado.** Este documento espera tu aprobación.

---

## 0. Resumen para Mario (en simple)

**Qué cambia.** `/academy` pasa a ser la puerta de **dos escuelas**:

- **Sales Academy**, para las vendedoras, desde el **teléfono**. Ven sus cursos pendientes, estudian fichas reales de producto, hacen microlecciones de 2 a 5 minutos, presentan evaluaciones, reciben retroalimentación, se certifican, descargan su diploma en PDF y juntan **XP** (avance) y **Puntos Academy** (canjeables más adelante).
- **Escuela Ejecutiva**, solo para ti al inicio. Es el diseño de b9abba4, que se construye después.

**Las vendedoras no ven nada sensible.**
- Entran con su cuenta actual (código por WhatsApp).
- No reciben ningún rol nuevo en Fuxia 360.
- No pueden abrir Dirección, Inteligencia, Finanzas ni la Escuela Ejecutiva. La base de datos lo niega aunque alguien escriba la dirección a mano.

**Carolina aprueba.** Ningún contenido de producto se publica sin su aprobación. Lo que todavía no está validado se muestra como **"pendiente de validación"** y nunca se enseña como dato.

**Los puntos son seguros desde el diseño.**
- Viven en un **libro de movimientos que no se puede borrar ni editar**.
- Nadie puede asignarse puntos a sí mismo. Un mismo logro no puede pagar dos veces.
- Los **canjes reales quedan apagados** desde la base de datos hasta que apruebes reglas, presupuesto, stock y entrega.
- No se toca nada de los puntos de las clientas.

**Lo que ya existe y sirve (producción, 11-oct):**

| Dato | Ballerinas |
|---|---|
| Modelos | **32** (28 activos) |
| Fotos | **32/32** |
| Tallas | **32/32**; los 28 activos van del **35 al 40** |
| Ficha de producto **validada por Carolina** (`f360.product_knowledge`) | **27/32** |
| Material exterior | 26/32 |
| Notas de comodidad | 27/32 |
| **Cuidados** | **0/32**: pendiente |
| Beneficios, objeciones, recomendaciones comerciales | **No existen** en ningún sistema: pendientes |
| Vendedoras | **4 activas** + 1 pendiente, todas en **1 tienda** |

En una frase: el primer curso se puede armar con **fichas reales de 27 modelos**. Cuidados, beneficios, objeciones, políticas y la historia de la marca **los tiene que dar Carolina** en A0.

### Decisiones que necesito de ti

1. **Dónde estudian las vendedoras.** Recomiendo **web en el teléfono** (admin-web, entrando con su código de WhatsApp) para el MVP. Las pantallas nativas en la app de vendedora vienen después, sobre la misma base. (§12.1)
2. **Valores de puntos y XP.** En §7.4 propongo valores. No se activan hasta que los apruebes.
3. **Verificación pública del diploma:** ¿muestra nombre y primera letra del apellido, o el nombre completo? (§6.4)
4. **Ranking.** ¿Las vendedoras ven un ranking de XP de su tienda, o solo su propio progreso? Recomiendo solo su progreso + el avance del equipo sin nombres para el MVP.
5. **Beneficios del producto.** ¿Son "uso interno de venta" (viven en Academy) o hechos para la clienta (deberían vivir en la ficha de producto que también usan la tienda en línea y Hilo)? (§9.3)
6. **Orden de sprints:** acepto tu orden con dos ajustes chicos (§15).

---

## 1. Qué se reutiliza de b9abba4, qué cambia y qué se pospone

| Tema | b9abba4 | v2 |
|---|---|---|
| Ruta `/academy` en el grupo `(app)`, sesión, layout y Shell | Diseñado | **Se reutiliza.** `/academy` es la entrada común. |
| Acceso | Candado de Dirección + 2FA para todo | **Cambia.** Permiso por escuela (§4): vendedoras sin rol nuevo; Ejecutiva con permiso propio **+** candado de Dirección. |
| Contenido | Archivos en el repo | **Cambia.** Motor de contenido **versionado en la base** con borrador → revisión → aprobado → publicado (§5). Se necesita porque pediste editar cursos desde el panel y que Carolina apruebe. |
| Pasos de la clase, guardado automático, retomar donde quedaste | Diseñado | **Se reutiliza.** Para Sales, en formato microlección (§12). |
| Calificación del lado del servidor, claves que nunca llegan al navegador | Diseñado | **Se reutiliza**, extendido a certificaciones (§6). |
| `attempts` append-only, dominio por habilidad, repaso espaciado | Diseñado | **Se reutiliza** en las dos escuelas. |
| Tiempo estudiado | Diseñado | **Se reutiliza.** |
| Niveles, certificaciones, diploma PDF, verificación | — | **Nuevo** (§6). |
| XP y Puntos Academy, libro de puntos, catálogo y canjes | — | **Nuevo** (§7, §8). |
| Fichas educativas de producto | — | **Nuevo**, sobre `f360.product_knowledge` existente (§9). |
| Panel de administración | Solo límites de IA | **Nuevo** (§11). |
| Tutor ejecutivo (Edge Function, controles de consumo, verificador) | Diseñado | **Se pospone a A7** (Escuela Ejecutiva). |
| Tutor comercial | — | **Nuevo, pospuesto a A6**; solo contenido aprobado (§14). |
| 30 clases ejecutivas y casos con datos reales | Diseñado | **Se conserva íntegro, pospuesto a A7** (`01_ESCUELA_EJECUTIVA.md`). |
| Hallazgos del analista (`tool_choice` forzado, precio de caché, actor del log) | Señalados | Siguen vigentes y fuera de Academy. |

---

## 2. Diagnóstico adicional (lo que la v2 necesitaba saber)

### 2.1 Identidad y acceso de vendedoras

| Hecho | Evidencia | Consecuencia |
|---|---|---|
| Roles de Fuxia 360: `owner`, `operator`, `seller`, `viewer` | `supabase/migrations/20260930000100_f360_c1_locations_roles.sql:15-19` | `seller` ya existe. **Academy no crea ni cambia roles.** |
| Vendedoras dadas de alta desde el admin (nombre, WhatsApp, tienda, PIN); la activación nunca degrada a una dueña | `supabase/migrations/20261013000100_f360_sellers_admin.sql:15-28`, `activate_seller` `:40-62` | La alumna de Sales se **deriva** de `f360.sellers` (`status = 'activa'` + cuenta). No hace falta otro alta. La tienda sale de `location_id`. |
| El turno con PIN es para **operar** (vender, transferir); leer no lo requiere | `supabase/migrations/20261001000100_f360_s02_seller_sessions.sql:1-12` | Estudiar no es operar: **no pide PIN ni turno**. |
| El admin web ya acepta entrada por código de WhatsApp | `admin-web/src/app/login/actions.ts:37-56` (`whatsapp-otp`) | Una vendedora puede entrar desde el navegador del teléfono sin contraseña nueva. |
| Producción: **4 vendedoras activas + 1 pendiente**, todas en **1 tienda**; en `user_roles` hay 3 `seller` y 2 `owner` | consulta de solo lectura, 11-oct | 4 fichas activas contra 3 roles `seller`: una ficha activa está sobre una cuenta de dueña. Es correcto por `activate_seller` y hay que tenerlo en cuenta: **esa persona no puede autoasignarse puntos** (§7.3). |
| El menú del admin muestra a `seller` las entradas sin `admin` (Inicio, Avisos, Inventario, Transferencias, Productos) | `admin-web/src/components/Shell.tsx:57-61` | Lo que una vendedora ya ve hoy no cambia. Academy agrega una entrada. |

### 2.2 Puntos de clientas (no se reutilizan)

Los puntos de clientas viven en `public.loyalty_cards`, `public.rewards`, `public.tier_config`, `public.free_pair_rewards` y `public.birthday_rewards` (`supabase/migrations/20260924000000_baseline_live_public_schema.sql:392-721`). Los calculan las funciones `calculate-points`, `loyalty-credit` y `admin-points` (`fuxia-native/supabase/functions/`).

**Academy no lee, no escribe y no reusa ninguno.** El nombre visible es **"Puntos Academy"**, para que nadie los confunda con los puntos de una clienta. Si una vendedora también es clienta, sus dos saldos están separados.

### 2.3 Producto: ver §9.

---

## 3. Arquitectura con dos escuelas

```
admin-web (Next.js 16)                              Supabase (Postgres)
/academy                ─ entrada común             esquema f360_academy  (nuevo, aditivo)
  /academy (Sales)      ─ vendedora, móvil            motor:  courses · course_versions · lessons · lesson_versions
  /academy/fichas       ─ fichas de producto                  items (banco) · assessments · enrollments
  /academy/certificados ─ diplomas PDF                        lesson_progress · attempts · study_time
  /academy/puntos       ─ XP, saldo, movimientos      logros: certificates · xp_events · points_rules · points_ledger
  /academy/ejecutiva    ─ Escuela Ejecutiva (P1)      premios: rewards · reward_changes · redemptions (apagado)
  /academy/admin        ─ panel                       acceso: grants · grant_changes · admin_events
/verificar/[código]     ─ pública, sin sesión         IA (A6/A7): tutor_settings (una fila por tutor) · tutor_log
         │ server actions / route handlers
         ▼                                           Lecturas existentes, sin cambios:
RPC public.f360_academy_*  (SECURITY DEFINER,          f360.sellers · f360.locations · f360.products
  search_path fijo, deciden con auth.uid())            f360.product_media · f360.product_sizes
                                                       f360.product_knowledge_public (solo validado)
Edge Functions (después): f360-academy-sales-tutor (A6) · f360-academy-exec-tutor (A7)
```

**Principios:**
- **Un motor, dos escuelas.** Todo lleva `school ∈ {sales, executive}`. Cada RPC verifica acceso **por escuela** antes de leer o escribir.
- **Sin duplicar.**
  - El producto se lee de `f360.products` y `f360.product_knowledge_public`; Academy guarda solo **referencias versionadas** (§9.4).
  - La vendedora y su tienda salen de `f360.sellers`.
  - La identidad y el 2FA son los de Supabase Auth y el candado de Dirección.
- **Sin tocar otros módulos.**
  - Una entrada en `Shell.tsx`.
  - Ocultar la barra inferior del Shell dentro de `/academy` en el teléfono (§12).
  - Una ruta pública `/verificar`.
  - Nada en Growth, Inteligencia, Cockpit, Estrategia, Inventario, WooCommerce ni Hilo.
- **Sin infraestructura nueva.** Sin servicios externos. Los PDF se generan en el servidor de Next (librería `pdf-lib`, JavaScript puro, sin binarios) y no se guardan: se crean al pedirlos desde el certificado.

---

## 4. Matriz de roles y permisos

**Roles de Academy** (tabla `f360_academy.grants`): son permisos **de Academy**, no roles de Fuxia 360. Nadie recibe `owner` ni `operator` por usar Academy.

| Rol Academy | Cómo se obtiene | Quién, al inicio |
|---|---|---|
| **Alumna Sales** | **Derivado**: `f360.sellers.status = 'activa'` con cuenta. Al desactivarla en Vendedoras, pierde acceso sola. También por permiso explícito (p. ej., una encargada nueva para probar) | Las 4 vendedoras activas |
| **Alumno Ejecutivo** | Permiso explícito **+** miembro de Dirección **+** sesión con 2FA (aal2) | Mario |
| **Editora** | Permiso explícito | Carolina, Mario |
| **Aprobadora de contenido** | Alcance `academy_content` en **`f360.approval_scopes`** (existente; ver nota abajo) | Carolina |
| **Administrador Academy** | Permiso explícito; funciones sensibles con 2FA | Mario |

**Aprobaciones = `f360.approval_scopes` (no una tabla nueva).** "Quién aprueba qué" ya existe en `f360.approval_scopes` + `f360.can_approve(scope, user)` (`supabase/migrations/20261023000200_f360_approval_scopes.sql`, hoy con `fx_rate`, `budget`, `close` y, desde `20261025000100`, `store_discount`). Academy **agrega alcances** a ese CHECK, conservando los existentes (incluido `store_discount`):
- `academy_content`: publicar contenido de producto/comercial (Carolina);
- `academy_points`: aprobar versiones de reglas y ajustes manuales de puntos;
- `academy_rewards`: aprobar premios del catálogo y, en A5, canjes.

`f360_academy.grants` queda **solo** para lo que no es una aprobación: Editora, Alumno Ejecutivo, Administrador y alumnas explícitas. La migración que amplíe el CHECK se coordina con quien esté tocando `approval_scopes` en ese momento (dry-run antes del push).

Los permisos explícitos se cargan con un script revisado (con evidencia de identidad, como `board_members`). Cada cambio queda en `grant_changes`, que es append-only. Solo el Administrador da permisos, con 2FA, y **nunca a sí mismo**.

| Acción | Alumna Sales | Alumno Ejecutivo | Editora | Aprobadora | Admin | Control reforzado |
|---|---|---|---|---|---|---|
| Ver y estudiar cursos Sales publicados que le corresponden | ✓ | — | vista previa | vista previa | vista previa | — |
| Ver y estudiar la Escuela Ejecutiva | ✗ | ✓ | ✗ | ✗ | ✗ (salvo que también sea alumno) | aal2 + Dirección |
| Ver su progreso, XP, saldo, movimientos y diplomas | ✓ (solo los suyos) | ✓ (solo los suyos) | — | — | — | — |
| Crear y editar borradores | ✗ | ✗ | ✓ | ✓ | ✓ | — |
| Aprobar y publicar contenido **de producto o comercial** | ✗ | ✗ | ✗ | ✓ | ✗ | Carolina es la autoridad (§10) |
| Aprobar y publicar contenido **ejecutivo** | ✗ | ✗ | ✗ | ✗ | ✓ | aal2 |
| Ver progreso por vendedora y tienda | ✗ | ✗ | ✗ | ✓ | ✓ | registrado en `admin_events` |
| Asignar cursos y fechas límite | ✗ | ✗ | ✗ | ✓ | ✓ | — |
| Revocar un certificado | ✗ | ✗ | ✗ | ✗ | ✓ | aal2 + motivo; revierte los puntos |
| Configurar reglas de puntos y XP | ✗ | ✗ | ✗ | ✗ | propone | aal2; **la versión nueva la aprueba otra persona** (Carolina) |
| Ajuste manual de puntos | ✗ | ✗ | ✗ | aprueba | solicita | aal2 en ambas; dos personas distintas; nunca a sí mismo |
| Catálogo de recompensas | ✗ | ✗ | ✗ | aprueba premio | crea; fija costo y presupuesto | aal2 |
| Encender canjes reales | ✗ | ✗ | ✗ | ✗ | ✗ en el MVP | Bandera en la base, **apagada**; se enciende solo en A5 con aprobación explícita (§8.3) |
| Datos de Dirección, Inteligencia, Finanzas | ✗ | según su acceso de Dirección | ✗ | según su acceso | según su acceso | Sin cambios: el candado existente |

**Dónde se aplica:** en cada RPC `SECURITY DEFINER`, con `auth.uid()`, nunca con datos enviados por el navegador. Las tablas tienen RLS activo **sin políticas**, y se revocan `SELECT/INSERT/UPDATE/DELETE` a `anon` y `authenticated`. El menú y las páginas solo son pistas: una página sin permiso responde `notFound()`.

**2FA.** Mario y Carolina, como miembros de Dirección, usan el flujo de segundo factor existente (`admin-web/src/app/(app)/estrategia/BoardMfa.tsx`). Las vendedoras **no** necesitan 2FA: solo pueden leer su escuela y responder sus evaluaciones.

---

## 5. Modelo de cursos, lecciones, evaluaciones y progreso

### 5.1 Contenido versionado (las dos escuelas)

| Tabla | Qué guarda |
|---|---|
| `courses` | `school`, `key`, título, tipo (`nivel` / `microcert` / `programa`), `level_key` (§6), prerequisitos (`course_key[]`), orden, `active_version` |
| `course_versions` | Versión del curso: lista ordenada de lecciones (`lesson_version_id[]`) + evaluación final. Estado: `borrador → en_revision → aprobado → publicado → retirado`. **Inmutable una vez publicada.** |
| `lessons` / `lesson_versions` | Microlección: bloques `jsonb` validados por esquema en el servidor (texto, foto, ficha de producto, comparación, pregunta, resumen), `product_refs` (§9.4), duración estimada, habilidades, autor, envío a revisión, quién aprobó y cuándo |
| `items` | Banco de reactivos: tipo (opción múltiple, verdadero/falso, numérico, ordenar, relacionar, **"¿qué le dirías a la clienta?"**), enunciado, opciones, **`answer_key` (nunca sale a la alumna)**, explicación, habilidad, dificultad, `product_ref` opcional |
| `assessments` | Por curso o versión: tipo (`quiz` de lección / `final`), **nota mínima configurable**, número de reactivos tomados del banco, intentos por día, espera entre intentos, si baraja |
| `approvals` | Append-only: cada envío, aprobación, rechazo (con comentario) y publicación |

### 5.2 Progreso (por persona)

| Tabla | Qué guarda |
|---|---|
| `enrollments` | Persona × curso: **versión fija**, origen (`auto` por nivel / `asignado` por admin), fecha límite, **tienda al inscribirse** (para reportes históricos), estado |
| `lesson_progress` | Persona × lección: versión, `step_index`, estado, segundos activos. Retoma exactamente donde quedó. |
| `attempts` | **Append-only.** Respuesta, puntaje y quién calificó (`regla` / `ia`, esto último solo en ejecutiva y con rúbrica). Una evaluación final guarda los reactivos que se le presentaron. |
| `study_time` | Persona × día, segundos activos (pulso cada 60 s con la pestaña visible) |

**Vistas:** `v_skill_mastery` y `v_review_due` (de b9abba4), `v_my_courses` (pendientes, en curso, completados, vencidos), `v_team_progress` (admin: por vendedora y por tienda).

### 5.3 Reglas de calificación (heredadas de b9abba4)

- El navegador manda **la respuesta**, nunca la calificación.
- El servidor califica con la clave guardada en la base y escribe el intento con una función `SECURITY DEFINER`.
- Las evaluaciones finales toman reactivos al azar del banco. Hay límite de intentos por día (propuesta: 3) y espera entre intentos (propuesta: 1 h).
- La retroalimentación muestra **por qué** la respuesta es correcta, citando la ficha de producto aprobada. En la evaluación final, la retroalimentación detallada se muestra **después** de cerrar el intento, para que no se pueda ir corrigiendo pregunta por pregunta.

---

## 6. Niveles, certificaciones y diplomas

### 6.1 Niveles (Sales)

Cada nivel tiene contenido obligatorio, una evaluación final con **nota mínima configurable** (propuesta: 80) y diploma verificable. El nivel siguiente se abre al certificar el anterior.

| Nivel | Para qué | Contenido obligatorio (resumen) | Requisito extra (propuesta) |
|---|---|---|---|
| **Fuxia Starter** | Atender con seguridad desde la primera semana | La marca (Carolina); **Ballerinas**: modelos, tallas, horma, materiales, comodidad; cuidados; atención básica; políticas de tienda (Carolina) | — |
| **Product Expert** | Dominar todo el catálogo | Todas las líneas (Ballerinas, Sandalias, Botas, Kids cuando exista); comparar modelos; recomendar por uso, pie y ocasión; venta cruzada con producto real | Starter |
| **Sales Pro** | Vender más y mejor | Descubrimiento de necesidad, presentación, objeciones (las validadas por Carolina), cierre, apartados y sobre pedido según las políticas vigentes, seguimiento por WhatsApp | Product Expert |
| **Fuxia Master** | Referente de tienda | Experiencia de marca, enseñar a otras, lectura de su propio desempeño, lanzamientos | Sales Pro + **validación práctica** firmada por una aprobadora (no se puede certificar solo en línea) |

Las **técnicas de venta** son pedagogía general. Las **políticas** (cambios, devoluciones, garantías, apartados, envíos, descuentos permitidos) salen **solo** de texto aprobado por Carolina. Si no hay texto aprobado, el bloque queda "pendiente" y el curso **no se puede publicar** (§10).

### 6.2 Microcertificaciones

Son cursos cortos (`tipo = microcert`) por **colección o modelo nuevo**. Ejemplo: "Lanzamiento Otoño · 4 modelos", con 3–5 microlecciones y 10 reactivos.
- Se arman desde las fichas validadas de esos modelos.
- Se pueden asignar a todas las vendedoras activas con fecha límite.
- No abren niveles; dan XP y, si la regla lo dice, Puntos Academy.

### 6.3 Certificados

Tabla `certificates`:
- id (uuid);
- `code` público: 10 caracteres aleatorios, base32 sin caracteres ambiguos; no secuencial ni adivinable;
- persona;
- **nombre como quedó en el certificado** (copia de `f360.sellers.name` al emitir);
- curso, versión y nivel;
- calificación;
- fecha;
- estado `vigente` / `revocado`, con motivo, quién y cuándo.

**Emisión:** **solo** dentro de la función que califica la evaluación final, en la misma transacción, cuando:
- todas las lecciones obligatorias están completas;
- la nota es ≥ la mínima;
- se cumplen los prerequisitos;
- si aplica, existe la validación práctica.

Ningún endpoint permite "emitir" desde fuera. **Revocación:** solo el Admin, con 2FA y motivo. Escribe un movimiento de reversa de los puntos (§7) y el diploma deja de verificarse como vigente.

### 6.4 Diploma PDF y verificación

- `GET /academy/certificados/[id]/pdf` (route handler) comprueba con una RPC que el certificado es **de quien lo pide** (o que quien lo pide es Admin o Aprobadora) y genera el PDF al vuelo con `pdf-lib`. El PDF lleva nombre, nivel, fecha, calificación, código y la URL `…/verificar/<código>`; en A2+ se agrega un código QR.
- `/verificar/[código]` es **pública y sin sesión**. Muestra nivel, fecha, estado (vigente o revocado) y el nombre según tu decisión 3. Por omisión propongo nombre + inicial del apellido.
  - Nunca muestra teléfono, tienda, calificación ni otros certificados.
  - Límite de consultas por IP.
  - Respuesta igual para "no existe" y "mal escrito".
- Tipografía: se usa la de la marca **solo si su licencia permite incrustarla en PDF**; si no, una libre. Se confirma en A2.

---

## 7. XP y Puntos Academy (modelo seguro)

### 7.1 Dos cosas distintas

| | XP | Puntos Academy |
|---|---|---|
| Qué es | Avance y reconocimiento | Saldo canjeable (cuando se encienda) |
| Valor económico | Ninguno | Sí: es un compromiso de Fuxia |
| Se gana por | Terminar lecciones y microcerts, rachas, aprobar a la primera | **Solo** certificaciones (niveles y microcerts) y bonos aprobados |
| Se gasta | Nunca | En canjes (A5) |
| Tabla | `xp_events` (append-only) | `points_ledger` (append-only, con controles §7.3) |

### 7.2 `points_ledger`

```
id · auth_user_id · delta (entero, ≠ 0) · kind ∈ {certificacion, bono_aprobado, ajuste_manual, canje, reversa, vencimiento}
source_kind · source_ref       ← UNIQUE (source_kind, source_ref, kind): un mismo logro no paga dos veces
rule_version                   ← regla con la que se calculó
created_by (uid o 'sistema') · approved_by (uid, ajustes) · reason · at
```

- El saldo es la suma del libro (`v_points_balance`). **No hay columna de saldo editable.**
- Los movimientos no se editan ni se borran (trigger `reject_audit_change`, como en el resto de Fuxia 360). Un error se corrige con un movimiento de `reversa` que referencia al original.

### 7.3 Controles

| Riesgo | Control |
|---|---|
| Autoasignación | Sin `INSERT` para `authenticated`. Solo escriben funciones `SECURITY DEFINER`. Un ajuste manual nunca puede tener `auth_user_id = auth.uid()` de quien lo pide ni de quien lo aprueba. |
| Duplicación | Índice único `(source_kind, source_ref, kind)`. La certificación usa `source_ref = certificate.id`. Reintentos y doble clic no pagan dos veces. |
| Puntos sin logro real | La única fuente automática es la emisión del certificado, que exige la evaluación calificada en el servidor (§6.3). |
| Ajustes manuales | Pedido por el Admin con motivo; aprobado por **otra persona** (Aprobadora); ambos con 2FA; tope por ajuste (propuesta: el valor de un nivel). Todo queda en `admin_events`. |
| Saldo negativo o doble gasto (A5) | El canje toma un bloqueo por persona (`pg_advisory_xact_lock`), recalcula el saldo dentro de la transacción y rechaza si no alcanza. |
| Cambiar la regla para favorecer a alguien | Reglas **versionadas** (`points_rules`): nunca se editan, se crea una versión nueva. Propone el Admin y **aprueba otra persona**. Cada movimiento guarda `rule_version`. Una regla nueva no recalcula el pasado. |
| Revocar un certificado | Movimiento de `reversa` automático por los puntos que dio. |
| Persona con doble papel (p. ej., dueña con ficha de vendedora, §2.1) | Puede estudiar y ganar puntos **automáticos**, pero no puede pedir ni aprobar ajustes sobre sí misma ni aprobar un premio cuyo canje le toque. |

### 7.4 Valores propuestos (requieren tu aprobación; no se activan sin ella)

| Logro | XP | Puntos Academy |
|---|---|---|
| Microlección terminada (primera vez) | 10 | — |
| Quiz de lección aprobado a la primera | +5 | — |
| Racha de 5 días | 25 | — |
| Microcertificación | 50 | por definir por microcert (p. ej., 50) |
| Fuxia Starter | 200 | 100 |
| Product Expert | 300 | 200 |
| Sales Pro | 400 | 300 |
| Fuxia Master | 500 | 500 |

Mientras no apruebes la regla v1, los certificados se emiten igual pero **no generan puntos**. Cuando la apruebes, la regla puede aplicarse **una vez** hacia atrás a los certificados ya emitidos, con su propio `source_ref`, para no castigar a quien se certificó antes.

---

## 8. Catálogo de recompensas y canjes futuros

### 8.1 Catálogo (A4, sin canjes)

`rewards` guarda:
- nombre y foto;
- tipo (`par`, `accesorio`, `kit`, `beneficio`);
- costo en Puntos Academy;
- **costo para Fuxia** (MXN, referencia para el presupuesto);
- `variant_id` opcional si es un par;
- stock asignado;
- vigencia;
- estado `borrador → aprobado_carolina → activo → retirado`.

Cada cambio queda en `reward_changes` (append-only). La vendedora ve el catálogo con el botón **"Canje próximamente"**: sirve para motivar sin prometer fechas.

### 8.2 Flujo de canje (diseño para A5)

```
solicitado ──(Admin o Aprobadora revisa stock y saldo)──▶ aprobado ──▶ entregado (con firma de recibido)
     │                                                       │
     └──▶ rechazado (sin movimiento)                         └──▶ cancelado (movimiento de reversa)
```

- Al **aprobar**: un movimiento `canje` (negativo) en el libro, en la misma transacción que reserva el stock asignado del premio.
- Si el premio es **un par Fuxia**, la **entrega** se registra como un movimiento de inventario **auditable** por el flujo de inventario existente, con un motivo nuevo ("premio interno"). Nunca se descuenta inventario desde Academy directamente (regla 8 del contrato).

### 8.3 Lo que debe aprobarse antes de encender canjes (A5)

1. Reglas y valores de puntos (§7.4).
2. Presupuesto mensual de premios y quién lo controla.
3. Stock asignado por premio y de qué ubicación sale.
4. Proceso de entrega y quién firma.
5. **Tratamiento fiscal y laboral** de los premios a empleadas: lo confirma la contadora. No asumo ninguna regla.
6. Prueba de seguridad del flujo (doble canje, saldo negativo, autoaprobación).

**Hasta entonces:** `f360_academy.settings.redemptions_enabled = false`. La función de canje **revisa esa bandera en la base** y rechaza. Encenderla requiere al Admin con 2FA, un motivo y la referencia de la aprobación, y queda en `admin_events`.

---

## 9. Product Knowledge: auditoría y fichas educativas

### 9.1 Qué existe hoy (Ballerinas, producción 11-oct)

| Campo de la ficha | Fuente | Cobertura | Uso en Academy |
|---|---|---|---|
| Fotografías | `f360.product_media` / `product_primary_image` (`supabase/migrations/20260926000100_f360_p21_product_master.sql:91-115`) | **32/32** | ✓ Real |
| Línea de negocio | `f360.products.category_key` (`…p21_product_master.sql:22-29`) | 32/32 | ✓ Real |
| Tallas | `f360.product_sizes` (`supabase/migrations/20260925010000_f360_admin_v1_inventory_core.sql`) | 32/32; activos **35–40** | ✓ Real, sin conversiones a otras escalas |
| Colores | `f360.product_colors` | por medir en A0 | ✓ Real |
| Ajuste de talla, horma, ancho, punta, tacón | `f360.product_knowledge` (`supabase/migrations/20261010000500_f360_product_knowledge.sql:12-31`), **solo validado** vía `product_knowledge_public` (`:60-72`) | **27/32 validadas** | ✓ Real |
| Material exterior | idem | 26/32 | ✓ Real |
| Forro, suela | idem | **no medido** (consulta bloqueada) | A0 |
| Comodidad | idem | 27/32 | ✓ Real |
| **Cuidados** | `care_instructions` | **0/32** | ⏳ Pendiente de Carolina |
| Descripción larga | `f360.products.description` | 32/32, texto libre **sin flujo de validación** | ✗ No se enseña como dato; Carolina puede tomar frases al aprobar |
| Descripción corta | `short_description` | 1/32 | ✗ |
| **Beneficios** | — | **No existe** | ⏳ Pendiente (§9.3) |
| **Objeciones frecuentes** | — | **No existe** | ⏳ Pendiente; Carolina y las vendedoras |
| **Recomendaciones comerciales** (con qué combinar, a quién recomendar) | — | **No existe** | ⏳ Pendiente |
| Precio | `f360.products.regular_price`, `f360.product_prices` | existe | Solo si Carolina decide enseñarlo; los precios cambian y no deben quedar fijos en un diploma |
| Enlace a WooCommerce | `f360.woo_variant_links` (`supabase/migrations/20261007000200_f360_d2_legacy_channel_links.sql`); `f360.products.wc_product_id` está en **0/32** y no se usa | — | No hace falta: Woo es el canal, no la fuente de la ficha |

**Tareas de A0 (lectura):** medir forro, suela, punta, tacón, nota de talla y colores por modelo, y por qué 5 modelos no tienen ficha validada (hay 4 modelos archivados; falta confirmar si son los mismos). Requiere tu permiso para otra consulta de solo lectura a producción, o hacerla en staging, que es copia anonimizada de producción.

### 9.2 Ficha educativa por modelo (pantalla)

```
[ foto grande · carrusel por color ]
PAULA · Ballerinas                       Ficha validada por Carolina · v3 · 08-oct
Tallas 35–40 · Talla exacta → "pide tu talla habitual"
Horma cómoda · Punta almendrada · Tacón 1 cm
Materiales: exterior ___ · forro ___ · suela ___
Comodidad: "___"
Cuidados: ⏳ pendiente de validación
Beneficios: ⏳ pendiente de validación
"Cuando la clienta dice…"  (objeciones)  ⏳ pendiente de validación
Recomiéndala para…                       ⏳ pendiente de validación
[ Practicar este modelo · 5 preguntas ]
```

- Lo validado se muestra tal cual, con la versión y la fecha de validación.
- Lo que falta dice **"pendiente de validación"**. No se rellena ni se estima.
- Las preguntas de práctica se **generan con plantillas fijas** (sin IA) desde los campos validados. Ejemplo: "¿Qué talla le recomiendas a una clienta que usa 37 en otro modelo de talla exacta?" → "37". Las plantillas las aprueba Carolina una vez.

### 9.3 Dónde viven los campos nuevos (decisión 5)

- **Opción A (recomendada para el MVP):** beneficios, objeciones y recomendaciones viven en Academy (`product_sales_notes`, versionadas y aprobadas por Carolina), marcadas como **uso interno de venta**. No tocan la tabla que usan la tienda en línea y Hilo.
- **Opción B:** agregar columnas a `f360.product_knowledge` para que la tienda en línea y Hilo también las usen. Es más coherente a largo plazo, pero cambia una tabla compartida y la página de producto. Requiere su propio sprint con el equipo de storefront.
- **Cuidados** sí pertenece a `f360.product_knowledge` (el campo ya existe). Carolina lo llena en la ficha de producto existente y Academy lo lee. **No se duplica.**

### 9.4 Referencias versionadas

Una lección guarda `product_refs = [{product_id, knowledge_version}]`. Al publicarla, se guarda una **foto** de la ficha validada en esa versión.
- Si Carolina vuelve a validar una ficha (la versión sube), las lecciones que la usan aparecen en su cola como **"ficha actualizada: revisar"**.
- Las alumnas siguen viendo la versión publicada hasta que Carolina publique la nueva.
- Así nunca se enseña una mezcla de versiones ni una ficha que volvió a borrador.

---

## 10. Flujo de aprobación de contenido (Carolina)

```
Editora crea/edita ──▶ borrador ──(Enviar a revisión: valida que no falte nada obligatorio)──▶ en_revision
                                                                                                  │
          ◀── Carolina "Pedir cambios" (comentario por bloque) ◀───────────────────────────────────┤
                                                                                                  ▼
                                                     Carolina "Aprobar y publicar" ──▶ publicado (inmutable)
```

- **Quién publica:** contenido de producto o comercial, **solo la Aprobadora** (Carolina). Contenido ejecutivo, el Admin.
- **Bloqueos al enviar a revisión:** un curso no se puede enviar si:
  - alguna referencia de producto apunta a una ficha no validada;
  - hay bloques "pendiente";
  - un reactivo no tiene clave o explicación;
  - la evaluación tiene menos reactivos en el banco que los que debe presentar.
- **Si Carolina es la autora**, su aprobación es la publicación, porque ella es la autoridad de producto. Queda registrado igual en `approvals`.
- **Pantalla de Carolina:** cola "Por aprobar" → vista **como la verá la vendedora** (marco de teléfono) → comentarios por bloque → Aprobar o Pedir cambios. Debe poder hacerse desde el teléfono en 2 minutos por lección.
- Cada evento queda en `approvals` (append-only).

---

## 11. Panel de administración (`/academy/admin`)

| Pestaña | Qué hace | Quién |
|---|---|---|
| **Contenido** | Cursos → lecciones → bloques con editor de formularios (texto, foto de producto, ficha, pregunta, resumen); banco de reactivos; evaluaciones (nota mínima, intentos, espera) | Editora, Aprobadora, Admin |
| **Por aprobar** | Cola de Carolina (§10) | Aprobadora |
| **Equipo** | Progreso por vendedora y por tienda: cursos asignados, avance, vencidos, calificaciones, temas débiles del equipo; asignar curso con fecha límite | Aprobadora, Admin |
| **Certificados** | Emitidos, buscar por código, descargar, revocar (2FA + motivo) | Admin (revocar); Aprobadora (consulta) |
| **Puntos** | Reglas por versión (proponer / aprobar); movimientos con filtros; ajustes manuales (solicitar / aprobar) | Admin + Aprobadora, con 2FA |
| **Recompensas** | Catálogo, estados, stock asignado, presupuesto; bandera de canjes (solo lectura en el MVP) | Admin + Aprobadora |
| **Costos** | Puntos emitidos y en circulación, valor de referencia (puntos × costo de los premios), premios entregados (A5), consumo de IA por tutor (A6/A7) | Admin |
| **Acceso** | Permisos de Academy y su historial | Admin (2FA) |

**Costo de referencia de los puntos:** para premios que son pares, depende del **costo por par**, que hoy está en **0 registros** (`f360.product_cost_versions`). Mientras no exista, el panel muestra el costo a precio de venta y dice explícitamente que **falta el costo**.

---

## 12. Diseño mobile-first para vendedoras

### 12.1 Plataforma (decisión 1)

| Opción | A favor | En contra |
|---|---|---|
| **A · Web en el teléfono (recomendada para el MVP)** | Un solo código para alumna, Carolina y panel; el PDF sale en el servidor; sin OTA; se agrega a la pantalla de inicio | Una segunda entrada, aparte de la app (código por WhatsApp) |
| B · Pantallas nativas en `fuxia-native/app/vendedora/` | Ya viven ahí todo el día | Doble interfaz; el diploma y el panel se hacen en web de todos modos |

**Recomendación:** A en el MVP. Después, en la app de vendedora, un mosaico "Academy" que abra la web. Pantallas nativas solo si el uso lo justifica, sobre **las mismas RPC**.

### 12.2 Pantallas

Dentro de `/academy` en el teléfono, el Shell oculta su barra inferior y Academy usa la suya: **Inicio · Cursos · Fichas · Yo**.

```
INICIO                          MICROLECCIÓN (2–5 min)            RESULTADO
┌────────────────────────┐      ┌────────────────────────┐        ┌────────────────────────┐
│ Hola, Ana 👋           │      │ ▓▓▓▓▓░░░  3 de 7       │        │ ✓ 9 de 10 · Aprobado   │
│ Fuxia Starter  ▓▓▓░ 60%│      │ [ foto Paula ]         │        │ +50 XP                 │
│ [Continuar → Paula]    │      │ La Paula es de talla   │        │ Repasa: horma (1)      │
│ Pendientes (2)         │      │ exacta: tu clienta     │        │  "La Paula tiene horma │
│  • Starter · vence 18  │      │ pide su talla habitual.│        │   cómoda…" (ficha v3)  │
│  • Otoño · microcert   │      │ ¿Qué talla le das a    │        │ [Siguiente lección]    │
│ XP 320 · Puntos 0      │      │ quien usa 37?          │        └────────────────────────┘
│ Racha 3 días           │      │ (36) (37) (38)         │
└────────────────────────┘      └────────────────────────┘
YO: nivel, XP, saldo de Puntos Academy y movimientos, diplomas (Descargar PDF), recompensas ("Canje próximamente")
```

**Criterios:**
- Botones de 44 px o más.
- Una idea por pantalla.
- Funciona con una mano.
- Imágenes ligeras (las fotos ya existen en Storage).
- Guardado al terminar cada tarjeta.
- Si se pierde la señal, la respuesta se reintenta al volver y no se pierde el avance de la tarjeta.
- Textos en español sencillo, sin términos técnicos.

---

## 13. Primer curso: Fuxia Starter · Ballerinas (contenido de A0)

| Módulo | Microlecciones | Fuente | Estado hoy |
|---|---|---|---|
| 1. Bienvenida a Fuxia | Historia, qué hace distinta a una Fuxia, cómo hablamos con la clienta | **Carolina** | ⏳ Por escribir con ella |
| 2. Conoce las Ballerinas | 1 lección por grupo de modelos (≈ 5–6 lecciones para 27 modelos): foto, horma, punta, materiales, comodidad | `product_knowledge_public` + fotos | ✓ 27 modelos validados |
| 3. Tallas y ajuste | Escala 35–40; talla exacta, chica o grande; "entre dos tallas"; cómo medir y preguntar | Fichas validadas + etiquetas existentes (`knowledge_labels`, `…product_knowledge.sql:44-56`) | ✓ Real; sin conversiones |
| 4. Cuidados | Cómo explicarle a la clienta el cuidado de su par | `care_instructions` | ⏳ 0/32: Carolina |
| 5. Atención y políticas básicas | Saludo, descubrir la necesidad, presentar 2–3 opciones, cerrar; cambios, apartados y envíos **según texto aprobado** | Carolina | ⏳ |
| Evaluación final | 20 reactivos del banco, nota mínima 80 (configurable), 3 intentos/día | Banco generado desde las fichas + reactivos de Carolina | — |

**Para A0 le pido a Carolina** (cuestionario de una página por tema; Claude Code redacta el borrador y ella corrige):
1. Historia y promesa de la marca.
2. Cuidados por material.
3. Por modelo: 2 beneficios, 2 objeciones con respuesta, "recomiéndala para…".
4. Políticas vigentes de cambios, apartados y envíos.
5. Los 5 modelos sin ficha: ¿se validan o se excluyen?

**Si al cierre de A0 faltan cuidados o políticas,** el curso puede publicarse **sin** los módulos 4 y 5. Quedaría como **"Starter · Parte 1 (Producto)"**, y el nivel completo se certifica cuando existan. Esa decisión es tuya y de Carolina; no la tomo yo.

---

## 14. Tutores de IA (posteriores, separados)

| | Tutor comercial (A6) | Tutor ejecutivo (A7) |
|---|---|---|
| Edge Function | `f360-academy-sales-tutor` | `f360-academy-exec-tutor` (diseño de `01_ESCUELA_EJECUTIVA.md` §5) |
| Quién lo usa | Alumnas Sales | Alumno Ejecutivo (aal2) |
| Qué puede leer | **Solo contenido publicado de Sales** y `product_knowledge_public`, por una RPC de búsqueda de solo lectura | Lo anterior **más** las herramientas de `f360_intel_query` con la sesión del usuario |
| Qué no puede | Ventas, inventario, clientas, finanzas, Dirección, escribir nada | Escribir nada |
| Regla clave | Si la respuesta no está en contenido aprobado, dice "eso no está validado; pregúntale a Carolina" y **no inventa** materiales, tallas, beneficios ni políticas | Etiqueta REAL / SIMULADO / CÁLCULO; verificador de cifras |
| Configuración | Una fila en `tutor_settings` con presupuesto propio | Otra fila con presupuesto propio |
| Auditoría | `tutor_log` compartida con columna `tutor` | idem |
| Modelo sugerido | Claude Haiku 5.5 (USD 0.10 / 0.50 por MTok): respuestas cortas sobre texto dado | Claude Sonnet 5.5 (USD 2 / 10) |
| Costo estimado | 5 vendedoras × 10 preguntas/día ≈ **< USD 2/mes** | USD 10–20/mes (`01` §8) |

**Ninguno usa `tool_choice` forzado** (ver el hallazgo del analista en `01` §1.2).

**El MVP no usa IA: costo de IA USD 0.** La retroalimentación del MVP sale de la explicación escrita en cada reactivo y de la ficha aprobada.

---

## 15. Plan de sprints (tu orden, con dos ajustes)

**Ajustes propuestos:**
1. **El flujo mínimo de aprobación de Carolina va en A1, no después.** Sin él no se puede publicar el primer curso: o ella aprueba en la plataforma, o hay que cargar contenido "aprobado" por migración, que es justo lo que queremos evitar.
2. **El XP va en A2**, junto con la evaluación, porque se deriva de completar lecciones. **A3 queda para el libro de Puntos Academy y sus controles.** El **MVP liberable = A1 + A2 + A3**.

Cada sprint se hace primero en STAGING, en `fuxia-360`, y lleva:
- migración aditiva con `.down.sql` ensayado;
- pruebas de base de datos (`scripts/f360/db_tests.mjs`) y Playwright;
- tu aprobación antes del siguiente.

| Sprint | Entrega | Base de datos / API | Seguridad | Verificación | Aceptación |
|---|---|---|---|---|---|
| **A0 · Rediseño y contenido** | Este documento aprobado; inventario de datos faltantes por modelo; cuestionario de Carolina; borrador del curso Starter · Ballerinas (guion + banco de ≥ 60 reactivos) | Ninguno | — | Revisión de Mario y Carolina | Carolina aprueba el guion y el banco en documento |
| **A1 · Motor y acceso de vendedoras** | Esquema `f360_academy` (contenido, versiones, progreso, permisos); alumna derivada de `f360.sellers`; `/academy` móvil (Inicio, Cursos, Microlección, Fichas); editor mínimo + cola de aprobación de Carolina; carga del curso A0 como **borrador** para que Carolina lo apruebe en la plataforma | Migración + RPC `f360_academy_*`; entrada en `Shell.tsx` | RLS sin políticas; revocaciones; pruebas de acceso cruzado | Una vendedora no ve Dirección, Ejecutiva ni el progreso de otra; vendedora desactivada = sin acceso; claves fuera del bundle | Ana estudia 3 lecciones en el teléfono, cierra y retoma en la misma tarjeta |
| **A2 · Evaluaciones, certificados, diplomas, XP** | Quizzes y final con banco aleatorio, límites e intentos; retroalimentación; emisión de certificados; PDF; `/verificar`; XP; progreso por vendedora y tienda en el panel | Migración + route handler PDF; dependencia `pdf-lib` | Emisión solo transaccional; PDF solo para la dueña o el admin; verificación con límite de consultas | Pruebas: no se emite sin aprobar; no se emite dos veces; un código mal escrito no revela nada | Ana se certifica en Starter y descarga su diploma; el código se verifica |
| **A3 · Puntos Academy** | `points_rules` versionadas (aprobación de dos personas); `points_ledger`; saldo y movimientos en "Yo"; ajustes manuales con doble aprobación; revocación con reversa | Migración | Append-only; único por logro; sin autoasignación; 2FA | Pruebas adversariales: doble emisión, autoajuste, regla editada, reversa | Saldo correcto tras certificar; ningún camino crea puntos sin certificado o sin doble aprobación |
| **— MVP Sales listo (A1–A3) → promoción a producción con tu aprobación —** | | | | | |
| **A4 · Catálogo sin canjes** | `rewards` + estados + aprobación de Carolina; vista "Canje próximamente"; pestaña Costos | Migración | Bandera `redemptions_enabled = false` revisada en la base | Prueba: canjear con la bandera apagada → rechazado | Catálogo visible; canje imposible |
| **A5 · Canjes reales** | Flujo solicitar → aprobar → entregar; movimiento de inventario "premio interno" por el flujo existente | Migración + motivo de inventario nuevo (coordinado con Inventario) | Bloqueo por persona; dos personas; entrega firmada | Pruebas de concurrencia y saldo | **Solo con tu aprobación explícita de §8.3** |
| **A6 · Tutor comercial** | Edge Function, configuración y log, panel del tutor | Migración + función nueva | Solo contenido aprobado; sin datos de negocio | Evaluación adversarial: inventar talla, material o política; pedir datos de ventas | 0 respuestas con datos no aprobados |
| **A7 · Escuela Ejecutiva** | `01_ESCUELA_EJECUTIVA.md` sobre el mismo motor | según `01` | aal2 + Dirección + permiso propio | según `01` | según `01` |

Los sprints no se encadenan con Growth, Inteligencia ni otros módulos. Los puntos compartidos son pocos y van en el sprint indicado:
- `Shell.tsx` (A1);
- la ruta pública `/verificar` (A2);
- el motivo de inventario (A5);
- el actor del log de Inteligencia (A7).

---

## 16. Criterios de aceptación del primer MVP (A1 + A2 + A3, en staging y luego producción)

1. **Entrar.** Una vendedora activa entra desde el navegador de su teléfono con su código de WhatsApp y llega a `/academy` en ≤ 2 toques. Una vendedora **desactivada** en Vendedoras no puede entrar a Academy.
2. **Cursos pendientes.** Ve "Fuxia Starter · Ballerinas" como pendiente, con avance y fecha límite si se asignó.
3. **Fichas reales.** Cada ficha muestra **solo** datos validados por Carolina, con versión y fecha. Lo no validado dice "pendiente de validación". No aparece ningún material, talla, beneficio ni política que no venga de una fuente aprobada.
4. **Microlecciones.** Completa una microlección en ≤ 5 min. Si cierra el navegador a la mitad, al volver retoma **en la misma tarjeta**.
5. **Evaluaciones.** Contesta quizzes y la evaluación final. La calificación la hace el servidor; las claves no están en el código que recibe el navegador (verificado inspeccionando el bundle y las respuestas de red).
6. **Retroalimentación.** Cada respuesta incorrecta muestra la explicación aprobada y la parte de la ficha que la respalda.
7. **Certificación.** Al aprobar con la nota mínima configurada, se emite **un** certificado. Repetir el envío no emite otro.
8. **Diploma PDF.** Lo descarga desde el teléfono; incluye nombre, nivel, fecha y código. `/verificar/<código>` responde "vigente". Otra vendedora no puede descargar ese PDF.
9. **XP y puntos.** Recibe el XP de cada lección una sola vez. Con la regla v1 aprobada, al certificarse recibe los Puntos Academy de la regla, una sola vez. Un intento de autoasignación o de duplicado falla en la base de datos (prueba automatizada).
10. **Progreso y saldo.** En "Yo" ve nivel, XP, saldo y la lista de movimientos con motivo. El catálogo, si existe, dice "Canje próximamente" y no permite canjear.
11. **Aislamiento.** Con la sesión de una vendedora, toda RPC de Dirección, Inteligencia, Finanzas, Ejecutiva, del panel de Academy y del progreso de otra persona **devuelve denegado** (prueba automatizada por RPC, no solo por pantalla).
12. **Carolina.** Aprueba o pide cambios a una lección desde su teléfono. Nada se publica sin su aprobación. Si re-valida una ficha, la lección que la usa aparece en su cola.
13. **Panel.** Mario ve avance por vendedora y por tienda. Las acciones sensibles (permisos, reglas de puntos, ajustes, revocaciones) piden 2FA y quedan en `admin_events`.
14. **Sin efectos colaterales.** No cambia nada en Growth, Inteligencia, Cockpit, Estrategia, Inventario, WooCommerce, Hilo ni en los puntos de clientas (las suites de pruebas existentes siguen verdes).
15. **Reversible.** El `.down.sql` de cada migración está ensayado en staging.

---

## 17. Riesgos y controles

| Riesgo | Control |
|---|---|
| Enseñar información de producto incorrecta | Solo fichas validadas; foto de la versión al publicar; aprobación de Carolina; "pendiente" visible |
| Vendedoras viendo información sensible | Permiso por escuela en cada RPC; sin roles nuevos; pruebas de aislamiento (§16.11) |
| Puntos inflados, duplicados o autoasignados | Libro append-only, único por logro, doble aprobación de ajustes y reglas, sin `INSERT` directo (§7.3) |
| Compromiso económico sin presupuesto | Canjes apagados en la base; §8.3 obligatorio antes de A5; costo de referencia visible |
| Premios a empleadas con implicaciones fiscales o laborales | Confirmación de la contadora antes de A5; no se asume ninguna regla |
| Hacer trampa en evaluaciones (ayuda de otra persona, repetir hasta pasar) | Banco aleatorio, límites de intentos y espera, retroalimentación detallada al final; validación práctica para Master |
| Contenido detenido por falta de datos | Publicación por partes ("Parte 1 · Producto"); cuestionario guiado a Carolina |
| Diploma falsificado | Código aleatorio verificable; estado vigente o revocado en línea |
| Exposición de datos en la verificación pública | Mínimo de datos (decisión 3); límite de consultas; sin listados |
| Confusión con puntos de clientas | Nombre "Puntos Academy"; tablas y funciones separadas (§2.2) |
| Interferir con trabajos en curso | Esquema, rutas y funciones propios; puntos compartidos mínimos y fechados por sprint |
| Duplicar fuentes de verdad | Aprobadores en `f360.approval_scopes` existente; producto y vendedoras se leen de su origen; Cuidados se captura en `product_knowledge`; la Ejecutiva usa el mismo motor |
