# A1 · Paquete de revisión: motor de Sales Academy (STAGING)

> 2026-10-11 · autorizado por Mario: **A1 solo en staging**, con alcance controlado.
> **Estado: construido y PRESENTADO PARA REVISIÓN. No se ha ejecutado nada** en staging, producción ni en ningún Postgres.
> - Rama de revisión: **`academy/a1`** (commit `66d4cb6`). **No está en `fuxia-360`**: la copia nocturna de staging aplica sin prueba en seco todo lo que llega a `origin/fuxia-360`, así que integrar = ejecutar.
> - Las otras sesiones (fuxiaapp-2d, fuxiaapp-ed) fueron avisadas. Respondieron **sin conflicto**: nadie toca `approval_scopes` ni usa el prefijo `20261026*`. Piden conservar `fx_rate`, `budget`, `close`, `store_discount` y la firma de `can_approve`; la propuesta lo cumple.

## 1. Qué contiene la rama

| Archivo | Qué es | Toca objetos existentes |
|---|---|---|
| `supabase/migrations/20261026000100_f360_approval_registry.sql` | **Registro compartido de aprobaciones** (infraestructura común, revisar aparte) | Solo **amplía** el CHECK de `f360.approval_scopes`, con guarda que aborta si el CHECK vigente no es exactamente `budget, close, fx_rate, store_discount`. No cambia columnas, llave, RLS, `can_approve` ni el flujo de descuentos |
| `supabase/migrations/20261026000200_f360_academy_a1.sql` | Esquema `f360_academy` + 15 RPC `public.f360_academy_*` | Lee `f360.sellers`, `f360.locations`, `f360.location_assignments`, `f360.products`, `f360.product_*`, `f360.product_knowledge_public`. No escribe en ellos |
| `supabase/migrations/20261026000300_f360_academy_pilot_seed.sql` | Curso "Fuxia Starter · Parte 1 (Producto Ballerinas)" **v1 en BORRADOR**: 7 lecciones y 24 preguntas (15 marcadas para el examen futuro) | No. Los modelos se nombran **por código**; los datos de producto se congelan de la ficha validada al enviar a revisión |
| `supabase/rollbacks/20261026000{1,2,3}00_*.down.sql` | Reversas | La del registro reconstruye el CHECK sin quitar alcances ajenos y se niega si otro módulo ya usa el registro |
| `supabase/staging/academy_a1_staging.sql` | Datos **solo de staging**: permisos de Academy, quién aprueba qué operación, 2 vendedoras de prueba ficticias | Inserta en `f360.approval_scopes`/operaciones y en `f360.sellers` (vía la activación normal), **solo** para cuentas `@staging.invalid` |
| `scripts/f360/academy_a1_test_users.mjs` | Crea `alumna.prueba1/2@staging.invalid`. Contraseñas solo en `~/.fuxia-staging.env` | Auth de staging (la librería se niega a apuntar a producción) |
| `supabase/staging/f360_academy_a1_tests.sql` | Suite de pruebas en **una transacción revertida**; ensaya las 3 migraciones en línea | Nada (ROLLBACK) |
| `admin-web/src/app/(app)/academy/**`, `src/lib/academy.ts` | Interfaz móvil `/academy` (inicio, lección por tarjetas, fichas, panel de contenido, revisión y aprobación) | — |
| `admin-web/src/components/Shell.tsx`, `src/app/(app)/layout.tsx` | Una entrada "Academy" en el menú, visible solo si la base dice que la persona tiene acceso **y** el ambiente es staging | Sí, mínimo. En la carpeta principal **otra sesión tiene cambios sin commit en estos dos archivos**: al integrar puede haber conflicto de texto, que se resuelve a mano |

**Verificado sin ejecutar:** `tsc --noEmit` pasa sin errores. `eslint` da 0 errores y 1 advertencia (`<img>`, igual que otras pantallas).

## 2. Arquitectura implementada

```
/academy (solo staging: academyEnabled() → si no, 404)
  ├─ Inicio · Lección por tarjetas (guardado automático, retoma en la misma tarjeta) · Práctica calificada en el servidor · Fichas
  ├─ /academy/admin: cursos y versiones, estado de aprobación, avance por persona y tienda, historial del registro
  └─ /academy/admin/version/[id]: vista previa como alumna, edición de borrador, preguntas CON respuesta (solo equipo),
                                  comentarios, "Enviar a revisión", "Aprobar y publicar" (aal2) → /academy/verificar (2FA)
        │ server actions (solo reenvían con la sesión del usuario)
        ▼
public.f360_academy_* (SECURITY DEFINER; deciden con auth.uid())
  capa 1 · roles educativos: f360_academy.grants (tester · editor · admin · executive_learner)
  capa 2 · acceso:           f360_academy.sales_access() → ok | bloqueado | none
  capa 3 · aprobación:       f360.can_approve_op() + f360.approval_request/decide/consume (registro compartido)
```

**Compuertas de A1, escritas en la base:**
- `f360_academy.settings` tiene `CHECK (NOT learner_access_enabled)`. **Ninguna vendedora real** puede entrar, aunque esté activa; solo se levanta con otra migración revisada **después de cerrar P0-6**.
- Igual para certificados, puntos y canjes, que además **no tienen tablas**.

## 3. Matriz de acceso (lo que verifica la suite)

| Llamada | Sin rol | Operación (sin tester) | Vendedora activa sin tester (= vendedora real) | Alumna de prueba (tester) | Editora | Aprobadora (`publish_sales`) |
|---|---|---|---|---|---|---|
| `me` | none | none | **bloqueado** | ok | — | — |
| `home`, `lesson`, `progress_save`, `answer`, `fichas` | ✗ | ✗ | **✗ (P0-6)** | ✓ (solo cursos Sales **publicados**) | ✗ como alumna | ✗ como alumna |
| `admin_overview`, `admin_version`, `team`, `comment` | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ |
| `lesson_save`, `item_save`, `new_draft`, `submit` | ✗ | ✗ | ✗ | ✗ | ✓ (solo borradores) | ✓ si también es editora |
| `decide` (publicar) | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ **con aal2**; autoaprobación solo en contenido ordinario |
| Leer/escribir tablas `f360_academy.*` o `f360.approval_*` directo | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Llamar `f360.approval_request/decide/consume` directo | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |

## 4. Pruebas (suite revertida, 101 comprobaciones)

| Grupo | Qué demuestra |
|---|---|
| **G1–G5** | Acceso real, certificados, puntos y canjes **no se pueden encender** (CHECK); no existen tablas de certificados, puntos ni premios |
| **R1–R6** | El CHECK queda = los 4 alcances existentes + 3 de Academy; permiso por operación; `can_approve` sin cambios; ningún cliente lee el registro ni llama sus funciones |
| **A1–A7** | Matriz de acceso completa, incluida **A5: todas las vendedoras reales activas de staging quedan bloqueadas** |
| **I1–I4** | Aislamiento: sin acceso directo a tablas (ni el admin), sin autoasignarse roles, sin sesión no hay nada |
| **W1–W19** | Flujo de contenido: borrador invisible para alumnas; tarjeta sin fuente rechazada; envío crea la solicitud con huella; ficha congelada; **no se edita lo enviado** (RPC y trigger); Mario no aprueba contenido ordinario; **sin 2FA no se aprueba**; **cambio después de enviar → aprobación invalidada**; autoaprobación registrada; historial solicitada → aprobada → usada; **no se reutiliza**; historial y solicitudes no se editan ni borran; lo publicado no se edita |
| **S1–S5** | Operaciones sensibles: quien pide no aprueba; motivo obligatorio; otra persona sí; **vencida no se aprueba** (reloj de la base); nadie aprueba algo a su favor |
| **F1–F11** | Flujo de la alumna: ve el curso publicado; abre lección con ficha congelada; **preguntas sin respuesta**; guarda y retoma tarjeta; calificación en el servidor; intentos append-only; preguntas solo de examen no se contestan; 5 fichas; Carolina ve el avance por persona y tienda; **vendedora sin tester sigue bloqueada con el curso publicado** |
| **X1–X7** | Sales y Ejecutiva separadas; la Ejecutiva no se publica en A1; **ficha re-validada → curso marcado**; nueva versión = copia en borrador; un borrador a la vez; la alumna sigue en su versión |

## 5. Plan de ejecución (cada paso necesita tu OK)

| # | Comando exacto | Efecto | Riesgo / reversión |
|---|---|---|---|
| 1 | `scripts/s00a/run.sh ../f360/sql_test_one.mjs supabase/staging/f360_academy_a1_tests.sql` (desde `academy/a1`) | **Ensayo** en staging dentro de una transacción que termina en ROLLBACK. Esperado: todo PASS | Bloquea staging unos segundos; aviso previo a las otras sesiones. No deja nada |
| 2 | Integrar `academy/a1` en `fuxia-360` + agregar `supabase/staging/academy_a1_staging.sql` a `scripts/f360/staging_refresh/after_refresh.list` + push | Esa noche staging aplica las 3 migraciones y los datos de prueba (y los reaplica cada noche) | La copia nocturna **no hace prueba en seco**: por eso va después del paso 1. **Las migraciones quedan pendientes para el próximo push manual a producción**: ese push deberá excluirlas o aprobarlas explícitamente |
| 2b | (alternativa el mismo día) `supabase db push --db-url "$STAGING_DB_URL" --dry-run`: la lista debe tener **solo** `20261026000100/0200/0300`, y después aplicarlas | Aplica hoy sin esperar la noche | Igual que 2; si la lista trae migraciones ajenas, se detiene |
| 3 | `scripts/s00a/run.sh ../f360/academy_a1_test_users.mjs` | Crea las 2 alumnas de prueba y carga `academy_a1_staging.sql` | Solo cuentas `@staging.invalid` |
| 4 | Recorrido en el teléfono con Alumna Prueba 1 (curso visible solo después de que Carolina demo lo publique), Alumna Prueba 2 (pantalla "todavía no abierta"), Carolina demo (enviar, 2FA, publicar) | Evidencia del flujo con cuentas autorizadas | — |
| 5 | Reporte final de A1 con resultados reales | — | — |

## 6. Cobertura y riesgos

| Tema | Estado |
|---|---|
| Acceso por roles educativos, catálogo, progreso, interfaz móvil, administración básica, estados de aprobación, piloto con los 5 modelos | Construido; **pendiente de ejecutar** |
| Pruebas de RLS y aislamiento | Escritas (101 comprobaciones: 49 de la matriz de acceso y aislamiento); **pendientes de ejecutar** |
| Evidencia de que P0-6 bloquea el acceso real | CHECK en la base + pruebas G1, A3, A5, F11 + pantalla "todavía no abierta" (paso 4) |
| Editar desde el panel: texto de tarjetas, preguntas y estado | Sí. **No** se pueden crear lecciones o cursos nuevos desde el panel (A1 básico); el contenido nuevo llega por migración revisada |
| Tiempo de estudio y XP | **No** en A1 (fuera del alcance autorizado) |
| Preguntas sobre un modelo | La pregunta repite la respuesta de la ficha. Si la ficha cambia, el aviso de "ficha actualizada" sale por la **lección** que usa el modelo, no por la pregunta. Riesgo bajo: las 10 preguntas de modelo son de los 5 modelos del piloto, todos en la lección 2.p |
| Conflicto con cambios sin commit de otra sesión en `Shell.tsx` / `layout.tsx` | Posible al integrar; se resuelve a mano |
| Despliegue del admin a producción (publica toda la rama) | `/academy` responde 404 fuera de staging y el menú no aparece. Las RPC tampoco existirían en producción |
| **P0-6** | Abierto. Bloquea el acceso real (por CHECK) y los canjes. Remediación independiente en `docs/fuxia360/security/P0-6_REMEDIACION.md` |
| Contenido | **Sin aprobar por Carolina**: el curso es un borrador. Paquete de revisión en `PAQUETE_CAROLINA_PILOTO.md` (no compartido) |
