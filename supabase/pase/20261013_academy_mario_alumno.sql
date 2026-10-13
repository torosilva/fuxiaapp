-- Fuxia Academy · PRODUCCIÓN · Mario también entra como alumno (permiso 'tester') para ver Academy como una vendedora
-- (Mario 2026-10-13: "para ver como lo ve una vendedora"). Ve los cursos publicados, el botón al curso en Inicio, las lecciones y
-- la práctica; su avance aparece en "Avance por persona y tienda" como el de cualquier alumno. No cambia nada de nadie más.
-- Reversión: UPDATE f360_academy.grants SET active = false WHERE role = 'tester'
--            AND auth_user_id = (SELECT auth_user_id FROM f360.user_roles WHERE role = 'owner' AND display_name = 'Mario Silva');
BEGIN;
DO $$
DECLARE mario uuid := (SELECT auth_user_id FROM f360.user_roles WHERE role = 'owner' AND display_name = 'Mario Silva');
BEGIN
  IF mario IS NULL THEN RAISE EXCEPTION 'MARIO-ALUMNO PRE: falta Mario'; END IF;
  IF EXISTS (SELECT 1 FROM f360_academy.grants WHERE auth_user_id = mario AND role = 'tester') THEN RAISE EXCEPTION 'MARIO-ALUMNO PRE: ya es alumno'; END IF;
  INSERT INTO f360_academy.grants (auth_user_id, role, display_name, granted_by_name, evidence)
  VALUES (mario, 'tester', 'Mario', 'Mario (2026-10-13)', 'Ver Academy como vendedora');
  IF f360_academy.sales_access(mario) <> 'ok' THEN RAISE EXCEPTION 'MARIO-ALUMNO POST: sin acceso de alumno'; END IF;
END $$;
COMMIT;
