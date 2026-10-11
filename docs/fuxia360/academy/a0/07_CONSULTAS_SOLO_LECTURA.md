# A0 · 07 — Consultas de solo lectura (Q1–Q4)

> **Estado: PREPARADAS — NO EJECUTADAS.** Esperan la autorización expresa de Mario (A0 §2, 2026-10-11).
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

**Resultado:** *(pendiente de autorización)*

---

## Q2 — Campos faltantes por modelo

**No se ejecuta.** Se calcula del resultado de Q1: para cada modelo, los campos de `product_knowledge` en `NULL`, si la ficha no está `validado` y si el modelo está archivado.

**Resultado:** *(se calcula después de Q1)*

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

**Resultado:** *(pendiente de autorización)*

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

**Resultado:** *(pendiente de autorización)*

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
