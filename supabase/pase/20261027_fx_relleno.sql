-- Fuxia 360 · PRODUCCIÓN · I5 paso 1b: relleno del tipo de cambio oficial desde 2026-05-01 (después de 20261027_fx_diario.sql y de
-- publicar f360-fx-rates). Mismo mecanismo que el cron diario (Vault f360_sync_url / f360_sync_secret). Asíncrono (pg_net): el POST
-- sale al hacer COMMIT. Solo escribe f360.fx_observations (append-only). No aprueba nada.
BEGIN;
DO $$
DECLARE v_url text; v_secret text;
BEGIN
  SELECT regexp_replace(decrypted_secret, '/functions/v1/[^/]+$', '/functions/v1/f360-fx-rates') INTO v_url FROM vault.decrypted_secrets WHERE name = 'f360_sync_url';
  SELECT decrypted_secret INTO v_secret FROM vault.decrypted_secrets WHERE name = 'f360_sync_secret';
  IF v_url IS NULL OR v_secret IS NULL OR v_url !~ '/functions/v1/f360-fx-rates$' OR v_url !~ 'tgzgiwfzddsghnxgkcqd' THEN
    RAISE EXCEPTION 'ABORT: no es producción o faltan los secretos de Vault'; END IF;
  PERFORM net.http_post(url := v_url, headers := jsonb_build_object('Authorization', 'Bearer ' || v_secret, 'Content-Type', 'application/json'),
    body := '{"action":"backfill","from":"2026-05-01"}'::jsonb, timeout_milliseconds := 120000);
END $$;
COMMIT;
