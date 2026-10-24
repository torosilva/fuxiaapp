-- Fuxia 360 · PRODUCCIÓN · relleno de Meta (Mario 2026-10-24: "si"): vuelve a leer de Meta los últimos 90 días con la función
-- f360-meta-spend YA ACTUALIZADA (gasto + "Meta dice"). Llena también el hueco de gasto del 11 al 13 de octubre (Meta respondía
-- "API access blocked"). La lectura nueva gana por ser la importación más reciente; las viejas quedan como historial (append-only).
-- Va DESPUÉS de supabase/pase/20261024_meta_dice.sql y de scripts/f360/deploy_prod_function.sh f360-meta-spend.
-- Igual que el cron diario (f360.meta_spend_tick): un POST con el mismo secreto del vault; el resultado queda en f360.measurement_runs.
-- Solo lectura en Meta. Reversión: no aplica (si algo sale mal, la lectura diaria de las 02:30 vuelve a escribir los últimos 7 días).
BEGIN;
DO $$
DECLARE v_url text; v_secret text; d_to date := (now() AT TIME ZONE 'America/Mexico_City')::date - 1;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version = '20261102000100') THEN
    RAISE EXCEPTION 'RELLENO PRE: primero supabase/pase/20261024_meta_dice.sql'; END IF;
  SELECT regexp_replace(decrypted_secret, '/functions/v1/[^/]+$', '/functions/v1/f360-meta-spend') INTO v_url FROM vault.decrypted_secrets WHERE name = 'f360_sync_url';
  SELECT decrypted_secret INTO v_secret FROM vault.decrypted_secrets WHERE name = 'f360_sync_secret';
  IF v_url IS NULL OR v_secret IS NULL OR v_url !~ '/functions/v1/f360-meta-spend$' THEN RAISE EXCEPTION 'RELLENO PRE: falta la URL o el secreto en el vault'; END IF;
  PERFORM net.http_post(url := v_url,
    headers := jsonb_build_object('Authorization', 'Bearer ' || v_secret, 'Content-Type', 'application/json'),
    body := jsonb_build_object('action', 'backfill', 'from', d_to - 89, 'to', d_to), timeout_milliseconds := 120000);
END $$;
COMMIT;
