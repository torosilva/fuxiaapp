# A1 · Ventana temporal de pruebas funcionales en staging (resultado)

> 2026-10-11 · autorizado por Mario (condiciones 1–10). Rama `academy/a1` (`f17577a` + scripts `692e052`).
> - **Ventana:** 12:53 → 13:01 CST, fuera de la copia nocturna de 3:30 a 3:50.
> - **Limpieza manual ejecutada y comprobada:** staging quedó **idéntico** al estado previo.
> - **No** se integró nada en `fuxia-360`, **no** se usó `db push`, **no** se tocó producción ni el panel compartido, y **no** se habilitó acceso de vendedoras reales.

## 1. Condiciones

| # | Condición | Cumplimiento |
|---|---|---|
| 1 | Otras sesiones sin migraciones ni pruebas incompatibles | **fuxiaapp-ed** terminó su ensayo de rollback (revertido) antes y solo leyó durante la ventana. **fuxiaapp-2d** respondió "libre" y dejó en espera su copia de Supabase. Ambas avisadas al terminar |
| 2 | Variables y credenciales de la vista previa solo de staging | `vercel env pull --environment=preview` a un archivo temporal, inspección **solo de destinos**, archivo borrado. `NEXT_PUBLIC_F360_ENV=staging`; `NEXT_PUBLIC_SUPABASE_URL=https://faltx….supabase.co`; llave anónima con `ref=faltxpkaicwpnlqaxrdu`, `role=anon`; sin llaves de servicio ni referencias a `tgzg…` |
| 3 | Limpieza manual presentada **y comprobada** | `academy_a1_window.mjs rehearse-cleanup`: aplicar + datos + limpiar dentro de una transacción revertida. Primer ensayo: limpia todo, pero rearmaba el CHECK en orden alfabético → corregido para conservar el orden vivo (`f17577a`). Segundo ensayo: CHECK idéntico, sin esquema, sin registro, sin RPC, sin datos de prueba |
| 4 | Solo las 3 migraciones, procedimiento aislado, sin `db push` | `academy_a1_window.mjs apply`: verificación previa de solo lectura (sin `f360_academy`, sin registro, sin `20261026*` registradas) y luego **una transacción por archivo** |
| 5 | Versiones exactas registradas y estado temporal documentado | En `f360_academy.staging_window`, tabla temporal (ver §2). **No** se escribieron filas en `supabase_migrations.schema_migrations`: las migraciones **no** formaron parte del historial oficial |
| 6 | Solo las 2 alumnas ficticias | `alumna.prueba1@staging.invalid` y `alumna.prueba2@staging.invalid`, con teléfonos ficticios `+1 555 019 0901/0902`. Sin datos reales. Fichas de vendedora por inserción directa (sin registros de auditoría imborrables) |
| 7 | Solo una vista previa temporal | `vercel deploy` **sin** `--prod` al proyecto `fuxia360-staging` → `target: null`, `productionUrl: null`, protegida con Vercel Authentication. El panel de staging habitual y producción no cambiaron. **Vista previa eliminada** al final (`vercel remove`) |
| 8 | Recorrido funcional | §3: **27/27** por API con sesiones reales + **7/7** en la interfaz |
| 9 | Las 4 vendedoras reales siguen bloqueadas | Verificado **dos veces** con Academy instalado: `vendedoras reales activas: 4 · bloqueadas: 4 · con acceso: 0` |
| 10 | Limpieza manual y comprobación final | §4 |

## 2. Estado temporal: versiones aplicadas (fuera del historial oficial)

| Versión | Nombre | sha256 (12) | Commit de la rama | Aplicada |
|---|---|---|---|---|
| 20261026000100 | f360_approval_registry | `68dcbc31a91a` | `f17577a` | 12:54:37 CST |
| 20261026000200 | f360_academy_a1 | `6d5289aeb429` | `f17577a` | 12:54:37 CST |
| 20261026000300 | f360_academy_pilot_seed | `24635bd9acf9` | `f17577a` | 12:54:37 CST |

Estuvieron aplicadas **≈ 6 minutos** (12:54:37 → 13:00:05), **sin** fila en `schema_migrations`. Así, el `db push` de otra sesión no habría fallado por versiones desconocidas. La limpieza las quitó.

## 3. Recorrido funcional

### 3.1 Por API, con sesiones reales (`academy_a1_walkthrough.mjs`): 27/27 PASS

| Área | Comprobado |
|---|---|
| Acceso permitido y denegado | Alumna 2 (vendedora activa sin permiso de prueba) **bloqueada** y sin cursos; Alumna 1 con acceso; el borrador no es visible antes de publicarse; la alumna no entra al panel |
| Revisión y publicación | Borrador de 7 lecciones y 24 preguntas; vista previa con las 5 fichas validadas en vivo; comentario de revisión; envío → solicitud `publish_sales` con huella; lo enviado ya no se edita; Mario no aprueba contenido ordinario; **Carolina sin segundo factor no aprueba**; Carolina con **factor TOTP temporal (aal2)** aprueba y publica (dos personas, sin autoaprobación); historial solicitada → aprobada → usada |
| Lecciones y progreso | El curso publicado aparece con 7 lecciones; la práctica llega sin respuestas; se guarda la tarjeta 2 y se retoma en la tarjeta 2; la lección se completa |
| Evaluación (A1 = práctica) | Respuesta correcta e incorrecta **calificadas por el servidor** |
| Fichas | La lección 2.p tiene las 5 fichas congeladas; la pantalla de fichas muestra 5 modelos |
| Seguimiento | Carolina ve a Alumna Prueba 1: tienda Amsterdam 264, 1/7 lecciones, práctica 1/2 |
| Bloqueo | Con el curso publicado, Alumna 2 **sigue bloqueada** |
| Limpieza del factor | Factor TOTP temporal de Carolina demo **retirado** (0 factores) |

### 3.2 En la interfaz (vista previa, teléfono 390 × 844): 7/7 PASS

Capturas en `capturas/`:
- `u1_alumna2_bloqueada.png`: "Academy todavía no está abierta para vendedoras".
- `u2_alumna1_inicio.png`: curso, avance y "Continuar".
- `u4_leccion_ficha.png`: tarjeta de ficha con "Ficha validada v2 · 2026-10-08" y cuidados "pendiente de validación".
- `u5_fichas.png`: las 5 fichas.
- `u6_carolina_panel.png`: compuertas, versión publicada, avance por persona y tienda, historial con aal2.

Además: al recargar, retoma en la tarjeta 2, y Alumna 1 no entra al panel de contenido.

### 3.3 Hallazgos (no corregidos en esta ventana)

| # | Hallazgo | Impacto | Propuesta |
|---|---|---|---|
| H1 | **La foto del modelo no se mostró** en la tarjeta de ficha de la vista previa (recuadro vacío) | Visual; los datos sí se ven | Revisar si el Storage de staging tiene esa ruta (copia `sync_storage`) o si `imageUrl` necesita otro bucket. Antes del piloto |
| H2 | La barra inferior del menú general aparece **dentro de `/academy`** y tapa parte de la tarjeta | Usabilidad en el teléfono | Implementar lo del diseño §12.2: ocultar la barra del Shell en `/academy` y usar la barra propia de Academy |
| H3 | La barra inferior muestra "Centro de control" a una vendedora (comportamiento previo del Shell, no de Academy) | Confusión; esa página la niega igual | Fuera de Academy; señalarlo al responsable del Shell |
| H4 | Estado de la solicitud en inglés ("consumed", "approved") en el panel | Texto | Traducir los estados en la interfaz |
| H5 | El interruptor de Academy usa su propia función (`academyEnabled()`). Otra sesión informa que existe un patrón común en `admin-web/src/lib/feature.ts` (`intelEnabled()`) y que el despliegue del panel a producción ahora exige un commit revisado (`F360_DEPLOY_SHA`) | Consistencia | Alinear con `feature.ts` antes de integrar en `fuxia-360` |
| H6 | `vercel env run` de la CLI 63.1.2 interpretó los argumentos como un despliegue y **falló antes de publicar nada**. Se usó la alternativa documentada: el token temporal en una cabecera, sin imprimirlo | Ninguno (no se desplegó) | No usar `env run` en estos scripts |

## 4. Limpieza manual y comprobación

**Ejecutado** (13:00:05), en **una transacción**:
- fichas, roles y asignaciones de las 2 cuentas de prueba;
- filas `academy_*` de `approval_scopes` y sus operaciones;
- esquema `f360_academy` y las 15 RPC;
- registro de aprobaciones;
- CHECK de vuelta a `fx_rate, budget, close, store_discount`, en el orden original.

Después:
- borradas las 2 cuentas de prueba (200 / 200);
- borradas sus contraseñas de `~/.fuxia-staging.env` (0 líneas restantes);
- **vista previa eliminada** (0 despliegues con ese id).

**Comprobación final** (diagnóstico de solo lectura):

| Comparación | Resultado |
|---|---|
| Contra el inicio de la ventana (12:53) | **Idéntico** en los 16 indicadores |
| Contra el estado anterior al paso 1 (12:41) | **Idéntico** en los 16 indicadores |
| Esquema Academy · registro · RPC · migraciones `20261026*` registradas | no existe · no existe · 0 · 0 |
| Cuentas de prueba · roles de prueba · factores MFA de las cuentas demo | 0 · 0 · 0 |
| CHECK de `approval_scopes` · filas | `fx_rate, budget, close, store_discount` · close 2, budget 1, fx_rate 1 (sin cambios) |
| Huella de `f360.can_approve` | `565a9163…` (sin cambios) |

**Lo que sí queda, por diseño de las plataformas (sin datos de negocio):**
- **Registros de auditoría de Supabase Auth** (inicios de sesión, alta y baja de las 2 cuentas, alta y baja del factor TOTP temporal). Son registros internos de Auth que no se borran a mano; la copia nocturna de las 3:30 los reemplaza.
- **Contadores de secuencia** que avanzaron. No hay filas.
- **Registro de actividad en Vercel** del despliegue eliminado.

## 5. Estado

- **P0-6 sigue abierto** y bloquea el piloto con vendedoras reales.
- **No se inicia A2.** Siguiente paso a tu criterio:
  - corregir H1–H5 en la rama;
  - decidir cuándo y cómo integrar en `fuxia-360`;
  - remediación de P0-6.
