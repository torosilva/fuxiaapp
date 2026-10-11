-- PASE · activar Meta Ads como fuente configurada, SOLO después de que f360-meta-spend cargó el historial (mayo → ayer).
-- Aborta si no hay gasto de Meta por API o si la última lectura falló.
BEGIN;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM f360.marketing_spend_imports WHERE platform = 'meta' AND source = 'api' AND status = 'accepted' AND date_from <= DATE '2026-05-01') THEN
    RAISE EXCEPTION 'ABORT: el historial de Meta (desde 2026-05-01) no está cargado';
  END IF;
  IF (SELECT ok FROM f360.measurement_runs WHERE source_key = 'meta_ads' ORDER BY id DESC LIMIT 1) IS NOT TRUE THEN RAISE EXCEPTION 'ABORT: la última lectura de Meta falló'; END IF;
END $$;
UPDATE f360.measurement_sources SET config_status = 'CONFIGURED',
  notes = 'Mario 2026-10-11: API de solo lectura (ads_read, usuario del sistema fuxia360-lectura, cuenta act_966161362834783); historial desde 2026-05-01; lectura diaria 02:30 CDMX.',
  updated_by_name = 'pase 20261011_meta_gasto_api_activar', updated_at = now()
  WHERE key = 'meta_ads' AND spend_expected IS TRUE;
DO $$ BEGIN
  IF (SELECT config_status FROM f360.measurement_sources WHERE key = 'meta_ads') <> 'CONFIGURED' THEN RAISE EXCEPTION 'ABORT: meta_ads no quedó configurada'; END IF;
END $$;
COMMIT;
