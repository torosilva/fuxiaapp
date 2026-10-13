# D12 cierre de la entrada vieja y P0-6 · producción · 2026-10-13

Todo lo corrió Mario con `!`; lo verifiqué con lecturas.

| Paso | Qué | Verificación |
|---|---|---|
| P0-6 función | `whatsapp-otp` v76 → v77 (código de `security/p0-6`, integrada en `ca23d6e`), `verify_jwt` true | Prueba de humo: código fijo de revisión → 401 sin sesión; código equivocado → 401 sin `debug`; acción inválida → 400. Respaldo de v76: `~/fuxia-backups/whatsapp-otp_prod_v76_2026-10-13/` (idéntica al repo antes de P0-6) |
| P0-6 rotación | `supabase/pase/20261013_p06_rotacion.sql@0239571` | 56/56 cuentas por teléfono con bcrypt nuevo. Sin reversión (a propósito) |
| D12 cierre | `supabase/pase/20261013_d12_cierre.sql@40384fe` (migración `20261029000200`) | Huella de políticas `f5dfca99… 25` → `3bd28e95… 17` (igual a staging); permisos anon `35 → 0`; fila en `schema_migrations`; lista de tiendas sigue abierta; 5 tiendas y 45 ventas sin cambio |

**Reversión del cierre:** `supabase/pase/20261013_d12_cierre_reversion.sql` (ensayada en staging).

**Efecto:** la pantalla vieja de NIP responde "PIN incorrecto". Guadalajara y Contreras venden con cuentas F360 cuando Carolina dé de alta a sus vendedoras.

**Pendientes de P0-6:**
- notas de revisión de tiendas de apps: la entrada de revisión solo se abre con `REVIEW_BYPASS_ENABLED='true'` y sus valores;
- borrar el secreto `OTP_SALT`;
- cuenta demo sin privilegios.

## Academy en producción · 2026-10-13
- **Base de datos:** se corrió `supabase/pase/20261013_academy.sql@e45645e`. Quedaron 4 migraciones `20261030*` y las compuertas así: vendedoras activas pueden entrar; certificados, puntos y canjes apagados.
- **Permisos:** Carolina editora y Mario admin y editor; 5 operaciones de `academy_content`. Los 2 cursos quedaron en borrador.
- **Admin:** `NEXT_PUBLIC_F360_ACADEMY=on` en Vercel `fuxia360`, solo en Production. Se publicó desde `e45645e`, que solo trae las pantallas de Academy.
  - Ojo: `admin-web/.vercel` apunta a **fuxia360-staging**.
- **Falta, a cargo de Carolina:** revisar y publicar el curso y el video, con 2FA. Antes tiene que aprobar las contradicciones de talla y cuidados, la foto de Mafalda Studs y la licencia de la música.
- **Reversión:** `supabase/pase/20261013_academy_reversion.sql`. Desmonta Academy y borra el avance.
