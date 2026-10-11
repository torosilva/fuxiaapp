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

### Decisiones aprobadas por Mario (2026-10-11)

| # | Decisión | Aprobado | Dónde se aplica |
|---|---|---|---|
| 1 | Plataforma | **Web móvil primero.** WhatsApp OTP se reutiliza **solo después de verificar** que es seguro y adecuado para vendedoras autorizadas | §2.4 (verificación hecha: apto para el MVP con condiciones; **no apto para canjes** hasta cerrar P0-6) |
| 2 | XP y puntos | Conceptos separados. **Starter = 100 puntos canjeables; microcertificación = 50.** XP según la tabla propuesta, **pendiente de revisión**. **Sin valor monetario** de los puntos. **Canjes apagados** | §7.4 |
| 3 | Diplomas | Identificador **no predecible**, **información mínima autorizada**, **revocable / invalidable** | §6.3, §6.4 |
| 4 | Ranking | **Sin ranking público individual.** Progreso personal + avance agregado del equipo | §12.2 |
| 5 | Contenido de producto | **Carolina es la autoridad.** Beneficios comerciales = contenido **interno** de Academy. **Cuidados consistentes con las fichas existentes** (se capturan en `f360.product_knowledge`, Academy los lee) | §9.3 |
| 6 | Datos para A0 | Diseñar la consulta de solo lectura a producción. **Sin consultas automáticas ni tareas programadas** sobre producción sin autorización adicional | §9.5 |
| 7 | Autoaprobación | Carolina puede **publicar directamente contenido ordinario de producto que ella creó**, con auditoría, versionado y registro explícito de la excepción. **No aplica** a reglas de puntos, ajustes de saldo, premios, canjes excepcionales ni revocaciones sensibles: ahí siempre hay dos personas | §4.1.2 |
| — | Arquitectura | **Registro compartido de aprobaciones en `f360`**, con las condiciones de §4.1.8 | §4.1 |

**Siguiente paso:** el alcance definitivo de A0 está en §18. **A0, migraciones, implementación, despliegues y consultas automatizadas a producción siguen sin autorizar.**

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

### 2.4 Verificación de WhatsApp OTP para vendedoras (decisión 1)

**Cómo funciona hoy:**
- El admin web llama a la Edge Function `whatsapp-otp` (`admin-web/src/app/login/actions.ts:34-56`).
- La función crea o abre una cuenta `{teléfono}@fuxia.app` (`fuxia-native/supabase/functions/whatsapp-otp/index.ts:226-258`).
- Después, el admin web **cierra la sesión de cualquier cuenta sin rol de Fuxia 360** (`actions.ts:20-32`).

| Control | Estado | Evidencia | Veredicto |
|---|---|---|---|
| Código de 6 dígitos con generador criptográfico | ✓ | `index.ts:34-39` | Adecuado |
| Vence en 10 min; máximo 3 envíos por teléfono cada 10 min; máximo 5 intentos por código, luego se invalida; un solo uso | ✓ | `:148-160`, `:194-216` | Adecuado para el MVP (≈ 15 intentos por teléfono cada 10 min; sin límite por IP) |
| Solo entran cuentas con rol de Fuxia 360 al admin web | ✓ | `actions.ts:20-32` | Adecuado: una clienta no entra |
| Vendedora desactivada pierde acceso | ✓ con Academy | Academy deriva la alumna de `f360.sellers.status` (§4) | Adecuado |
| **Entrada de revisión de tiendas de apps** (`+525555555555` / `555555` → cuenta demo) **activa con valores fijos en el código** | ✗ **abierto** | `index.ts:17-19`, `:183-191`; hallazgo **P0-6.3** en `docs/fuxia360/audit/SPRINT_0_IMPLEMENTATION_PLAN.md:112, 367-389` (contención "A8" diseñada, **no aplicada**: el código actual conserva los valores fijos) | No afecta a Academy si la cuenta demo **no** tiene rol de Fuxia 360 ni ficha de vendedora (entonces el admin web la expulsa). **Se verifica en A0** (consulta §9.5 Q4) |
| **Contraseña derivada** de teléfono + un secreto (`OTP_SALT`) | ⚠ riesgo P1 conocido | `index.ts:227-228`; `docs/fuxia360/audit/SECURITY_AUDIT.md:70`; `LIVE_RECONCILIATION.md:84` (el secreto **sí** está configurado en producción) | Quien tuviera el secreto podría entrar como cualquier vendedora sin código |
| El error de Twilio se devuelve en `debug`; teléfonos en logs; `check_phone` revela si un número existe | ⚠ menores | `:163-166`, `:69-87`, `:110-125` | No bloquean el MVP |

**Veredicto:**
- **Apto para el MVP de Sales** (A1–A4). Ahí la vendedora solo estudia, se certifica y ve un saldo **sin valor monetario y sin canje**. Lo peor que podría hacer un impostor es presentar exámenes por otra persona.
- **No apto para A5 (canjes reales).** Ahí una cuenta tomada sí tendría valor. **Condición para encender canjes:** cerrar P0-6, con dos requisitos:
  - contener la entrada de revisión de tiendas (A8);
  - reemplazar la contraseña derivada.

  Además, la entrega física de premios lleva firma en tienda.
- Corregir `whatsapp-otp` **no es parte de Academy**: es una función compartida con la app de clientas y requiere su propia aprobación. Academy solo **depende** de que P0-6 esté cerrado antes de A5.

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

Academy separa **tres capas** que no se mezclan (requisito 7 de Mario, 2026-10-11):

| Capa | Responde | Dónde vive | Ejemplo |
|---|---|---|---|
| **1. Rol educativo** | ¿Qué papel tiene la persona dentro de Academy? | `f360_academy.grants` (+ alumna derivada de `f360.sellers`) | Alumna Sales, Alumno Ejecutivo, Editora, Administrador Academy |
| **2. Autorización de acceso** | ¿Puede entrar a esta escuela o pantalla ahora? | Funciones `f360_academy.can_access(school)` / `can_admin()`, que combinan la capa 1 con condiciones de sesión (cuenta activa, Dirección, aal2) | Una vendedora desactivada pierde acceso aunque conserve su rol; la Ejecutiva exige además Dirección + 2FA |
| **3. Aprobación** | ¿Puede decidir sobre esta operación sensible? | `f360.approval_scopes` existente + sus operaciones + el registro compartido de solicitudes (§4.1) | Carolina aprueba publicar una lección; otra persona aprueba un ajuste de puntos |

Tener un rol no da acceso por sí solo, y tener acceso no da poder de aprobación. Por ejemplo, la Editora puede escribir y no puede publicar; Mario como Administrador no aprueba contenido de producto.

**Roles educativos** (tabla `f360_academy.grants`): son permisos **de Academy**, no roles de Fuxia 360. Nadie recibe `owner` ni `operator` por usar Academy.

| Rol Academy | Cómo se obtiene | Quién, al inicio |
|---|---|---|
| **Alumna Sales** | **Derivado**: `f360.sellers.status = 'activa'` con cuenta. Al desactivarla en Vendedoras, pierde acceso sola. También por permiso explícito (p. ej., una encargada nueva para probar) | Las 4 vendedoras activas |
| **Alumno Ejecutivo** | Permiso explícito **+** miembro de Dirección **+** sesión con 2FA (aal2) | Mario |
| **Editora** | Permiso explícito | Carolina, Mario |
| *(Aprobadora de contenido)* | **No es un rol educativo:** es la capa 3, el alcance `academy_content` · operación `publish_sales` (§4.1) | Carolina |
| **Administrador Academy** | Permiso explícito; funciones sensibles con 2FA | Mario |

**Aprobaciones:** se usa el sistema existente `f360.approval_scopes` (decisión aprobada por Mario el 2026-10-11), con los alcances `academy_content`, `academy_points` y `academy_rewards`. El diseño completo está en §4.1. `f360_academy.grants` guarda **solo** roles educativos, nunca aprobaciones.

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

### 4.1 Integración con el sistema de aprobaciones existente (diseño aprobado 2026-10-11)

**Lo que existe hoy** (auditado en el repo):

| Pieza | Evidencia | Qué hace | Qué **no** hace |
|---|---|---|---|
| `f360.approval_scopes (scope, auth_user_id, …)` + `f360.can_approve(scope, user)` | `supabase/migrations/20261023000200_f360_approval_scopes.sql:6-21`; CHECK ampliado a `store_discount` en `20261025000100_f360_store_discounts.sql:21-22` | Registro de **quién puede aprobar** cada alcance (`fx_rate`, `budget`, `close`, `store_discount`) | No distingue **operaciones** dentro de un alcance. No guarda **solicitudes ni decisiones**. |
| Decisiones | `fx_rates.approved_by` (`20261024000100_f360_fx_daily.sql:169`), `budget_versions.approved_by` (`20261024000200_f360_intel_inputs.sql:144`), `f360.store_discount_requests` (`20261025000100…:45`) | Cada módulo guarda su decisión **en su propia tabla** | No hay un registro compartido de solicitud → decisión. |

**Contradicción a señalar.** Los requisitos 3 (registro auditable), 4 (atar la aprobación a la versión) y 6 (no duplicar la lógica en tablas exclusivas de Academy) **no se pueden cumplir solo con `approval_scopes`**, porque hoy solo dice quién puede aprobar. Hay dos caminos:
- tablas de aprobación propias de Academy, lo que **viola el requisito 6**; o
- un **registro de aprobaciones compartido** en `f360`, del que Academy es el primer usuario.

**Recomiendo el segundo.** Los módulos existentes (tipo de cambio, presupuesto, descuentos) **no se migran**: siguen como están y pueden adoptarlo después, cada uno con su propia decisión.

#### 4.1.1 Objetos (todos en `f360`, aditivos, sin cambiar los existentes)

| Objeto | Qué es | Requisito |
|---|---|---|
| `f360.approval_scopes` | **Sin cambio de estructura.** Solo se amplía el CHECK con `academy_content`, `academy_points` y `academy_rewards`, conservando `fx_rate`, `budget`, `close` y `store_discount` | 6 |
| `f360.approval_scope_operations (scope, auth_user_id, operation, added_by_name, added_at)` | Permiso **por operación** dentro del alcance. FK a `approval_scopes(scope, auth_user_id)`. Si la persona no tiene la operación, no puede aprobarla aunque tenga el alcance. Los alcances existentes no lo usan y siguen funcionando con `can_approve` | 1 |
| `f360.approval_operations (scope, operation, sensitive, requires_aal2, allow_self_approval, max_age_days, label)` | Catálogo de operaciones con sus reglas, cargado por migración. Solo se cambia con otra migración revisada, nunca desde la interfaz | 1, 2 |
| `f360.can_approve_op(scope, operation, user)` | `can_approve(scope, user)` **y** la operación asignada. La función existente `can_approve` no se modifica | 1 |
| `f360.approval_requests` | Una solicitud: alcance, operación, `object_kind`, `object_id`, **`object_version`**, **`object_hash`** (sha256 del contenido canónico al pedir), `beneficiary_user` (si la operación favorece a alguien), resumen legible, quién pide, motivo, estado, vence | 3, 4 |
| `f360.approval_events` | **Append-only** (trigger `f360.reject_audit_change`): `requested`, `approved`, `rejected`, `cancelled`, `invalidated`, `expired`, `consumed`, con responsable, nombre, fecha, motivo, nivel de sesión (`aal`) y **hash del objeto al decidir** | 3 |
| `f360.approval_request(…)` / `f360.approval_decide(…)` / `f360.approval_consume(…)` | Únicas funciones que escriben; `SECURITY DEFINER`. Academy (y cualquier módulo futuro) las llama; nadie escribe las tablas directo | 2, 3, 4, 6 |

#### 4.1.2 Operaciones de Academy

| Alcance | Operación | Qué aprueba | Sensible (dos personas) | aal2 | Quién al inicio |
|---|---|---|---|---|---|
| `academy_content` | `publish_sales` | Publicar una versión de lección o curso de Sales con contenido **ordinario de producto** | **Excepción de autoridad** (decisión 7): ver nota | **Sí** (endurecido por P0-6: una sesión obtenida con la contraseña derivada no debe poder publicar; `P0-6_ACCESO_VENDEDORAS_PROPUESTA.md` §2) | Carolina |
| `academy_content` | `publish_sales_policy` | Publicar contenido con **políticas** o cambiar **criterios de certificación** | **Sí** | Sí | Carolina, Mario (nunca la misma persona que lo pidió) |
| `academy_content` | `publish_executive` | Publicar contenido de la Escuela Ejecutiva | No (P1, alumno único) | Sí | Mario |
| `academy_content` | `retire` | Retirar un curso publicado | Sí | Sí | Carolina, Mario |
| `academy_points` | `rule_version` | Activar una versión de reglas de XP y puntos | **Sí** | Sí | Carolina (propone Mario) |
| `academy_points` | `manual_adjust` | Un ajuste manual de puntos | **Sí** + el beneficiario no puede ser quien pide ni quien aprueba | Sí | Carolina (pide Mario) |
| `academy_points` | `certificate_revoke` | Revocar un certificado (y revertir sus puntos) | **Sí** | Sí | Carolina (pide Mario) |
| `academy_rewards` | `catalog_item` | Activar un premio o cambiar su costo, stock o vigencia | **Sí** | Sí | Carolina (propone Mario) |
| `academy_rewards` | `redemptions_enable` | Encender canjes reales | **Sí** | Sí | **No se asigna a nadie hasta A5** (§8.3) |
| `academy_rewards` | `redemption` | Aprobar un canje (A5) | **Sí** + beneficiario ≠ aprobador | Sí | No se asigna hasta A5 |

**Nota sobre `publish_sales`.** Carolina es la autoridad única de producto, igual que con `store_discount`, donde solo ella aprueba. Si ella misma escribe una lección y además la aprueba, exigir una segunda persona dejaría el contenido sin quien lo apruebe.
- **Aprobado por Mario (decisión 7):** `allow_self_approval = true` **solo** para `publish_sales`, y solo para **contenido ordinario de producto** creado por la propia Carolina.
  - Queda como evento `approved` con la marca **`self_approval = true`**, la versión y la huella del contenido.
  - Aparece en el panel de Mario.
- Si otra persona es la autora, la aprobación de Carolina es obligatoria.
- **La excepción nunca aplica** a `academy_points.*` (reglas, ajustes de saldo, revocaciones), `academy_rewards.*` (premios, canjes, encendido de canjes) ni `academy_content.retire`. Esas operaciones tienen `allow_self_approval = false` en el catálogo, y `approval_decide` exige siempre solicitante ≠ aprobador.
- **"Contenido ordinario" excluye** cualquier lección que incluya una **política** (cambios, apartados, envíos, descuentos) o que **cambie la nota mínima o los criterios de certificación**. Esas van como `publish_sales_policy`, sin autoaprobación: Carolina las propone y Mario las aprueba, o al revés.

#### 4.1.3 Separación solicitante / aprobador (requisito 2)

`f360.approval_decide` rechaza, **en la base**, cuando la operación es sensible y:
- quien decide es quien pidió;
- quien decide o quien pidió es el **beneficiario** (puntos, canjes);
- falta `aal2` y la operación lo exige;
- quien decide no tiene `can_approve_op`;
- la solicitud está vencida, cancelada o ya decidida.

Además, **nadie aprueba con una sesión de vendedora**, aunque esa misma persona tenga el alcance. La decisión se toma desde el panel con la cuenta de Fuxia 360 y su 2FA.

#### 4.1.4 Una aprobación vieja no autoriza un cambio nuevo (requisito 4)

1. **Versiones inmutables.** Lecciones, cursos, reglas de puntos y premios se aprueban **por versión**. Una versión enviada a revisión ya no se edita (trigger). Cualquier cambio crea una versión nueva, con su propia solicitud.
2. **Hash al pedir y al decidir.** La solicitud guarda `object_hash`. Al aprobar, `approval_decide` recalcula el hash del objeto. Si no coincide, la solicitud pasa a `invalidated` y no se puede aprobar.
3. **Hash al usar.** La acción que ejecuta (publicar, activar regla, aplicar ajuste, activar premio) llama `approval_consume(request_id, object_hash)`:
   - comprueba que la aprobación existe, coincide en **alcance, operación, objeto, versión y hash**, y no ha caducado (`max_age_days`; propuesta: 14);
   - la marca `consumed` en la misma transacción. **Una aprobación se usa una sola vez.**
4. **Dependencias.** Si una lección aprobada referencia una ficha de producto y Carolina re-valida esa ficha (§9.4), la versión de la lección no cambia, pero su contenido "foto" ya no es el vigente. La lección entra a la cola como "ficha actualizada", y publicar la nueva requiere **otra** aprobación.

#### 4.1.5 Registro auditable (requisito 3)

Cada solicitud y decisión deja, sin posibilidad de edición:
- **qué:** alcance, operación, objeto, versión y hash;
- **solicitud:** quién, cuándo y motivo;
- **decisión:** aprobada, rechazada, invalidada o vencida; quién, cuándo, motivo (obligatorio al rechazar o aprobar algo sensible) y con qué nivel de sesión;
- **uso:** cuándo se consumió y por qué acción.

El panel de Academy (§11) lo muestra filtrado por sus alcances. Un futuro módulo de auditoría puede leer el mismo registro para todo Fuxia 360.

#### 4.1.6 Coordinación antes de cualquier migración (requisito 5)

Ninguna migración que toque `f360.approval_scopes` o cree el registro compartido se escribe sin este chequeo:
1. **Leer el estado real.** En el repo, `git pull` y todas las migraciones que mencionan `approval_scopes`/`can_approve` (hoy `20261023000200`, `20261024000100`, `20261024000400`, `20261024000200`, `20261025000100`). En staging y producción, la definición vigente del CHECK, en solo lectura.
2. **Avisar a la otra sesión** (mensaje entre sesiones) qué objetos se tocarán y con qué número de migración. Esperar confirmación de que no hay otra migración pendiente sobre lo mismo.
3. **Migración con guarda:** antes de redefinir el CHECK, la migración **verifica que el CHECK vigente es exactamente el esperado** (`fx_rate`, `budget`, `close`, `store_discount`, …). Si no coincide, **aborta**. Nunca reescribe el CHECK de memoria.
4. **No tocar** `f360.can_approve` ni la estructura de `approval_scopes`: solo se agregan objetos nuevos.
5. `supabase db push --dry-run` antes de cada push y `.down.sql` ensayado. El rollback **no** quita alcances que otra migración posterior haya agregado.
6. Los cambios al registro compartido se presentan **aparte** de las migraciones de Academy, para revisarlos como infraestructura común.

#### 4.1.7 Qué no se duplica (requisito 6)

- Academy **no** tiene tabla de aprobadores ni de solicitudes o decisiones. La tabla `approvals` de §5.1 **se elimina** del diseño.
- Academy **sí** guarda en sus tablas el **estado** del objeto (`borrador`, `en_revision`, `publicado`…) y el `approval_request_id` que lo autorizó. Es una referencia, no una copia de la decisión.
- Los comentarios de Carolina por bloque ("cambia esta frase") son **notas de edición**, no decisiones. Viven en `f360_academy.review_comments`. La decisión formal está solo en `f360.approval_events`.

#### 4.1.8 Condiciones de Mario al registro compartido (2026-10-11)

| Condición | Cómo se cumple |
|---|---|
| No modificar las aprobaciones de tipo de cambio, presupuesto ni descuentos | Esos flujos siguen con sus tablas y funciones (`fx_rates`, `budget_versions`, `store_discount_requests`). El registro nuevo **no** los lee ni los escribe, y no tienen que adoptarlo |
| No eliminar ni alterar `approval_scopes`, `can_approve` ni `store_discount` | Única intervención: **ampliar** el CHECK de alcances con guarda que aborta si el CHECK vigente no es el esperado (§4.1.6). Sin cambio de columnas, llave, RLS ni función |
| Historial inmutable | `approval_events` append-only con `f360.reject_audit_change`; `approval_requests` solo cambia de estado por las funciones del registro, y cada cambio deja un evento |
| Aprobaciones atadas a versiones | Objeto + versión + huella en la solicitud, al decidir y al consumir (§4.1.4) |
| Sin reutilización | `approval_consume` marca `consumed` en la misma transacción; una solicitud consumida no se vuelve a usar |
| Expiración correcta | `expires_at` fijo al crear la solicitud (por operación, `max_age_days`). Se evalúa **en la base con `now()`** al decidir y al consumir, nunca con la hora del navegador. Vencer no borra nada: deja un evento `expired` |
| Sin aprobar versiones modificadas | Versiones inmutables desde que se envían a revisión + huella recalculada (§4.1.4) |
| Coordinación con otras sesiones | §4.1.6 obligatorio antes de cualquier migración |
| Sin dependencias que rompan módulos existentes | Objetos **nuevos**; ninguna función existente cambia su firma ni su comportamiento; ningún módulo existente depende del registro. Si el registro falla, **solo** Academy queda sin poder publicar. El `.down.sql` del registro solo se puede ejecutar si no hay solicitudes de otros módulos |

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
| `review_comments` | Comentarios de edición de Carolina por bloque (no son decisiones). **Las decisiones viven en el registro compartido `f360.approval_requests/events` (§4.1)**; cada versión guarda el `approval_request_id` que la publicó |

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
- **Invalidar sin revocar.** Además de revocar (el certificado deja de ser válido), el Admin puede **apagar la verificación pública** de un certificado vigente, por ejemplo si la vendedora lo pide por privacidad. La página responde igual que un código inexistente. Si se trata de una revocación sensible, se pide con `academy_points.certificate_revoke` y dos personas.
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

### 7.4 Valores

**Aprobado (2026-10-11):**
- **Fuxia Starter = 100 Puntos Academy.**
- **Microcertificación = 50 Puntos Academy.**
- **Sin valor monetario** por punto.
- **Canjes apagados.**
- Los demás niveles **no tienen puntos fijados**: se deciden cuando existan sus cursos.
- La **tabla de XP** de abajo sigue **pendiente de revisión** y se confirma antes de A2.

Tabla original propuesta (referencia):

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

**Tareas de A0 (lectura):** medir forro, suela, punta, tacón, nota de talla y colores por modelo, y por qué 5 modelos no tienen ficha validada (hay 4 modelos archivados; falta confirmar si son los mismos). Mecanismo en §9.5.

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

### 9.5 Consulta de solo lectura a producción para A0 (decisión 6)

**Mecanismo:** manual, puntual y aprobado por consulta. **Sin** tareas programadas, cron, copias nocturnas nuevas ni ejecuciones automáticas.

1. **Herramienta existente:** `scripts/f360/prod_read.sh`. Envuelve la consulta en `BEGIN READ ONLY … COMMIT`, así que Postgres rechaza cualquier escritura. Acepta una sola sentencia (rechaza `;`). Usa la sesión de la CLI de Supabase del llavero de macOS y no imprime credenciales.
2. **Lista cerrada:** las consultas exactas (abajo) se aprueban **antes** de ejecutarse. No se ejecuta nada fuera de la lista; si hace falta otra, se pide de nuevo.
3. **Solo datos de producto o conteos.** Sin teléfonos, nombres de clientas ni montos individuales. Q4 devuelve solo **sí/no**.
4. **Una ejecución por consulta**, a mano, en esta sesión. El resultado se guarda en `docs/fuxia360/academy/a0/07_CONSULTAS_SOLO_LECTURA.md` con fecha, consulta y resultado, y queda versionado.
5. **Si el permiso de la sesión bloquea la ejecución** (como pasó el 11-oct), no se reintenta ni se rodea. Se te pide que la ejecutes tú con `! scripts/f360/prod_read.sh <<'SQL' … SQL`.

| # | Para qué | Devuelve |
|---|---|---|
| Q1 | Fichas: datos de producto por modelo Ballerinas | Por modelo: código, nombre, estado, colores, tallas, foto principal (ruta), y de `product_knowledge`: estado, versión, fecha de validación, ajuste, entre tallas, nota de talla, horma, ancho, materiales (exterior, forro, suela), tacón, punta, comodidad, cuidados |
| Q2 | Qué falta | Por modelo: lista de campos vacíos y si el modelo está archivado |
| Q3 | Descripciones existentes (posible material para Carolina) | Por modelo: `short_description` y los primeros 400 caracteres de `description` (texto de producto, no personal) |
| Q4 | Verificar la entrada de revisión de tiendas (§2.4) | Dos valores **sí/no**: ¿la cuenta demo tiene rol en `f360.user_roles`? ¿tiene ficha en `f360.sellers`? Sin teléfono ni id en la salida |

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
- **Si Carolina es la autora**, su aprobación es la publicación, porque ella es la autoridad de producto. Queda registrado como autoaprobación en `f360.approval_events` (§4.1.2).
- **Pantalla de Carolina:** cola "Por aprobar" → vista **como la verá la vendedora** (marco de teléfono) → comentarios por bloque → Aprobar o Pedir cambios. Debe poder hacerse desde el teléfono en 2 minutos por lección.
- Cada envío, aprobación, rechazo e invalidación queda en `f360.approval_events` (append-only, §4.1). Publicar consume la aprobación, que debe coincidir con la versión y el hash (§4.1.4).

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

> El detalle definitivo de A0 está en **§18**. Esta sección queda como resumen.

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
1. **El flujo mínimo de aprobación de Carolina va en A1, no después.** Sin él no se puede publicar el primer curso: o ella aprueba en la plataforma, o hay que cargar contenido "aprobado" por migración, que es justo lo que queremos evitar. Esto implica que **el registro de aprobaciones compartido (§4.1) entra en A1**, como una migración **separada** de infraestructura común (`f360`), revisada por su cuenta y coordinada con la otra sesión según §4.1.6, **antes** de la migración de Academy.
2. **El XP va en A2**, junto con la evaluación, porque se deriva de completar lecciones. **A3 queda para el libro de Puntos Academy y sus controles.** El **MVP liberable = A1 + A2 + A3**.

Cada sprint se hace primero en STAGING, en `fuxia-360`, y lleva:
- migración aditiva con `.down.sql` ensayado;
- pruebas de base de datos (`scripts/f360/db_tests.mjs`) y Playwright;
- tu aprobación antes del siguiente.

| Sprint | Entrega | Base de datos / API | Seguridad | Verificación | Aceptación |
|---|---|---|---|---|---|
| **A0 · Contenido del primer curso** | Ver **§18**: temario, microlecciones, fichas, banco de preguntas, criterios de certificación, lista de validación de Carolina, consultas Q1–Q4 | Ninguno (solo documentos + 4 lecturas manuales aprobadas) | Sin escrituras; lecturas de producto solamente | Revisión de Mario y Carolina | Criterios de §18.6 |
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
| Choque con migraciones de otra sesión sobre `approval_scopes` | Chequeo obligatorio de §4.1.6: estado real, aviso a la otra sesión, guarda del CHECK que aborta si no coincide, dry-run |
| Una aprobación usada para algo distinto de lo aprobado | Aprobación atada a alcance, operación, objeto, versión y hash; un solo uso; vencimiento (§4.1.4) |
| Duplicar fuentes de verdad | Aprobadores en `f360.approval_scopes` existente; solicitudes y decisiones en el registro compartido `f360.approval_*` (no en Academy); producto y vendedoras se leen de su origen; Cuidados se captura en `product_knowledge`; la Ejecutiva usa el mismo motor |

---

## 18. Alcance definitivo de A0 — "Fuxia Starter · Ballerinas" (para autorizar)

### 18.1 Qué produce A0

Documentos en `docs/fuxia360/academy/a0/`, versionados en `fuxia-360`. **Nada de código, migraciones, despliegues ni escrituras en ningún ambiente.**

| # | Archivo | Contenido | Tamaño esperado |
|---|---|---|---|
| 1 | `01_TEMARIO.md` | Curso Starter · Ballerinas: 5 módulos, objetivos por módulo y microlección, duración, orden, qué es obligatorio y qué queda "pendiente de Carolina" | 1 página |
| 2 | `02_MICROLECCIONES.md` | **Guion completo, tarjeta por tarjeta**, de ≈ 18 microlecciones de 2–5 min (≈ 70 min en total). Cada frase lleva su **etiqueta de fuente**: `[FICHA vN]` (validada), `[PEDAGOGÍA]` (técnica general de venta, revisable), `[PENDIENTE CAROLINA]` (hueco explícito). Una pregunta de práctica por tarjeta donde aplique | ≈ 18 guiones |
| 3 | `03_FICHAS_BALLERINAS.md` | **Una ficha educativa por modelo activo** (28), con el formato de §9.2: lo validado tal cual (con versión y fecha), lo que falta marcado **pendiente**, y beneficios / objeciones / "recomiéndala para…" como **BORRADOR PARA CAROLINA** solo cuando se derivan de un campo validado, con la derivación escrita (p. ej., "horma cómoda [FICHA v3] → beneficio propuesto: …"). **Nunca** se escriben materiales, tallas, cuidados ni políticas que no estén validados | 28 fichas |
| 4 | `04_BANCO_DE_PREGUNTAS.md` | **≥ 60 reactivos fijos** + **6 plantillas** que generan reactivos por modelo desde campos validados (≈ 150). Cada reactivo: tipo, enunciado, opciones, respuesta, **explicación con su fuente**, habilidad, módulo, dificultad. Los reactivos que dependen de datos pendientes quedan marcados y **no cuentan** para el examen hasta validarse | ≥ 60 + plantillas |
| 5 | `05_CRITERIOS_CERTIFICACION.md` | Requisitos de Starter: lecciones obligatorias, examen de 20 reactivos con distribución por módulo (producto 8, tallas 5, cuidados 2, atención 3, marca/políticas 2), **nota mínima 80** (configurable), 3 intentos al día, 1 h de espera, qué pasa si no hay datos de un módulo (variante "Parte 1 · Producto"), 100 Puntos Academy al certificar, datos del diploma y de la verificación, causas de revocación. Todo lo que es **criterio de certificación** se marca para aprobación con dos personas (`publish_sales_policy`) | 2 páginas |
| 6 | `06_VALIDACION_CAROLINA.md` | **Lista de lo que Carolina debe validar o dar**: (a) por modelo, campos faltantes (de Q2); (b) cuidados por material, para capturarlos en la ficha de producto existente; (c) historia y promesa de la marca; (d) políticas de cambios, apartados, envíos y descuentos (preguntas, **sin borrador**); (e) aceptar, editar o rechazar cada beneficio/objeción propuesto; (f) los 5 modelos sin ficha validada; (g) las 6 plantillas de preguntas; (h) la parte `[PEDAGOGÍA]` de atención. Con casillas y tiempo estimado (≈ 90 min de respuestas + ≈ 2 h de revisión) | 3–4 páginas |
| 7 | `07_CONSULTAS_SOLO_LECTURA.md` | Las consultas Q1–Q4 (§9.5) con fecha, texto exacto y resultado | 1 página |
| 8 | `00_A0_ESTADO.md` | Índice, avance y criterios de salida (§18.6) | 1 página |

### 18.2 Temario propuesto (se detalla en `01_TEMARIO.md`)

| Módulo | Microlecciones | Fuente | Puede escribirse en A0 sin Carolina |
|---|---|---|---|
| 1. Bienvenida a Fuxia | 2: qué es Fuxia; cómo hablamos con la clienta | Carolina | Solo estructura y preguntas |
| 2. Conoce las Ballerinas | 1 "cómo leer una ficha" + ≈ 6 por grupo de modelos (27 validados) | Fichas validadas + fotos | **Sí** (datos validados) |
| 3. Tallas y ajuste | 3: escala 35–40; talla exacta, chica o grande y "entre dos tallas"; cómo preguntar por la talla | Fichas + etiquetas existentes (`knowledge_labels`) | **Sí**; sin conversiones a otras escalas |
| 4. Cuidados | 2 | `care_instructions` (0/32) | No: hueco explícito |
| 5. Atención y venta básica | 4: recibir, descubrir la necesidad, presentar 2–3 opciones, cerrar sin presionar; políticas | `[PEDAGOGÍA]` + políticas de Carolina | La técnica sí (para revisión); las políticas **no** |

### 18.3 Reglas de contenido en A0 (no negociables)

1. Ningún material, talla, medida, cuidado, beneficio, garantía, precio ni política aparece como dato si no viene de una ficha **validada** o de texto de Carolina.
2. Las **propuestas** (beneficios, objeciones, recomendaciones) se marcan BORRADOR, muestran de qué campo validado se derivan y no se usan en el examen hasta que Carolina las apruebe.
3. **Políticas: solo preguntas, nunca borradores.**
4. Las tallas se enseñan como están en el sistema (35–40), sin equivalencias.
5. Los precios no se usan en lecciones ni en el examen; cambian y no deben quedar en un diploma.
6. Español sencillo; cada tarjeta ≤ 60 palabras.

### 18.4 Lo que A0 necesita y lo que no toca

| Necesita | No toca |
|---|---|
| Tu autorización para **ejecutar a mano Q1–Q4** (§9.5), una vez cada una | Producción (escrituras), staging, WooCommerce, Hilo, la app, `whatsapp-otp`, `approval_scopes` |
| El tiempo de Carolina para `06_VALIDACION_CAROLINA.md` | Cron, tareas programadas, copias de datos |
| (Opcional) que le compartamos los documentos de A0 en **Google Docs** para comentar más fácil. Si no, en PDF o en el repo | Otras sesiones de trabajo |

**Si Q1–Q4 no se autorizan:** A0 se puede hacer con la estructura completa, pero las 28 fichas y las plantillas quedarían **sin valores** hasta tener los datos. No lo recomiendo: las fichas son el corazón del curso.

### 18.5 Pasos

1. Ejecutar Q1–Q4 y guardar resultados (`07`).
2. Escribir `03` (fichas) y `02` módulos 2–3 (datos validados).
3. Escribir `04` (banco + plantillas) y `05` (criterios).
4. Escribir `02` módulos 1, 4 y 5 como estructura + `[PEDAGOGÍA]` + huecos, y `06` (lista para Carolina).
5. Revisión tuya → envío a Carolina → incorporar sus respuestas → segunda versión.

Cada paso se sube a `fuxia-360` al terminarlo.

### 18.6 Criterios de salida de A0

1. Los 8 archivos existen. Cada afirmación de producto tiene etiqueta de fuente, y una revisión automática del texto confirma que no hay ningún material, talla ni cuidado **sin** `[FICHA vN]` o `[PENDIENTE CAROLINA]`.
2. 28 fichas: los campos validados coinciden con Q1; los faltantes coinciden con Q2.
3. ≥ 60 reactivos fijos, todos con respuesta, explicación y fuente; distribución suficiente para presentar 20 por intento sin repetir más del 50% entre dos intentos seguidos.
4. Criterios de certificación completos y marcados para aprobación con dos personas.
5. Lista de Carolina completa, con tiempo estimado y casillas.
6. **Tú apruebas A0** (y Carolina contesta y aprueba el contenido en documento). La aprobación formal en la plataforma ocurre en A1, cuando el contenido se cargue como borrador y Carolina lo publique con `publish_sales`.
