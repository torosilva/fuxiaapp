# P0-6 · Acceso por teléfono: hallazgo abierto y propuesta de corrección

> 2026-10-11 · rama `fuxia-360` · pedido de Mario (A0 §3).
> **Solo análisis y propuesta.** No se ejecutó ninguna corrección, consulta ni cambio de secretos. Cada paso de §4 requiere su propia autorización.
> **Estado del hallazgo: ABIERTO.** Es **bloqueante para canjes reales** de Fuxia Academy (A5).

---

## 1. Qué es P0-6 (con evidencia)

| # | Problema | Evidencia | Estado |
|---|---|---|---|
| **P0-6.3** | **Entrada fija de revisión de tiendas de apps.** `+525555555555` con el código `555555` crea una sesión válida para la cuenta demo `+525543412939` **sin código real**. Los valores están fijos en el código; no hay interruptor para apagarla | `fuxia-native/supabase/functions/whatsapp-otp/index.ts:14-19` (valores), `:110-125` (`check_phone`), `:142-146` (`send`), `:183-191`, `:242` (`verify`). Hallazgo original: `docs/fuxia360/audit/SPRINT_0_IMPLEMENTATION_PLAN.md:112, 367-389` | **Abierto.** La contención "A8" se diseñó en Sprint 0 y **no se aplicó**: el código actual conserva los valores fijos. En septiembre la cuenta demo era **admin de la app de clientas** (`customers.role = 'admin'`, `LIVE_RECONCILIATION.md:235`) |
| **P0-6.2** | **Contraseña derivada de un secreto compartido.** Cada cuenta por teléfono es `{teléfono}@fuxia.app` con contraseña `fuxia_{teléfono}_{OTP_SALT}`. Quien conozca `OTP_SALT` puede pedir una sesión de **cualquier** cuenta directo a Supabase Auth, sin código | `index.ts:226-228`; `docs/fuxia360/audit/SECURITY_AUDIT.md:70`; `LIVE_RECONCILIATION.md:84` (el secreto **sí** está configurado; el riesgo de diseño sigue) | **Abierto** |
| menores | Mensaje de error de Twilio devuelto en `debug`; teléfonos en los logs; `check_phone` revela si un número es clienta; código guardado en claro; sin límite por IP | `index.ts:163-166`, `:69-87`, `:110-125`, `:153` | Abiertos, baja prioridad |

---

## 2. ¿Afecta al MVP de capacitación y certificaciones?

**Sí, y no solo por la cuenta de revisión.** No se asume que el riesgo queda contenido porque esa cuenta no tenga rol.

| Vía | Qué permitiría hoy | Efecto en el MVP de Academy | Efecto fuera de Academy |
|---|---|---|---|
| **P0-6.2: contraseña derivada** | Sesión como **cualquier** persona que entra por teléfono: vendedoras, **Mario y Carolina** (sus cuentas de Fuxia 360 en producción también son por teléfono; el acceso con correo solo existe en staging, `admin-web/src/app/login/actions.ts:59-66`) | Una sesión falsa de **vendedora** puede presentar exámenes por ella y sumar XP y puntos (sin valor mientras no haya canjes). Una sesión falsa de **Carolina o Mario** podría **aprobar o publicar contenido** y hacer acciones de administración de Academy **si esas operaciones no exigen segundo factor** | Todo lo que un `owner` hace con sesión normal (inventario, productos, vendedoras, aprobaciones sin 2FA). Lo de Dirección queda protegido porque exige TOTP (aal2) |
| **P0-6.3: entrada fija** | Sesión válida como la cuenta demo, para **cualquiera** que lea los documentos de revisión de tiendas o el código | Ninguno, **si** la cuenta demo no tiene ficha de vendedora ni permiso de Academy: Academy decide en la base, no en la pantalla. **Se verifica con Q4** y con las pruebas de §4.3 | Lo que permitan las reglas de la app de clientas para una cuenta `admin` en `public.*` |
| Escalamiento por activación de vendedora | Si alguien pudiera crear o ligar una fila de `public.customers` con el teléfono de una vendedora **pendiente**, el trigger `customers_activate_seller` (`supabase/migrations/20261013000100_f360_sellers_admin.sql:67-80`) le daría **el rol `seller`** | Acceso de alumna a Academy y lectura de inventario como vendedora (sin PIN no opera) | Igual |
| — | Por qué parece cerrado hoy | La política `customers self insert` solo permite insertar con su propio `auth_user_id` (`20260924000000_baseline_live_public_schema.sql:1300`). El índice único sobre el teléfono **normalizado** (`20261010000100_f360_crm_c1_customer_profile.sql:51`) impide una segunda fila con el mismo teléfono escrito distinto. La alta de una vendedora sin cuenta crea su fila de `customers` (`20261013000100…:1-12`) | **No se da por cerrado:** depende de que esa fila exista siempre y de que el índice esté en producción. Va en las pruebas de §4.3 |

**Conclusión para Academy:**

1. **Canjes reales (A5): bloqueados** hasta cerrar P0-6.2 y P0-6.3.
2. **MVP (A1–A3):** puede avanzar en staging. **Antes de usarse en producción**, Academy debe cumplir, por diseño y aunque P0-6 siga abierto:
   - **Toda** aprobación y acción de administración de Academy exige **segundo factor (aal2)**, incluida `academy_content.publish_sales`. Esto **endurece** el catálogo de operaciones de §4.1.2: allí `publish_sales` no lo exigía. Así, una sesión obtenida con la contraseña derivada no publica contenido ni toca puntos.
   - La alumna se deriva **solo** de `f360.sellers.status = 'activa'` y de permisos explícitos. Nunca de `customers.role`, `user_metadata` ni del teléfono enviado por el navegador.
   - Las pruebas de §4.3 pasan en staging.
3. **Riesgo residual del MVP con P0-6 abierto:** alguien con `OTP_SALT` puede hacerse pasar por una vendedora en sus exámenes. Es bajo mientras los puntos no tengan valor, y se reduce con el cierre de P0-6.2.
4. **Fuera de Academy**, P0-6.2 afecta a todo Fuxia 360. **Recomiendo cerrarlo antes de abrir el MVP a todas las vendedoras**, aunque técnicamente no bloquea el piloto. La decisión es tuya.

---

## 3. Principios de la corrección

- Se corrige en `whatsapp-otp`, que es una **función compartida con la app de clientas publicada**. Cualquier cambio debe mantener funcionando el ingreso de las clientas.
- Sin dependencias nuevas, salvo las de Supabase Auth.
- Primero staging, con pruebas, y después producción, coordinado con las otras sesiones y con la revisión de tiendas de apps.

---

## 4. Propuesta (cada paso requiere autorización por separado)

### 4.1 Eliminar o aislar la entrada fija (P0-6.3)

| Paso | Qué | Efecto | Riesgo / reversión |
|---|---|---|---|
| **a. Contención inmediata, solo configuración** | Poner `REVIEW_BYPASS_CODE` en producción con un valor largo y aleatorio. El código ya lo lee (`index.ts:18`) | `555555` deja de funcionar **sin desplegar código** | **Rompe el acceso de los revisores de Apple y Google** si hay una revisión en curso. Antes hay que revisar App Store Connect y Play Console. Reversión: quitar el secreto |
| **b. Corrección de código (el "A8" de Sprint 0)** | Quitar los valores fijos. La entrada de revisión funciona **solo** si `REVIEW_BYPASS_ENABLED = 'true'` **y** los tres valores están configurados; si no, ese número se trata como cualquier otro | Se apaga fuera de las ventanas de revisión | Despliegue de la función; prueba con un número normal y con el de revisión |
| **c. Cuenta demo sin privilegios** | La cuenta de revisión pasa a ser una **clienta común**: sin `admin` ni `staff` en `customers`, sin rol de Fuxia 360, sin ficha de vendedora ni permisos de Academy. Q4 dice cómo está hoy | Aunque alguien la use, no ve nada interno | Cambio de datos en producción con su propia autorización. Actualizar las notas de revisión de las tiendas de apps |

### 4.2 Sustituir la contraseña derivada (P0-6.2)

**Recomendado:** que la función **no conozca ni derive contraseñas**. Tras verificar el código, crea la sesión con la API de administración de Supabase Auth, generando un *magic link* o un OTP de Auth y canjeándolo en el servidor (`auth.admin.generateLink` + `verifyOtp`), sin contraseña.
- Las cuentas existentes quedan con una **contraseña aleatoria nueva e inútil**, rotada una vez con un script revisado. Así deja de existir una fórmula que reproduzca contraseñas.
- `OTP_SALT` se elimina después.

| Alternativa | A favor | En contra |
|---|---|---|
| **Sesión emitida por Auth sin contraseña (recomendada)** | Elimina el secreto compartido; cada sesión sale de un canje de un solo uso | Cambio de función + rotación masiva de contraseñas (una vez); probar la app de clientas publicada |
| Contraseña aleatoria por cuenta, guardada cifrada | Cambio menor en la función | Sigue habiendo contraseñas que proteger; no resuelve el diseño |
| Phone auth nativo de Supabase (proveedor SMS/WhatsApp) | Estándar | Cambio grande en la app de clientas y en el proveedor de mensajes |

**Secuencia:**
1. Staging: nueva función + rotación de las cuentas de staging + pruebas §4.3.
2. Confirmar que la app publicada sigue entrando. La app solo recibe `session` de la función, así que no debería notar el cambio.
3. Producción: desplegar la función, rotar contraseñas con script revisado, eliminar `OTP_SALT`.

**Reversión:** volver a la versión anterior de la función. Las cuentas rotadas siguen entrando por código, porque la función ya no usa contraseñas.

### 4.3 Validar autenticación y permisos de vendedoras (pruebas automatizadas)

Con sesiones reales de staging. Se agregan a `scripts/f360/db_tests.mjs` o a una suite nueva, sin tocar producción:

| # | Prueba | Esperado |
|---|---|---|
| T1 | Login con el número de revisión y `555555`, con la entrada apagada | Rechazado, como cualquier código incorrecto |
| T2 | Login con contraseña derivada `fuxia_{tel}_{salt}` tras la corrección 4.2 | Rechazado |
| T3 | Clienta común (sin rol) llama cada RPC `f360_*` y `f360_academy_*` | Todas niegan |
| T4 | Vendedora activa llama RPC de Dirección, Inteligencia, Finanzas, Ejecutiva, panel de Academy y progreso de otra vendedora | Todas niegan |
| T5 | Vendedora **desactivada** con sesión abierta llama RPC de Academy | Niega en la siguiente llamada |
| T6 | Usuario autenticado inserta en `public.customers` el teléfono de una vendedora **pendiente**, en otros formatos (`55…`, `+52 1 55…`, `0052…`) | Falla por el índice normalizado; la vendedora sigue pendiente; sin rol `seller` nuevo |
| T7 | Usuario autenticado cambia su propio `customers.phone` al de una vendedora pendiente y luego su `auth_user_id` | Falla; sin activación |
| T8 | Sesión aal1 de una dueña intenta `publish_sales`, ajustar puntos, cambiar reglas o revocar | Niega por falta de aal2 |
| T9 | Cualquier sesión intenta escribir directo en las tablas de Academy y del registro de aprobaciones | Niega (sin permisos de tabla) |
| T10 | Cuenta demo de revisión (en staging) llama RPC de Fuxia 360 y Academy | Todas niegan |
| T11 | Revisión del catálogo de funciones `SECURITY DEFINER` expuestas a `authenticated` en `public` y `f360`: cada una decide con `auth.uid()` y nunca confía en un rol, id o teléfono que mande el cliente | Lista revisada, sin excepciones sin justificar |

### 4.4 Probar que no hay rutas de escalamiento de privilegios

Además de T6, T7 y T11:
- inventario de **todos los triggers que asignan roles o permisos** (hoy: `customers_activate_seller`; cualquier otro que se encuentre);
- inventario de las **políticas RLS de `public.*` que dependen de `customers.role`**, para saber qué obtiene una cuenta `admin` o `staff` de la app de clientas;
- revisión de que ningún flujo de Fuxia 360 derive privilegios de `customers.role` o de `user_metadata`.

Se entrega como informe con evidencia (archivo y línea) **antes** de proponer correcciones adicionales.

---

## 5. Orden recomendado y qué necesito de ti

| Orden | Paso | Necesita |
|---|---|---|
| 1 | Q4 (en A0) para saber qué es hoy la cuenta demo | Tu autorización de Q4 |
| 2 | §4.1a contención por configuración | Confirmar que no hay revisión de tiendas en curso + tu autorización |
| 3 | §4.3 / §4.4 pruebas e informe en staging | Tu autorización (no toca producción) |
| 4 | §4.1b + §4.2 en staging | Tu autorización |
| 5 | §4.1c, despliegue y rotación en producción | Tu autorización, coordinada con las otras sesiones y con la app de clientas |

**Nada de esto se ejecuta como parte de A0.**
