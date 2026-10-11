-- PASE · pide a f360-meta-spend el historial de Meta (2026-05-01 → ayer CDMX), una sola vez. Solo encola UNA llamada pg_net
-- (se envía al confirmar); la función lee Meta (ads_read) y escribe por public.f360_marketing_spend_api_import.
-- Mismo canal que f360-commerce-poll: URL y Bearer desde el vault (f360_sync_url / f360_sync_secret); nada sale del servidor.
-- Requiere: pase 20261011_meta_gasto_api aplicado y f360-meta-spend desplegada. Repetirlo es inofensivo (importaciones idempotentes).
BEGIN;
DO $$
DECLARE v_url text; v_secret text; v_to date := (now() AT TIME ZONE 'America/Mexico_City')::date - 1;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version = '20261023000100') THEN RAISE EXCEPTION 'ABORT: falta el pase 20261011_meta_gasto_api'; END IF;
  SELECT regexp_replace(decrypted_secret, '/functions/v1/[^/]+$', '/functions/v1/f360-meta-spend') INTO v_url FROM vault.decrypted_secrets WHERE name = 'f360_sync_url';
  SELECT decrypted_secret INTO v_secret FROM vault.decrypted_secrets WHERE name = 'f360_sync_secret';
  IF v_url IS NULL OR v_secret IS NULL OR v_url !~ '/functions/v1/f360-meta-spend$' THEN RAISE EXCEPTION 'ABORT: vault f360_sync_url / f360_sync_secret'; END IF;
  PERFORM net.http_post(url := v_url,
    headers := jsonb_build_object('Authorization', 'Bearer ' || v_secret, 'Content-Type', 'application/json'),
    body := jsonb_build_object('action', 'backfill', 'from', '2026-05-01', 'to', v_to), timeout_milliseconds := 120000);
END $$;
COMMIT;
