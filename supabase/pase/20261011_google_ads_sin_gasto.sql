-- PASE · Google Ads: sin gasto (Mario 2026-10-11, en el chat: "¿Hay gasto en Google Ads?" → "NO").
-- Sets ONLY measurement_sources.google_ads.spend_expected = false (the same field f360_measurement_source_set writes), so the
-- marketing_spend source stops reporting "platforms_with_unknown_spend:google". No spend rows are loaded; config_status stays as is.
-- Note: Google Analytics shows an UNLINKED Google Ads account (951-639-9227). If it ever spends, set spend_expected back to true
-- (or NULL) and load its spend; this pase does not hide that account.
-- Rollback: UPDATE f360.measurement_sources SET spend_expected = NULL WHERE key = 'google_ads';
BEGIN;

DO $$ BEGIN
  IF (SELECT spend_expected FROM f360.measurement_sources WHERE key = 'google_ads') IS NOT NULL THEN RAISE EXCEPTION 'ABORT: google_ads ya tiene respuesta'; END IF;
END $$;

UPDATE f360.measurement_sources
   SET spend_expected = false,
       notes = 'Sin gasto en Google Ads (Mario 2026-10-11). Cuenta 951-639-9227 existe sin vincular a GA4; si gasta, volver a marcar.',
       updated_by_name = 'Mario Silva (pase)', updated_at = now()
 WHERE key = 'google_ads';

DO $$ BEGIN
  IF (SELECT spend_expected FROM f360.measurement_sources WHERE key = 'google_ads') IS DISTINCT FROM false THEN RAISE EXCEPTION 'ABORT: no quedó'; END IF;
  IF EXISTS (SELECT 1 FROM f360.marketing_spend_daily WHERE platform = 'google') THEN RAISE EXCEPTION 'ABORT: hay gasto de Google cargado'; END IF;
END $$;
COMMIT;
