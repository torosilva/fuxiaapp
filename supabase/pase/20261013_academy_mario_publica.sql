-- Fuxia Academy · PRODUCCIÓN · Mario también puede publicar contenido ordinario de producto (academy_content.publish_sales).
-- Mario 2026-10-13: "no esperes que Carolina aprueba ya aprueba". Carolina no tiene 2FA configurado; Mario sí. Mario envía y
-- aprueba desde el admin (Academy → Contenido y aprobaciones) con su propio código 2FA; publish_sales permite autoaprobación y
-- queda marcada como tal en el registro. Carolina conserva su permiso. Políticas y retiros siguen pidiendo a otra persona.
-- Reversión: DELETE FROM f360.approval_scope_operations WHERE scope = 'academy_content' AND operation = 'publish_sales'
--            AND auth_user_id = (SELECT auth_user_id FROM f360.user_roles WHERE role = 'owner' AND display_name = 'Mario Silva');
BEGIN;
DO $$
DECLARE mario uuid := (SELECT auth_user_id FROM f360.user_roles WHERE role = 'owner' AND display_name = 'Mario Silva');
BEGIN
  IF mario IS NULL OR NOT EXISTS (SELECT 1 FROM f360.approval_scopes WHERE scope = 'academy_content' AND auth_user_id = mario) THEN
    RAISE EXCEPTION 'MARIO-PUBLICA PRE: Mario no es aprobador de academy_content'; END IF;
  IF EXISTS (SELECT 1 FROM f360.approval_scope_operations WHERE scope = 'academy_content' AND auth_user_id = mario AND operation = 'publish_sales') THEN
    RAISE EXCEPTION 'MARIO-PUBLICA PRE: ya tiene el permiso'; END IF;
  INSERT INTO f360.approval_scope_operations (scope, auth_user_id, operation, added_by_name)
  VALUES ('academy_content', mario, 'publish_sales', 'Mario (2026-10-13: "Carolina ya aprueba")');
  IF NOT f360.can_approve_op('academy_content', 'publish_sales', mario) THEN RAISE EXCEPTION 'MARIO-PUBLICA POST: el permiso no quedó'; END IF;
END $$;
COMMIT;
