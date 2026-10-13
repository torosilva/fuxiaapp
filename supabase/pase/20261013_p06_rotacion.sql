-- P0-6 · paso 4 en PRODUCCIÓN: cambia la contraseña de cada cuenta por teléfono ({dígitos}@fuxia.app) por una aleatoria que
-- nadie conoce ni se guarda. Así la contraseña derivada del teléfono (fuxia_{tel}_{OTP_SALT}) deja de abrir cuentas.
-- Nadie usa esas contraseñas: la app y el admin de producción entran solo por código de WhatsApp (whatsapp-otp v77, que
-- emite la sesión con un enlace de un solo uso); el inicio con contraseña del admin existe solo en staging. El 2FA no cambia.
-- No tiene reversión, a propósito: las contraseñas anteriores eran el hueco.
-- Lectura previa 2026-10-13: 56 cuentas, todas por teléfono y con bcrypt, 0 de laboratorio.
-- Correr: scripts/f360/prod_sql.sh supabase/pase/20261013_p06_rotacion.sql   (ensayo con ROLLBACK, luego aplica)
BEGIN;
DO $$
DECLARE n int; m int;
BEGIN
  CREATE TEMP TABLE p06_old ON COMMIT DROP AS
    SELECT id, encrypted_password FROM auth.users
    WHERE email ~ '^[0-9]{8,15}@fuxia[.]app$' AND email !~ '^1555010[0-9]{4}@';   -- laboratorio fuera
  SELECT count(*) INTO n FROM p06_old;
  IF n < 1 OR n > 100 THEN RAISE EXCEPTION 'P0-6 rotación: % cuentas, fuera de lo esperado (1–100); no se cambia nada', n; END IF;

  UPDATE auth.users u
     SET encrypted_password = extensions.crypt(encode(extensions.gen_random_bytes(32), 'base64'), extensions.gen_salt('bf', 10)),
         updated_at = now()
    FROM p06_old o WHERE u.id = o.id;
  GET DIAGNOSTICS m = ROW_COUNT;
  IF m <> n THEN RAISE EXCEPTION 'P0-6 rotación: % de % cuentas cambiadas', m, n; END IF;
  IF EXISTS (SELECT 1 FROM auth.users u JOIN p06_old o USING (id)
             WHERE u.encrypted_password IS NOT DISTINCT FROM o.encrypted_password OR u.encrypted_password NOT LIKE '$2%') THEN
    RAISE EXCEPTION 'P0-6 rotación: alguna cuenta quedó con la contraseña anterior o sin bcrypt';
  END IF;
  RAISE NOTICE 'P0-6 ROTACIÓN OK · % cuentas', n;
END $$;
COMMIT;
