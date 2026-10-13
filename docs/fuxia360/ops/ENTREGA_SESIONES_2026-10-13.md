# Entrega de sesiones — 2026-10-13

> **Mario (2026-10-13):** "pasa todo a esta sesión y cierra las otras". Desde hoy, **una sola sesión** (seguridad, D12 y Centro de Inteligencia) lleva todo.
> Las sesiones fuxiaapp-2d (copia de staging) y fuxiaapp-d5 (Academy y P0-6) entregaron su estado y se detuvieron.
> **Producción no se tocó en ninguno de sus frentes.**

## 1. Copia nocturna de staging (antes, fuxiaapp-2d)
- **Programación:**
  - launchd `com.fuxia.staging-refresh` (`~/Library/LaunchAgents`), diario a las **3:30**, ejecuta `~/.fuxia360/staging-nightly.sh` (copia de `scripts/f360/staging_refresh/launcher.sh`).
  - El lanzador clona limpio `origin/fuxia-360` en `~/.fuxia360/staging-refresh-repo` y corre `nightly.sh`: primero `woo_refresh.sh --apply` (tienda real → staging4), luego `refresh.sh --apply --woo-mirrored` (o sin la bandera si Woo falla). Al final reaplica las migraciones y `after_refresh.list`.
- **Guía:** `docs/fuxia360/ops/STAGING_REFRESH.md`.
- **Registro:** `~/fuxia360-respaldos/staging-refresh/launchd.log`; cada corrida en `<ts>_apply/refresh.log`.
- **`after_refresh.list`:** `intel_approvers`, `intel_board_demo`, `intel_goal_300k`, `intel_fx_backfill`, `intel_fx_propose` y `scripts/f360/staging_demo_contadora.sql`.
- **Respaldos:**
  - Supabase en `~/fuxia360-respaldos/staging-refresh/<ts>` (7 días);
  - staging4 en el servidor `~/f360-backups/staging4-refresh/<ts>` (7 días);
  - restaurar: `RESTORE_FROM=<ts> woo_refresh.sh --apply`.
- **Respaldos de producción:** `~/fuxia-backups/` (`prod_data_2026-10-11.sql`, `storage_2026-10-11/`, 1.1 GB, modo 600).

**Riesgos abiertos:**
1. **La corrida del 14-oct a las 3:30 es la primera real** por launchd: las del 12 y 13 no corrieron (TCC; corregido en `bdb1ebf`). **Revisar `launchd.log` el 14-oct.**
2. La copia de Woo necesita la llave SSH de SiteGround cargada en el agente (`ssh-add -l` muestra "fuxia"). Si la Mac se reinicia sin cargarla, Woo falla (staging4 se restaura solo) y Supabase se copia sin `--woo-mirrored`.
3. La copia **no** vuelve a desplegar Edge Functions ni el admin de staging. La `whatsapp-otp` nueva (P0-6) se queda en staging.
4. Hilo no tiene staging: `f360-hilo.php` no se copia y la URL de Railway se reemplaza por `hilo.staging.invalid`.
5. El Mercado Pago de staging4 podría estar ligado a la cuenta real. **Confirmar el modo de prueba antes de probar pagos.**
6. **Seguridad (11-oct):** un `supabase db dump --dry-run` imprimió una contraseña temporal `cli_login_postgres` de **producción**. **Pendiente: que Mario confirme que revisó o eliminó ese rol.**

**Reglas:**
- Los scripts de reset, seed o refresh solo se corren con aprobación del comando exacto.
- El SSH al WordPress de producción lo corre Mario.

## 2. Academy A1 (antes, fuxiaapp-d5)
- **Rama `academy/a1` @ `5cd62cd`** (en origin, rebasada sobre `b78aa6e`).
- **Migraciones** `20261030000100_f360_approval_registry`, `0200_f360_academy_a1` y `0300_f360_academy_pilot_seed`, con sus rollbacks.
  - **No están aplicadas en ningún ambiente.**
  - **El ensayo no se ha vuelto a correr desde la renumeración.** El último fue 103/103 con los números `20261028`.
  - **No usar `20261030*` para otra cosa.**
- **Guarda:** el CHECK de `f360.approval_scopes` debe ser exactamente `{budget, close, fx_rate, store_discount}`; si no, la migración aborta a propósito.
- **Compuertas:** CHECK `NOT learner_access_enabled`; sin certificados, puntos ni canjes. Las 4 vendedoras reales quedan bloqueadas por diseño.
- **UI:** `/academy` con video de bienvenida (`admin-web/public/academy/bienvenida-720.mp4`, sha `586603c1…`). Se activa con `academyEnabled()` (`lib/feature.ts`): en staging, o con `NEXT_PUBLIC_F360_ACADEMY=on`.
- **Video:** fuentes en `tools/video/academy/`. Los MP4 de 1080 (`983026415c…`) y 720 (`586603c1…`) y la música están respaldados en `~/fuxia360-respaldos/academy-video/`.
- **Docs:** `docs/fuxia360/academy/a1/` (A1_REVISION, A1_ENSAYO_STAGING, A1_VENTANA_PRUEBAS, PAQUETE_CAROLINA_PILOTO no compartido, Q4_REVISION_FINAL). Q4 nunca se ejecutó.
- **Para abrirla a las vendedoras, en orden:**
  - (a) P0-6 en producción;
  - (b) integrar `academy/a1` en `fuxia-360`;
  - (c) dry-run y luego las migraciones en producción;
  - (d) una migración nueva que levante `learner_access_enabled`;
  - (e) permisos: Carolina aprobadora de `academy_content` y Mario admin;
  - (f) despliegue del panel con `F360_DEPLOY_SHA` revisado y `NEXT_PUBLIC_F360_ACADEMY=on`;
  - (g) Carolina publica el curso y el video con 2FA.
- **Pendientes:**
  - licencia de la música sin verificar;
  - aprobación de Carolina para el video, el curso piloto y P1–P5 (contradicciones de talla y cuidados 0/28);
  - foto de Mafalda Studs;
  - H3: el Shell muestra "Centro de control" a las vendedoras;
  - H6: no usar `vercel env run`;
  - A2 no iniciado.

## 3. P0-6 · inicio de sesión por WhatsApp (antes, fuxiaapp-d5) — **RIESGO ALTO ABIERTO EN PRODUCCIÓN**
- **Rama `security/p0-6` @ `d87938a`** (en origin). Plan en `docs/fuxia360/security/P0-6_REMEDIACION.md`.
- **En producción hoy:**
  - el **código fijo de revisión** abre la sesión de cualquier cuenta;
  - la **contraseña derivada del teléfono** abre la cuenta.
- **La `whatsapp-otp` nueva está desplegada SOLO en staging** (`verify_jwt` true). Pruebas: 15/15 (`p06_security_tests.mjs`) y 6/6 de rotación.
- **Falta para producción** (cada paso con autorización):
  - (a) Mario confirma que no hay una versión en revisión en las tiendas de apps;
  - (b) desplegar `whatsapp-otp` en producción con un comando aparte (`deploy_prod_function.sh` la excluye a propósito);
  - (c) rotar las contraseñas de las cuentas por teléfono con `p06_rotate_passwords.mjs --apply` (el dry-run en staging dio 45 cuentas);
  - (d) coordinar con D12 (políticas con `user_metadata.phone`: fase A ya aplicada; el cierre de la entrada vieja quita las dos que quedan).
- **Revertir en staging:** redeploy de `whatsapp-otp` desde `fuxia-native/supabase/functions/whatsapp-otp`. No se recomienda: la vieja tiene la llave maestra.
- **La entrada de revisión** solo funciona con `REVIEW_BYPASS_ENABLED='true'` y valores explícitos.

## 4. Preguntas de Mario que quedaron abiertas en esas sesiones
1. ¿Se despliega P0-6 en producción? (Mario ya dijo "hay que hacer el P0-6", pero no dio el sí explícito al despliegue.)
2. ¿Se abre Academy a las 4 vendedoras, después de P0-6? (Mario: "ya a produccion paa tomar cursos".)
