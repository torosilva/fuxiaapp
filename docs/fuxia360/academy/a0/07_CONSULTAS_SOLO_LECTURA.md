# A0 · 07 — Consultas de solo lectura (Q1–Q4)

> **Estado (2026-10-11):**
> - **Q1 y Q3 ejecutadas una vez cada una**, con autorización expresa de Mario.
> - **Q2** calculada de Q1.
> - **Q4 NO ejecutada:** no se pudo confirmar la condición de Mario (ver Q4); se presenta corregida.
>
> **Verificaciones previas pedidas por Mario:**
> - `scripts/f360/prod_read.sh` sin cambios desde su único commit (`6b7d9f0`). Envuelve en `BEGIN READ ONLY; … ; COMMIT;` (línea 14) y rechaza `;` (línea 13).
> - `f360.product_primary_image` y `f360.color_primary_image` están definidas una sola vez (`20260926000100_f360_p21_product_master.sql:104-115`) como `LANGUAGE sql STABLE`, con un único `SELECT coalesce(…)`: sin efectos secundarios.
> Sin consultas adicionales y sin tareas programadas. Cada consulta se ejecuta **una sola vez**, a mano, y su resultado se pega abajo con la fecha.

## Datos comunes a las cuatro consultas

| Concepto | Valor |
|---|---|
| **Entorno** | **Producción** de Fuxia 360 (proyecto Supabase `tgzg…`, la base de la app y de Fuxia 360) |
| **Base** | Postgres de ese proyecto (`postgres`) |
| **Cómo se ejecuta** | `scripts/f360/prod_read.sh` (existente). Envía la consulta a la API de administración de Supabase (`/v1/projects/{ref}/database/query`) envuelta en `BEGIN READ ONLY; … ; COMMIT;`. Rechaza el texto si contiene `;`, o sea, una sola sentencia |
| **Permisos usados** | El token de la **CLI de Supabase** de Mario, guardado en el llavero de macOS (la misma sesión de `supabase login`). La API ejecuta como el rol de administración de la base, que **podría** escribir; por eso la protección es la transacción `READ ONLY`, que hace que Postgres **rechace cualquier escritura** (INSERT, UPDATE, DELETE, DDL) con error. El script no imprime el token ni la URL |
| **Tipo** | Solo `SELECT` (más funciones `STABLE` de lectura: `f360.product_primary_image`, `f360.color_primary_image`). Ninguna función con efectos |
| **Salida** | JSON por la terminal. Se pega aquí, en el repo. Nada se envía a otro servicio |
| **Registro** | Fecha, consulta y resultado en este archivo, versionado en `fuxia-360` |

**Q2 se calcula sin consultar.** En el diseño (§9.5), Q2 ("qué campos faltan por modelo") era otra consulta. Sale íntegra del resultado de Q1, así que **se calcula localmente y no se ejecuta**. Quedan **tres ejecuciones**: Q1, Q3 y Q4.

---

## Q1 — Datos de producto por modelo (Ballerinas)

**Para qué:** llenar las 28 fichas educativas con lo validado y marcar lo que falta.

```sql
SELECT p.code, p.name, p.status,
  f360.product_primary_image(p.id) AS foto_principal,
  (SELECT string_agg(s.label, ',' ORDER BY s.sort) FROM f360.product_sizes s WHERE s.product_id = p.id) AS tallas,
  (SELECT jsonb_agg(jsonb_build_object('color', c.name, 'codigo', c.code, 'foto', f360.color_primary_image(c.id)) ORDER BY c.sort, c.created_at)
     FROM f360.product_colors c WHERE c.product_id = p.id) AS colores,
  k.status AS ficha_estado, k.version AS ficha_version, k.validated_at::date AS ficha_validada, k.validated_by_name AS ficha_validada_por,
  k.fit_category, k.between_sizes, k.recommended_size_note, k.last_fit, k.width_fit,
  k.material_upper, k.material_lining, k.material_sole, k.heel_height_cm, k.toe_type,
  k.comfort_notes, k.care_instructions
FROM f360.products p
LEFT JOIN f360.product_knowledge k ON k.product_id = p.id
WHERE p.category_key = 'ballerinas'
ORDER BY p.status, p.name
```

| Concepto | Detalle |
|---|---|
| Tablas y columnas | `f360.products` (`id`, `code`, `name`, `status`, `category_key`); `f360.product_sizes` (`product_id`, `label`, `sort`); `f360.product_colors` (`id`, `product_id`, `name`, `code`, `sort`, `created_at`); `f360.product_knowledge` (los 12 campos de producto + `status`, `version`, `validated_at`, `validated_by_name`); `f360.product_media` (vía las dos funciones de foto) |
| Registros esperados | **≈ 32 filas** (28 activos + 4 archivados), una por modelo |
| Exposición | Datos de **producto**. Única persona: `validated_by_name`, el nombre de quien validó (Carolina o Mario), que se muestra en la ficha como "validada por". Las rutas de foto son de Storage público (las mismas de la tienda). **Sin clientas, teléfonos ni montos** |

**Resultado (2026-10-11, una ejecución, sin errores):**
- **32 filas** (28 activos, 4 archivados); 36.5 KB de JSON.
- Los valores por modelo están **copiados tal cual** en `03_FICHAS_BALLERINAS.md`.
- El JSON crudo quedó en el directorio temporal de la sesión, fuera del repo.
- **Coincide con la medición del 11-oct:** 27 fichas validadas (todas de los activos), 0 con cuidados; todos los modelos con tallas 35–40.
- **Nuevo:** el activo sin ficha es **Pointed Aladdin**; 5 modelos son "talla chica"; 0 "talla grande".

---

## Q2 — Campos faltantes por modelo

**No se ejecuta.** Se calcula del resultado de Q1: para cada modelo, los campos de `product_knowledge` en `NULL`, si la ficha no está `validado` y si el modelo está archivado.

**Resultado:** tabla "Por modelo" de `03_FICHAS_BALLERINAS.md`.
- **Campos validados:** 279 de 336 (83 %).
- **Faltantes por campo** (de 28 activos): cuidados 28 · tacón 11 · nota de talla 4 · suela 4 · forro 2 · exterior 2 · los demás 1 (Pointed Aladdin).

---

## Q3 — Descripciones existentes (material de apoyo para Carolina)

**Para qué:** darle a Carolina el texto que ya existe en el catálogo. Ella decide si algo sirve para beneficios o recomendaciones. **No se enseña como dato** (no pasa por validación).

```sql
SELECT p.code, p.name, p.short_description, left(regexp_replace(coalesce(p.description, ''), '<[^>]+>', ' ', 'g'), 400) AS descripcion_400
FROM f360.products p
WHERE p.category_key = 'ballerinas' AND p.status = 'active'
ORDER BY p.name
```

| Concepto | Detalle |
|---|---|
| Tablas y columnas | `f360.products` (`code`, `name`, `short_description`, `description`, `category_key`, `status`) |
| Registros esperados | **≈ 28 filas** |
| Exposición | Texto de catálogo, el mismo que publica la tienda. Sin datos personales. Se quitan etiquetas HTML y se corta a 400 caracteres |

**Resultado (2026-10-11, una ejecución, sin errores):** **28 filas**. Las descripciones están en el anexo de `06_VALIDACION_CAROLINA.md`, como material de apoyo, **no** validado. Solo 1 modelo (Leo Penny) tiene descripción corta.

---

## Q4 — Verificación de la cuenta de revisión de tiendas de apps (P0-6)

**Para qué:** saber qué puede hacer hoy la cuenta a la que entra el código fijo de revisión. **Responde solo sí/no**: no devuelve ids, teléfonos, nombres ni correos.

La cuenta demo es `+525543412939`, valor fijo por omisión en `fuxia-native/supabase/functions/whatsapp-otp/index.ts:19`. En septiembre, `REVIEW_DEMO_PHONE` **no** estaba configurado en producción (`docs/fuxia360/audit/LIVE_RECONCILIATION.md:49`), así que rige el valor fijo. Su usuario de Auth es `525543412939@fuxia.app` (`index.ts:226`).

```sql
WITH demo AS (SELECT id FROM auth.users WHERE email = '525543412939@fuxia.app')
SELECT jsonb_build_object(
  'demo_tiene_cuenta_auth',        EXISTS (SELECT 1 FROM demo),
  'demo_rol_f360',                 EXISTS (SELECT 1 FROM f360.user_roles r JOIN demo d ON d.id = r.auth_user_id),
  'demo_ficha_vendedora',          EXISTS (SELECT 1 FROM f360.sellers s LEFT JOIN demo d ON d.id = s.auth_user_id
                                           WHERE d.id IS NOT NULL OR s.phone = '+525543412939'),
  'demo_miembro_direccion',        EXISTS (SELECT 1 FROM f360_board.board_members b JOIN demo d ON d.id = b.auth_user_id),
  'demo_contadora',                EXISTS (SELECT 1 FROM f360_board.finance_preparers f JOIN demo d ON d.id = f.auth_user_id),
  'demo_en_tablero_semanal',       EXISTS (SELECT 1 FROM f360.weekly_people w WHERE w.phone = '+525543412939'),
  'demo_aprobador_alguno',         EXISTS (SELECT 1 FROM f360.approval_scopes a JOIN demo d ON d.id = a.auth_user_id),
  'demo_customers_role_admin',     EXISTS (SELECT 1 FROM public.customers c WHERE f360.normalize_phone(c.phone) = '+525543412939' AND c.role = 'admin'),
  'demo_customers_role_staff',     EXISTS (SELECT 1 FROM public.customers c WHERE f360.normalize_phone(c.phone) = '+525543412939' AND c.role = 'staff'))
```

| Concepto | Detalle |
|---|---|
| Tablas y columnas | `auth.users` (`id`, `email`); `f360.user_roles` (`auth_user_id`); `f360.sellers` (`auth_user_id`, `phone`); `f360_board.board_members` (`auth_user_id`); `f360_board.finance_preparers` (`auth_user_id`); `f360.weekly_people` (`phone`); `f360.approval_scopes` (`auth_user_id`); `public.customers` (`phone`, `role`) |
| Registros esperados | **1 fila** con 9 valores sí/no |
| Exposición | Ninguna salida identifica a nadie. El número y el correo de la cuenta demo ya están escritos en el código y en los documentos de las tiendas de apps |
| Dependencias | `f360.approval_scopes` existe en producción solo si ya se aplicó `20261023000200` (la otra sesión lo sube hoy). **Si no existe, la consulta falla completa** sin efectos; en ese caso se quita esa línea y se pide de nuevo la autorización con el texto corregido |

**NO EJECUTADA (2026-10-11).**

**Condición de Mario:** antes de ejecutar, verificar que el correo de `auth.users` y el teléfono usado en las demás comprobaciones correspondan a **la misma cuenta de revisión**.

| Qué se pudo confirmar | Evidencia |
|---|---|
| ✓ El correo **se deriva** del teléfono: la función construye `{teléfono sin +}@fuxia.app`, así que `+525543412939` ↔ `525543412939@fuxia.app` | `whatsapp-otp/index.ts:226` |
| ✗ Que **hoy** la cuenta de revisión siga siendo `+525543412939` | Depende del secreto `REVIEW_DEMO_PHONE` en producción. La última evidencia de que no estaba configurado (y rige el valor fijo) es de **septiembre** (`LIVE_RECONCILIATION.md:49`). Comprobarlo hoy es una consulta adicional no autorizada |
| ✗ Que la versión **desplegada** de la función sea la del repo | Verificado el 2026-09-24 (`SPRINT_0_IMPLEMENTATION_PLAN.md:367`); no hoy |
| ✗ Que en la base la cuenta, su metadata y su ficha de clienta apunten al mismo teléfono | La Q4 original no lo comprobaba: mezclaba búsquedas por id y por teléfono |

### Q4 corregida (para nueva autorización)

Verifica **dentro de la misma consulta** que correo, metadata, ficha de clienta y teléfono son la misma cuenta. Todas las comprobaciones de privilegio se hacen **por el id de esa cuenta** (y, aparte, por teléfono, para detectar fichas sueltas). Solo devuelve conteos y sí/no.

```sql
WITH demo AS (SELECT id, raw_user_meta_data->>'phone' AS meta_phone FROM auth.users WHERE email = '525543412939@fuxia.app')
SELECT jsonb_build_object(
  'cuentas_con_ese_correo',            (SELECT count(*) FROM demo),
  'metadata_mismo_telefono',           EXISTS (SELECT 1 FROM demo WHERE f360.normalize_phone(meta_phone) = '+525543412939'),
  'clienta_ligada_a_esa_cuenta',       EXISTS (SELECT 1 FROM public.customers c JOIN demo d ON d.id = c.auth_user_id),
  'clienta_ligada_mismo_telefono',     EXISTS (SELECT 1 FROM public.customers c JOIN demo d ON d.id = c.auth_user_id WHERE f360.normalize_phone(c.phone) = '+525543412939'),
  'clientas_con_ese_telefono',         (SELECT count(*) FROM public.customers c WHERE f360.normalize_phone(c.phone) = '+525543412939'),
  'cuenta_rol_f360',                   EXISTS (SELECT 1 FROM f360.user_roles r JOIN demo d ON d.id = r.auth_user_id),
  'cuenta_ficha_vendedora',            EXISTS (SELECT 1 FROM f360.sellers s JOIN demo d ON d.id = s.auth_user_id),
  'telefono_ficha_vendedora',          EXISTS (SELECT 1 FROM f360.sellers s WHERE s.phone = '+525543412939'),
  'cuenta_miembro_direccion',          EXISTS (SELECT 1 FROM f360_board.board_members b JOIN demo d ON d.id = b.auth_user_id),
  'cuenta_contadora',                  EXISTS (SELECT 1 FROM f360_board.finance_preparers f JOIN demo d ON d.id = f.auth_user_id),
  'cuenta_aprobador_alguno',           EXISTS (SELECT 1 FROM f360.approval_scopes a JOIN demo d ON d.id = a.auth_user_id),
  'telefono_tablero_semanal',          EXISTS (SELECT 1 FROM f360.weekly_people w WHERE w.phone = '+525543412939'),
  'cuenta_clienta_role_admin',         EXISTS (SELECT 1 FROM public.customers c JOIN demo d ON d.id = c.auth_user_id WHERE c.role = 'admin'),
  'cuenta_clienta_role_staff',         EXISTS (SELECT 1 FROM public.customers c JOIN demo d ON d.id = c.auth_user_id WHERE c.role = 'staff'))
```

| Concepto | Detalle |
|---|---|
| Tablas y columnas | `auth.users` (`id`, `email`, `raw_user_meta_data->>'phone'`); `public.customers` (`auth_user_id`, `phone`, `role`); `f360.user_roles`, `f360.sellers`, `f360_board.board_members`, `f360_board.finance_preparers`, `f360.approval_scopes` (`auth_user_id`); `f360.sellers.phone`; `f360.weekly_people.phone` |
| Registros | 1 fila: 2 conteos + 12 sí/no |
| Exposición | Ningún id, teléfono, nombre ni correo en la salida |
| Interpretación | Es la misma cuenta si `cuentas_con_ese_correo = 1`, `metadata_mismo_telefono = sí` y `clienta_ligada_mismo_telefono = sí`. Si no se cumple, **no se interpretan** los demás valores |
| Dependencia | `f360.approval_scopes` debe existir en producción (`20261023000200`). Si no existe, la consulta falla completa y sin efectos |
| Lo que **no** confirma | Que la función desplegada use hoy ese teléfono (secreto `REVIEW_DEMO_PHONE`). Para eso hace falta `supabase secrets list --project-ref tgzg…`, que solo muestra **nombres** de secretos, no valores. Es otra lectura y necesita su propia autorización; Mario puede ejecutarla con `! supabase secrets list --project-ref <ref>` |

**Recordatorio (Mario, 2026-10-11):** una respuesta negativa en Q4 **no** resuelve P0-6. P0-6 debe corregirse **antes** de dar acceso real de vendedoras a Academy.

---

## Riesgos de la ejecución y cómo se controlan

| Riesgo | Control |
|---|---|
| Escritura accidental en producción | Transacción `READ ONLY` (Postgres la rechaza); solo `SELECT`; una sentencia por ejecución |
| Exposición de datos personales | Q1 y Q3: solo producto. Q4: solo sí/no. Nada de clientas |
| Carga sobre la base | ≈ 32 + 28 + 1 filas; tablas chicas; sin barridos de ventas ni inventario |
| Credenciales en pantalla o en logs | El script no imprime token ni URL; no se usa `ps` ni se listan procesos |
| Que el permiso de la sesión bloquee la ejecución | No se reintenta ni se rodea. Se le pide a Mario ejecutarla con `! scripts/f360/prod_read.sh <<'SQL' … SQL` |
| Consultas fuera de la lista | Prohibidas. Una consulta nueva o corregida requiere otra autorización |
