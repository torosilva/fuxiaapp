# Q4 · Revisión final (NO ejecutar todavía)

> 2026-10-11 · pedido de Mario (A1): "Presentar el SQL corregido y las evidencias de identidad necesarias para una última revisión. No ejecutar todavía."
> Recordatorio: **una respuesta negativa en Q4 no resuelve P0-6** (`docs/fuxia360/security/P0-6_REMEDIACION.md`).

## 1. Evidencias de identidad

| # | Afirmación | Evidencia | Estado |
|---|---|---|---|
| E1 | La entrada de revisión autentica como `REVIEW_DEMO_PHONE`, y si el secreto no existe usa el valor fijo `+525543412939` | `fuxia-native/supabase/functions/whatsapp-otp/index.ts:19` (`?? '+525543412939'`), `:189` (`authPhone = isReviewBypass ? REVIEW_DEMO_PHONE : phone`) | ✓ Código del repo |
| E2 | El correo de esa cuenta se deriva del teléfono: `525543412939@fuxia.app` | `index.ts:228` (``fakeEmail = `${authPhone.replace('+', '')}@fuxia.app` ``) | ✓ Código del repo |
| E3 | La cuenta se crea con `user_metadata.phone = authPhone` | `index.ts:239-244` | ✓ Código del repo |
| E4 | La ficha de clienta se liga a esa cuenta por teléfono | `index.ts:260-272` (`customers.phone = authPhone` → `auth_user_id`) | ✓ Código del repo |
| E5 | En producción, `REVIEW_DEMO_PHONE` **no** está configurado (rige el valor fijo) | `docs/fuxia360/audit/LIVE_RECONCILIATION.md:49` | ⚠ Evidencia de **septiembre**; no verificada hoy |
| E6 | La función desplegada en producción es la del repo | `docs/fuxia360/audit/SPRINT_0_IMPLEMENTATION_PLAN.md:367` (verificado el 2026-09-24) | ⚠ No verificada hoy |

**Cómo cerrar E5 y E6 (cada uno necesita su propia autorización; ninguno es una consulta a la base):**
- **E5:** `supabase secrets list --project-ref tgzgiwfzddsghnxgkcqd`. Muestra **solo nombres** de secretos, no valores. Si `REVIEW_DEMO_PHONE` no aparece, rige `+525543412939`. Puedes ejecutarlo tú con `! supabase secrets list --project-ref tgzgiwfzddsghnxgkcqd`.
- **E6:** `supabase functions download whatsapp-otp --project-ref tgzgiwfzddsghnxgkcqd` en un directorio temporal y comparar contra el repo. Es lectura del código desplegado.

**Además, la propia Q4 se auto-verifica:** si no se cumplen las tres condiciones de §3, sus demás resultados no se interpretan.

## 2. SQL final (sin cambios respecto a la corrección de A0 `07`)

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
| Entorno | Producción (`tgzg…`), con `scripts/f360/prod_read.sh` (`BEGIN READ ONLY … COMMIT`, una sentencia) |
| Tipo | Solo `SELECT`; funciones de lectura (`f360.normalize_phone`, IMMUTABLE) |
| Tablas | `auth.users`, `public.customers`, `f360.user_roles`, `f360.sellers`, `f360_board.board_members`, `f360_board.finance_preparers`, `f360.approval_scopes`, `f360.weekly_people` |
| Registros | 1 fila: 2 conteos + 12 sí/no |
| Exposición | Ningún id, teléfono, nombre ni correo en la salida |
| Dependencia | `f360.approval_scopes` en producción (`20261023000200`). Si no existe, la consulta falla completa y sin efectos |
| Ejecuciones | **Una**, sin reintentos |

## 3. Cómo se interpreta

1. **Misma cuenta** solo si `cuentas_con_ese_correo = 1`, `metadata_mismo_telefono = sí` y `clienta_ligada_mismo_telefono = sí`. Si no, se detiene la interpretación y se informa.
2. Cualquier "sí" en `cuenta_rol_f360`, `cuenta_ficha_vendedora`, `telefono_ficha_vendedora`, `cuenta_miembro_direccion`, `cuenta_contadora` o `cuenta_aprobador_alguno` → **incidente**: la entrada pública da acceso interno. Se recomienda el paso 1 de la remediación **de inmediato**.
3. `cuenta_clienta_role_admin = sí` → la entrada pública da privilegios de **admin en la app de clientas** (hallazgo G3 de septiembre, sigue vigente).
4. Todo "no" → la cuenta demo no tiene acceso interno, pero **P0-6 sigue abierto**: la contraseña derivada no depende de esta cuenta.
