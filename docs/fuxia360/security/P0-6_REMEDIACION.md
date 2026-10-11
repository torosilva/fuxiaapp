# P0-6 · Remediación del acceso por teléfono (propuesta independiente y prioritaria)

> 2026-10-11 · pedido de Mario (A1): "propuesta de remediación independiente, prioritaria y con pruebas de seguridad".
> **Nada aplicado.** Cada paso necesita su propia autorización. No forma parte de Academy, pero **bloquea** el acceso real de vendedoras a Academy y cualquier canje.
> Análisis de detalle (evidencia con archivo y línea): `docs/fuxia360/academy/P0-6_ACCESO_VENDEDORAS_PROPUESTA.md`.

## 1. El problema en una línea cada uno

| ID | Problema | Quién puede abusarlo | Impacto |
|---|---|---|---|
| **P0-6.3** | `+525555555555` + `555555` abre sesión de una cuenta demo **sin código real**. Los valores están fijos en el código (`fuxia-native/supabase/functions/whatsapp-otp/index.ts:14-19, 183-191`) y no hay interruptor | Cualquiera que lea el código o las notas de revisión de tiendas de apps | Lo que permita esa cuenta (en septiembre era `admin` de la app de clientas) |
| **P0-6.2** | La contraseña de **toda** cuenta por teléfono es `fuxia_{tel}_{OTP_SALT}` (`index.ts:228-229`) | Quien conozca `OTP_SALT` (secreto de Supabase; quien tenga o haya tenido acceso al proyecto) | Sesión como **cualquier** persona: clientas, vendedoras, **Mario y Carolina** (aal1). Dirección queda protegida porque exige TOTP |

## 2. Prioridad y orden

| Prioridad | Paso | Tipo | Tiempo | Bloquea |
|---|---|---|---|---|
| **1** | **Contención de P0-6.3 solo por configuración:** poner `REVIEW_BYPASS_CODE` = valor aleatorio de 32+ caracteres en producción | Secreto (sin despliegue) | 10 min | Nada, **salvo** que haya una revisión de tiendas de apps en curso: antes hay que revisar App Store Connect y Play Console |
| **2** | **Pruebas de seguridad en staging (línea base)**: suite §4 con el estado actual → documenta qué falla hoy | Solo staging | 1 h | — |
| **3** | **P0-6.3 en código:** quitar los valores fijos; entrada de revisión solo si `REVIEW_BYPASS_ENABLED='true'` y los tres valores están configurados | Edge Function, staging → prod | 2 h | Ventana de revisión de tiendas |
| **4** | **P0-6.2: sesión sin contraseña derivada** (§3) | Edge Function + rotación de contraseñas | 1 día | Probar la app publicada |
| **5** | Cuenta demo = clienta común sin privilegios (`customers.role = 'customer'`, sin rol F360, sin ficha de vendedora) | Datos en prod | 15 min | Actualizar las notas de revisión de tiendas |
| **6** | Menores: quitar `debug` de las respuestas, quitar teléfonos de los logs, límite por IP, código guardado como hash | Edge Function | 2 h | — |
| **7** | Suite §4 completa en verde en staging y prueba de humo en prod → **cierre de P0-6** | — | — | Habilita levantar la compuerta de Academy (otra migración revisada) |

## 3. Diseño del paso 4 (P0-6.2)

**Hoy:** la función verifica el código y luego `signInWithPassword({ email: {tel}@fuxia.app, password: fuxia_{tel}_{OTP_SALT} })`.

**Propuesto** (sin contraseñas que se puedan derivar):
1. Verificar el código, igual que hoy: intentos, vencimiento, un solo uso.
2. Asegurar que exista el usuario `{tel}@fuxia.app`. Si se crea, es con una **contraseña aleatoria de 32 bytes que no se guarda**.
3. Emitir la sesión en el servidor sin contraseña: `auth.admin.generateLink({ type: 'magiclink', email })` → `verifyOtp({ type: 'magiclink', token_hash })` con el cliente anónimo. Se devuelve `session` igual que hoy, así que **la app publicada no cambia**.
4. **Rotación única**: un script revisado pone una contraseña aleatoria (no guardada) a cada cuenta `@fuxia.app`. Después se borra `OTP_SALT`.

| Riesgo | Control |
|---|---|
| La app publicada deja de entrar | La respuesta conserva la forma `{ success, session, isNewUser, customer }`; prueba con la app real en staging antes de producción |
| Los magic links quedan expuestos | Nunca salen del servidor; se canjean en la misma llamada |
| Fallo a mitad de la rotación | Script idempotente por lotes; las cuentas sin rotar siguen entrando por código, porque la función nueva no usa contraseñas |
| Reversión | Volver a la versión anterior de la función. Las cuentas rotadas siguen entrando por código |

## 4. Pruebas de seguridad (suite propuesta, staging)

`scripts/f360/p06_security_tests.mjs`, con cuentas `@staging.invalid` y números de laboratorio `+1555010xxxx`. La librería se niega a apuntar a producción.

| # | Prueba | Esperado después de la corrección | Hoy (esperado) |
|---|---|---|---|
| T1 | `verify` con `+525555555555` / `555555` sin `REVIEW_BYPASS_ENABLED` | 401 | **Sesión** |
| T2 | `POST auth/v1/token?grant_type=password` con `{tel}@fuxia.app` / `fuxia_{tel}_{salt}` | 400 (credenciales inválidas) | **Sesión** |
| T3 | 6.º intento con el mismo código | 429 y código invalidado | 429 |
| T4 | 4.º envío en 10 min al mismo teléfono | 429 | 429 |
| T5 | Respuestas de error sin `debug` ni detalles del proveedor | Sin `debug` | `debug` presente |
| T6 | Clienta sin rol llama cada RPC `f360_*` y `f360_academy_*` | Todas niegan | Niegan |
| T7 | Vendedora activa llama RPC de Dirección, Inteligencia, Finanzas, Ejecutiva, panel de Academy | Todas niegan | Niegan |
| T8 | Vendedora **desactivada** con sesión abierta | Niega en la siguiente llamada | Niega |
| T9 | Usuario autenticado inserta en `public.customers` el teléfono de una vendedora pendiente en otros formatos (`55…`, `+52 1 55…`, `0052…`) | Falla; sin rol `seller` | Probablemente falla (índice normalizado); **verificar** |
| T10 | Usuario autenticado cambia su `customers.phone` al de una vendedora pendiente y después su `auth_user_id` | Falla; sin activación | **Verificar** |
| T11 | Sesión aal1 de una dueña intenta aprobar en el registro de Academy o en Dirección | Niega por falta de aal2 | Niega |
| T12 | Inventario automático de funciones `SECURITY DEFINER` expuestas a `authenticated`: cada una decide con `auth.uid()` y no con datos del cliente | Lista sin excepciones injustificadas | Por revisar |
| T13 | Inventario de políticas RLS de `public.*` que dependen de `customers.role`: qué obtiene hoy `admin` / `staff` | Informe | Por revisar |

**Criterio de cierre de P0-6:** T1–T13 en verde en staging; prueba de humo en producción (T1 y T2 con la cuenta demo y una cuenta de laboratorio); notas de revisión de tiendas actualizadas; `OTP_SALT` eliminado.

## 5. Autorizaciones que necesito (una por línea)

1. ☐ Paso 1: confirmar que no hay revisión de tiendas en curso y poner el secreto en producción.
2. ☐ Paso 2: escribir y correr la suite T1–T13 en **staging** (línea base).
3. ☐ Paso 3: cambio de código de la entrada de revisión (staging, luego producción).
4. ☐ Paso 4: sesión sin contraseña + rotación (staging, luego producción).
5. ☐ Paso 5: cuenta demo sin privilegios (dato en producción).
6. ☐ Paso 6: menores.
