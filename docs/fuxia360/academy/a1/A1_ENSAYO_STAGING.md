# A1 · Paso 1: ensayo transaccional en staging (resultado)

> 2026-10-11 · autorizado por Mario: **solo el paso 1**. Rama `academy/a1`.
> - Ejecutado **una vez**, de 12:41:44 a 12:42:01 CST, fuera de la ventana nocturna de 3:30 a 3:50.
> - Las otras sesiones (fuxiaapp-2d, fuxiaapp-ed) fueron avisadas antes.
> - **No** se integró `academy/a1` en `fuxia-360`. **No** se aplicaron migraciones persistentes, **no** se crearon cuentas de prueba, **no** se tocó producción y **no** se habilitó acceso de vendedoras.

## 1. Resultado

**101 PASS / 0 FAIL** (`scripts/s00a/run.sh ../f360/sql_test_one.mjs supabase/staging/f360_academy_a1_tests.sql`, código de salida 0).

| Grupo | Comprobaciones | Resultado |
|---|---|---|
| G · compuertas (acceso real, certificados, puntos, canjes) | 5 | 5 PASS |
| R · registro compartido (CHECK, permiso por operación, `can_approve` sin cambios, sin acceso de clientes) | 6 | 6 PASS |
| A · matriz de acceso (incluye **todas las vendedoras reales activas bloqueadas**: 4 revisadas) | 45 | 45 PASS |
| I · aislamiento y RLS | 4 | 4 PASS |
| W · flujo de contenido y aprobación (invalidación por cambio, 2FA, autoaprobación registrada, sin reutilización, historial inmutable) | 18 | 18 PASS |
| S · operaciones sensibles (dos personas, motivo, vencimiento, beneficiario) | 5 | 5 PASS |
| F · flujo de la alumna (curso, ficha congelada, preguntas sin respuesta, retomar, calificación en servidor, bloqueo P0-6 con curso publicado) | 11 | 11 PASS |
| X · separación Sales/Ejecutiva, ficha re-validada, versiones | 7 | 7 PASS |

## 2. Errores y advertencias

- **Errores:** ninguno.
- **Advertencias:**
  1. El ejecutor (`sql_test_one.mjs`) solo imprime las líneas PASS/FAIL. Los `NOTICE` de Postgres **no se capturan**: no puedo afirmar que no hubo avisos, solo que ninguno fue un error.
  2. **Efecto residual no transaccional, sin datos:** los contadores de secuencia no retroceden con un `ROLLBACK` en Postgres. Las fichas de prueba se activaron con `f360.activate_seller`, que escribe en `f360.access_changes` y en el registro de eventos de vendedoras, así que sus contadores de id avanzaron unos números. **No queda ninguna fila**; solo hay huecos en la numeración, un comportamiento normal de Postgres.
  3. Los 5 modelos del piloto existen y están validados en staging con las mismas versiones que en producción (copia nocturna). Si Carolina re-valida una ficha antes de la siguiente prueba, las pruebas siguen pasando: no dependen del número de versión.

## 3. Confirmación de rollback

- El archivo de pruebas termina en `ROLLBACK;`. El ejecutor se niega a correr si no es así, y todo va en **una sola sesión de `psql`** con `ON_ERROR_STOP=1`: ante cualquier error, la conexión se cierra y Postgres revierte.
- **Diagnóstico de solo lectura antes y después** (`scripts/f360/academy_a1_staging_diag.mjs`, en `BEGIN READ ONLY … ROLLBACK`). **16 indicadores idénticos**:

| Indicador | Antes = Después |
|---|---|
| CHECK de `approval_scopes` | `fx_rate, budget, close, store_discount` |
| Filas en `approval_scopes` | close 2 · budget 1 · fx_rate 1 |
| Huella de `f360.can_approve` (md5 de su definición) | `565a9163…` |
| Tablas `f360.approval_*` | solo `approval_scopes` |
| Esquema `f360_academy` | no existe |
| Funciones `public.f360_academy_*` | 0 |
| Migraciones `20261026*` registradas | 0 |
| Usuarios `zz-a1-*` / teléfonos de prueba | 0 / 0 |
| Vendedoras activas con cuenta | 4 |

## 4. Diferencias entre el esquema esperado y staging

**Ninguna que afecte a A1.**

| Esperado por las migraciones | Staging (real) |
|---|---|
| `20261023000200` (approval_scopes) aplicada | ✓ |
| `20261025000100` (store_discount en el CHECK) aplicada | ✓ |
| CHECK exactamente con 4 valores (la guarda lo exige) | ✓ |
| `f360.can_approve(text, uuid)` presente | ✓ |
| `extensions.crypt` (activación de vendedoras de prueba) | ✓ |
| `f360.location_assignments.granted_at`, `f360.product_knowledge_public`, `f360.product_primary_image`, `f360.color_primary_image` | ✓ (las pruebas los usaron) |
| Al menos 1 tienda activa | ✓ (4) |
| Los 5 modelos del piloto activos y con ficha validada | ✓ (PAULA v2, BYL v1, MAFALDA-TACHES v3, LEATHER-LOAFERS v4, SUECO-CUCARRON v1) |
| Última migración aplicada | `20261025000100`. Las de Inteligencia `20261024000100–0700` también están |

**Observaciones, no diferencias:**
- Staging no tiene aprobadores de `store_discount`. No afecta a Academy.
- Producción **no se revisó** en este paso. Antes de llevar las migraciones a producción hay que repetir el diagnóstico allí, con autorización.

## 5. Propuesta de despliegue aislado de A1 (no arrastra migraciones ni cambios de otras sesiones)

**Restricciones del entorno:**
- Staging se **reescribe cada noche** desde producción y luego aplica `db push` de lo que esté en `origin/fuxia-360`.
- El admin de staging (`fuxia360-staging` en Vercel) se publica desde `fuxia-360`.
- El despliegue del admin a producción publica **toda** `fuxia-360`.

### Propuesta: "ventana de pruebas de A1" de un día, sin tocar `fuxia-360`

| Paso | Qué | Cómo se aísla | Requiere |
|---|---|---|---|
| **D1 · Base** | Aplicar en staging **solo** `20261026000100/0200/0300`, en orden, con un script nuevo `academy_a1_day_apply.mjs`. Cada archivo en su transacción; **sin** escribir en `supabase_migrations.schema_migrations` | No usa `db push`, así que no arrastra migraciones pendientes de nadie. Al no registrar versiones, el `db push` de otra sesión ese día no falla por "versiones remotas que no existen localmente". La copia de las 3:30 lo borra todo | Tu OK |
| **D2 · Cuentas de prueba** | `academy_a1_test_users.mjs` (2 alumnas `@staging.invalid`) + `academy_a1_staging.sql` | Las cuentas `@staging.invalid` sobreviven a la copia; los permisos y fichas de Academy se borran cada noche | Tu OK |
| **D3 · Interfaz** | Despliegue **de vista previa** (no `--prod`) del worktree `academy/a1` en el proyecto `fuxia360-staging`: URL única y temporal | El admin de staging habitual (desde `fuxia-360`) no cambia; nadie más ve Academy. Producción no se toca | Tu OK + verificar en solo lectura (`vercel env ls preview`) que las variables de vista previa apunten a staging y tengan `NEXT_PUBLIC_F360_ENV=staging`; si no, hay que configurarlas (cambio aparte) |
| **D4 · Recorrido** | Alumna 1 (estudia), Alumna 2 (pantalla "todavía no abierta"), Carolina demo (envía, 2FA, publica) | — | — |
| **D5 · Fin** | Nada que limpiar: la copia nocturna borra la base de A1; la URL de vista previa se puede borrar | — | — |

**Riesgos de la propuesta y controles:**

| Riesgo | Control |
|---|---|
| Otra sesión redefine el CHECK de `approval_scopes` ese mismo día | Aviso previo; la guarda aborta si el CHECK cambió |
| Otra sesión aplica una migración que dependa del CHECK de 4 valores mientras A1 está aplicado (7 valores) | Hoy nadie lo hace (confirmado por ambas sesiones); aviso previo |
| La ventana dura solo hasta las 3:30 | Es a propósito: aislamiento total. Si hace falta otro día, se repite D1–D2 (idempotente) con tu OK |
| La vista previa usa variables de otro ambiente | Verificación D3 antes de publicar |
| Confusión entre "probado en staging" y "listo para producción" | Integrar en `fuxia-360` y llevar a producción son decisiones **aparte**. Además, producción necesita su propio diagnóstico, y el acceso real exige que **P0-6 esté cerrado** |

**Lo que NO propone:** integrar en `fuxia-360`, registrar versiones en `schema_migrations`, cambiar el refresco nocturno ni tocar producción.

## 6. Estado

- **P0-6 sigue abierto** y bloquea el piloto con vendedoras reales (`docs/fuxia360/security/P0-6_REMEDIACION.md`).
- **A2 no iniciado.** Espero tu autorización para el siguiente paso (D1–D4, o lo que decidas).
