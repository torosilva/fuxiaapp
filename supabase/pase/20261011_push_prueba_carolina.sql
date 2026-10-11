-- PASE · una notificación de PRUEBA a Carolina para verificar las push de producción de punta a punta (Mario 2026-10-11:
-- "configuralas"). Solo encola un aviso en f360.push_outbox; f360.push_tick() lo manda a f360-push tras confirmar.
BEGIN;
INSERT INTO f360.push_outbox (auth_user_id, title, body, data)
  VALUES ('31da6b13-70eb-4d89-8019-6f04c3207300', 'Fuxia 360 · prueba', 'Así te van a llegar los descuentos por aprobar. No tienes que hacer nada.',
          '{"type":"f360_test"}'::jsonb);
SELECT f360.push_tick();
COMMIT;
