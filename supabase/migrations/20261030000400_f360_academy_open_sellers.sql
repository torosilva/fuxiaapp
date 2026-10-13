-- Fuxia Academy · abre Sales Academy a las vendedoras reales (Mario 2026-10-13: "si sale", después de cerrar P0-6 en producción:
-- whatsapp-otp v77 + rotación de contraseñas, ver docs/fuxia360/security/D12_CIERRE_Y_P0-6_PRODUCCION.md).
-- Solo levanta la compuerta de acceso: una vendedora activa (f360.sellers.status = 'activa') ve los cursos PUBLICADOS.
-- Certificados, puntos y canjes siguen bloqueados por sus CHECK. Ningún curso se publica aquí: lo publica Carolina (2FA).
-- Rollback: supabase/rollbacks/20261030000400_f360_academy_open_sellers.down.sql
ALTER TABLE f360_academy.settings DROP CONSTRAINT a1_no_real_learners;
UPDATE f360_academy.settings
   SET learner_access_enabled = true,
       note = 'Vendedoras reales con acceso desde 2026-10-13 (P0-6 cerrado en producción). Certificados, puntos y canjes: bloqueados.'
 WHERE id;
