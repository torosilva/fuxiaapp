# Growth P0 · Instagram orgánico, registro de experimentos y Clarity diario

**Fecha:** 2026-10-27. **Pedido:** Mario ("no quiero otro módulo… quiero terminar el Growth que ya construimos"), con autorización **solo para staging**.
**Estado:** STG. Producción sin tocar, campañas de Meta sin tocar, nada publicado en Instagram.

## 0. Reconciliación: ¿9 o 16 de 20 ventas de Instagram?

Las dos cifras salen de las mismas 20 ventas pagadas de México del **23 de julio al 2 de agosto**. Cada venta se clasifica por su último clic, según la atribución de WooCommerce (`f360.commerce_woo_attribution`). Las cifras miden cosas distintas:

| Último clic | Ventas | Pedidos |
|---|---|---|
| Instagram sin anuncio (bio, historias, publicaciones) | **9** | 2379, 2490, 2491, 2517, 2539, 2627, 2628, 2632, 2636 |
| Facebook sin anuncio | 1 | 2542 |
| Google orgánico | 3 | 2493, 2552, 2616 |
| Directo | 3 | 2540, 2541, 2588 |
| Anuncio de Meta | 4 | 2538, 2543, 2546, 2573 |
| **Total** | **20** | |

- **9 de 20** es Instagram solo.
- **16 de 20** suma todo lo que no fue anuncio: Instagram, Facebook, Google y directo.
- El error fue mío: el 27 de octubre escribí que "16 de las 20 ventas llegaron de Instagram orgánico". No es así. La cifra correcta es **9 por Instagram**, o 10 si se suma Facebook.
- La pestaña Instagram reproduce las 9 y la prueba G4b lo comprueba.
- Advertencia: es último clic. Si una clienta vio un anuncio y luego entró directo, la venta cuenta como "directo".

## 1. Qué existía y qué se reutilizó

| Existía | Cómo se usa ahora |
|---|---|
| Growth (War Room, Campañas, Medición, Plan, Conciliación) | Se agregan dos pestañas: **Instagram** y **Experimentos**. Nada existente cambia |
| `f360.measurement_sources` / `measurement_runs` | Dos fuentes nuevas, `instagram` y `clarity`. Su salud aparece sola en **Medición** por el tramo genérico de APIs que ya existía |
| `f360.commerce_orders` + `commerce_woo_attribution` + `classify_channel_v1` | Única evidencia de ventas. "Instagram sin anuncio" = las categorías existentes, filtradas solo a Instagram |
| `f360.marketing_spend_daily` (gasto de Meta por API) | Gasto de las campañas de cada experimento |
| `f360.require_role`, RPC con `SECURITY DEFINER` y tablas sin acceso directo | Mismo modelo: leen dueño y operador; aprueba y da veredicto solo el dueño |
| Patrón de `f360-meta-spend` (handler, secreto del programador, registro de fallas) | Mismo patrón en `f360-instagram` y `f360-clarity`, con el mismo `f360_sync_secret` del vault y `pg_cron` |
| Diseño `06_EXPERIMENTS.md` | Implementado tal cual: tabla, bitácora, estados y seguridad (§4 abajo) |
| `lib/feature.ts` | `growthP0Enabled()`: las pestañas solo se ven en staging hasta el pase |

**No se duplicó nada.** No hay una plataforma nueva, un servicio de pago ni un tablero aparte.

## 2. Qué se construyó (staging)

| Pieza | Archivo |
|---|---|
| Migración Instagram + Clarity | `supabase/migrations/20261104000100_f360_growth_instagram_clarity.sql` |
| Migración de experimentos | `supabase/migrations/20261104000200_f360_growth_experiments.sql` |
| Reversiones | `supabase/rollbacks/20261104000100…down.sql`, `…0200…down.sql` |
| Función `f360-instagram` | `fuxia-native/supabase/functions/f360-instagram/`. Corre diario (cuenta + publicaciones de 60 días), cada 4 h (historias) y en relleno (hasta 120 días por llamada) |
| Función `f360-clarity` | `fuxia-native/supabase/functions/f360-clarity/`. Corre diario: últimas 24 h por fuente, dispositivo y URL |
| Pantallas | `admin-web/src/app/(app)/growth/Instagram.tsx`, `Experimentos.tsx`, `ExperimentForms.tsx`, `experimentos-actions.ts`, `lib/growth-p0.ts` |
| Captura local (puente hasta el pase) | `scripts/f360/staging_growth_p0_capture.mjs`, `clarity_capture_launcher.sh`, `com.fuxia360.clarity-captura.plist` |
| Pruebas | `supabase/staging/test_growth_p0.sql` (40), `f360-instagram/ig.test.ts` (8), `f360-clarity/clarity.test.ts` (6), `admin-web/e2e/growth-p0.spec.ts` |

Las migraciones son las siguientes libres: no había ninguna pendiente de otra sesión ni de otra rama.

### Decisiones que el diseño dejaba abiertas (marcadas en la migración)

1. **Lo que se fija antes de empezar.** Hipótesis, responsable, presupuesto, KPI, metas, mercado, campañas y fechas quedan **congelados desde APROBADO**. El diseño solo congelaba los umbrales, y desde CORRIENDO.
2. **Quién propuso y quién ejecuta.** Cada experimento guarda las dos cosas: Mario, Carolina, Goyo, agencia, IA u otro. Con eso sale el **récord por persona**.
3. **KPIs que se pueden medir hoy.** Solo con ventas pagadas y gasto de Meta: ventas pagadas, venta en dinero y costo por venta. Los demás del §5 (favoritos, carritos) se rechazan hasta que exista el dato.
4. **El veredicto no es libre.**
   - GANÓ solo si cumplió la meta con la muestra mínima.
   - PERDIÓ solo si llegó al criterio para cancelar.
   - Cualquier otro caso es SIN CONCLUSIÓN.
   - El servidor calcula el resultado al cerrar y lo guarda como foto.
5. **Evidencia etiquetada.**
   - Si el experimento tiene campañas, cuenta las ventas cuyo último clic fue esa campaña: es **atribución observada**.
   - Si no tiene campañas, compara el mercado antes y después.
   - Nunca se presenta como "causal": no hay grupo de control.
6. **Ventana medida.** Va de la fecha de inicio a la de revisión fijada, o al día en que se detuvo. Cerrar tarde no estira la ventana.

## 3. Qué datos reales se pueden recuperar

| Fuente | Hoy | Qué hace falta |
|---|---|---|
| **Instagram orgánico** | **Nada.** El token actual (`fuxia360-lectura`) solo tiene permisos de anuncios. La cuenta de Instagram responde "missing permissions" (código 100) en 6 llamadas distintas, verificado el 27 de octubre. La falla queda registrada en staging y la pestaña lo dice | En Business Manager, asignar la cuenta de Instagram (y su página) al usuario del sistema y dar `instagram_basic` + `instagram_manage_insights`. Es decisión de Mario: no lo pedí a nadie |
| Instagram, cuando haya permiso | — | Lo siguiente sale de la documentación de Meta y **no está verificado** hasta tener permiso; la función registra hasta dónde responde la API:<br>• todas las publicaciones y reels de la historia, con su métrica acumulada a hoy;<br>• alcance, vistas, visitas al perfil, clics al sitio, interacciones y seguidos/dejados de seguir por día;<br>• historias solo desde el día en que se empiece a capturar;<br>• seguidores solo desde ese día |
| **Ventas desde Instagram** | **Sí, desde junio.** Salen de WooCommerce y no dependen del permiso | Ligar una venta a una publicación solo es posible si el enlace trae `utm_content` con el id de la publicación. Hoy ninguno lo trae |
| **Clarity** | **Sí, desde hoy.** Primera captura real: 27 métricas (fuente, dispositivo y URL) | Confirmado: la API **solo da 1 a 3 días**. Con `numOfDays=4` y con 30 responde HTTP 400, y no acepta fechas. **Lo anterior al 25 de octubre no se puede recuperar** |

## 4. Qué sigue faltando

- **Datos de Instagram:** dependen del permiso.
- **Embudo diario de GA4 con historial:** visitas, producto, carrito, checkout. No estaba en este pedido.
- **Pantalla de Clarity:** fuera del alcance, por pedido de Mario. Solo se guarda.
- **Precio y cupón por venta en Growth.**
- **Las 3 pruebas viejas de Growth fallan por causas anteriores, ajenas a esto:**
  - `test_sg0_measurement` y `test_sg0_reconciliation` buscan clientas demo que ya no existen desde que staging copia producción;
  - `test_sg1_cockpit` (C4) espera que no haya gasto de Meta y ahora sí lo hay.
  - Hay que actualizarlas; no las toqué.

## 5. Pruebas y resultados

| Prueba | Resultado |
|---|---|
| Base de datos, `test_growth_p0.sql`: permisos, importaciones, julio = 9, reglas de experimentos, bitácora inmutable | **40/40.** En el camino encontró 2 errores reales, corregidos: se podía archivar sin decisión, y la ventana se estiraba al cerrar tarde |
| Función Instagram (`ig.test.ts`): tipos de contenido, métricas sin inventar ceros, sin token no llama a Meta, el token nunca aparece en errores | **8/8** |
| Función Clarity (`clarity.test.ts`): 3 llamadas, limpieza de URLs, sin token no gasta llamadas | **6/6** |
| Programador → función en staging | Las dos responden 503 "no está configurado" sin gastar llamadas |
| API real de Instagram con el token actual | Falla por permisos (esperado). Registrado en Medición y en la pestaña |
| API real de Clarity | Captura OK y 27 métricas en staging. **Privacidad:** traía 2 llaves de pedido (`key=wc_order…`) y unos 186 identificadores de clic. Ahora se guardan solo la ruta y los utm, verificado con 0 en archivos y en staging |
| Reversión de las 2 migraciones | Ensayada en una transacción revertida: quedan 0 tablas nuevas y las 8 fuentes originales |
| Pantallas (Playwright, staging, Mario demo): pestañas existentes intactas, Instagram (no conectado, 9 ventas de julio), experimento de punta a punta, teléfono sin scroll horizontal | **2/2.** Encontró 2 fallas, corregidas: el formulario importaba código de servidor, y la tabla de récord se salía en el teléfono |
| `tsc` + `eslint` | Limpios |

### 5.1 Pantallas
Capturas en `admin-web/e2e-screenshots/growth-p0/`. La prueba del experimento intenta cerrar como "ganó" sin cumplir la meta y la pantalla lo rechaza con el motivo. Esa prueba deja en staging experimentos llamados "Prueba e2e", que no se pueden borrar; la copia nocturna los quita.

## 6. Costos incrementales estimados

- **Dinero: $0.** Las APIs de Instagram y de Clarity son gratuitas. No se contrata nada.
- **Supabase:** unas 8 invocaciones de funciones al día (1 de Instagram diaria, 6 de historias y 1 de Clarity). Es despreciable dentro del plan.
- **Almacenamiento:**
  - Clarity por URL pesa alrededor de 1 MB al día, unos 30 MB al mes. Si hiciera falta, se recorta a las 500 URLs principales.
  - Instagram pesa unos KB al día.
- **Cuota de Clarity:** 3 de las 10 llamadas diarias. Quedan 7 para preguntas manuales.

## 7. Riesgos de seguridad y privacidad

- **Tokens:** viven solo como secretos de las funciones. Staging no tiene ninguno a propósito. Los errores nunca muestran el token; hay pruebas que lo verifican.
- **Datos personales:**
  - Instagram: solo contenido de la marca y cifras agregadas, sin datos de seguidoras.
  - Clarity: agregados, y las URLs se limpian (sin llaves de pedido, sin fbclid ni gclid, sin correos en parámetros).
  - Ventas: cuenta y mercado, sin nombres.
- **Permisos:**
  - Tablas sin acceso directo para `anon` ni `authenticated`.
  - Importar es solo para `service_role`.
  - Leer es para operador o dueño.
  - Aprobar y dar veredicto es solo para el dueño.
  - La identidad sale de la sesión, nunca del formulario (prueba G6d).
- **Integridad:**
  - La bitácora no se edita ni se borra, y un experimento no se borra (pruebas G8d y G8e).
  - Las metas no se mueven después de aprobadas (prueba G6g).
- **Token de Meta con escritura:** sigue siendo el mismo, y la función de Instagram solo hace lecturas (GET). Si se le agregan los permisos de Instagram al mismo usuario del sistema, ese token ve más. Alternativa: un token propio para Instagram (`INSTAGRAM_TOKEN`, que la función ya acepta).

## 8. Plan de despliegue y reversión (cuando Mario lo autorice)

1. **Migraciones a producción:** archivo de pase con candados (`supabase/pase/…`) por `scripts/f360/prod_sql.sh`, primero en seco. Incluye las dos migraciones tal cual, más la fila de `schema_migrations`.
2. **Funciones:** agregar `f360-instagram` y `f360-clarity` a la lista de `deploy_prod_function.sh` y desplegar.
3. **Secretos en producción:** `CLARITY_API_TOKEN`. Para Instagram, `INSTAGRAM_TOKEN` cuando exista el permiso; sin él, la función responde "no configurado" y no hace nada.
4. **Historial de Clarity:** importar `~/fuxia360-respaldos/clarity/*` a producción. Después **desinstalar** la captura local para no gastar llamadas dos veces:
   `launchctl bootout gui/$(id -u)/com.fuxia360.clarity-captura`
5. **Pantallas:** `NEXT_PUBLIC_F360_GROWTH_P0=on` en el build de producción y `deploy_prod_admin.sh` con el sha fijo.
6. **Verificación:** las pruebas de §5 contra producción en lectura, y Medición mostrando las dos fuentes.
7. **Reversión:**
   - los dos archivos de `supabase/rollbacks/`, primero 0200 y luego 0100;
   - quitar la variable y volver a publicar el admin.
   - **Se pierde el historial capturado:** Clarity no se puede volver a leer. Hay que exportarlo antes.

## 9. Captura local de Clarity mientras tanto (staging)

La copia nocturna prod → staging (3:30) **borra** las tablas de staging cada noche. Para no perder días, `com.fuxia360.clarity-captura` (launchd, 6:30) hace dos cosas:
- guarda la respuesta del día, ya limpia, en `~/fuxia360-respaldos/clarity/<día>/`;
- reimporta todos los días guardados a staging.

**Estado: INSTALADA por Mario el 27 oct** (corre diario a las 6:30; log en `~/fuxia360-respaldos/clarity/launchd.log`). Comando con que se instaló:

```
! install -m 700 scripts/f360/clarity_capture_launcher.sh ~/.fuxia360/clarity-captura.sh && cp scripts/f360/com.fuxia360.clarity-captura.plist ~/Library/LaunchAgents/ && launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.fuxia360.clarity-captura.plist
```

Sin ella, Clarity solo se guarda cuando alguien corre `scripts/s00a/run.sh ../f360/staging_growth_p0_capture.mjs clarity` (el del 27 oct ya está guardado). Cada día sin capturar se pierde. Desinstalar: ver `scripts/f360/clarity_capture_launcher.sh`.
