-- Rollback of 20261030000400: vuelve a bloquear a las vendedoras reales (los testers siguen entrando).
UPDATE f360_academy.settings
   SET learner_access_enabled = false,
       note = 'A1: acceso real de vendedoras bloqueado mientras P0-6 siga abierto (Mario 2026-10-11).'
 WHERE id;
ALTER TABLE f360_academy.settings ADD CONSTRAINT a1_no_real_learners CHECK (NOT learner_access_enabled);
