-- Fuxia 360 · S-G0 · MARKETING SPEND SOURCE STATE (Mario 2026-10-08, pre-production decision 5). CONFIGURATION ONLY.
--   · Meta Ads: Fuxia DOES spend on Meta (spend_expected = true) but there is NO reliable integrated source yet →
--     config_status stays NOT_CONFIGURED until a valid CSV is loaded (f360_marketing_spend_upload) or a read-only API exists.
--     Effect: marketing_spend health stays NOT_CONFIGURED (no rows) and MER / CAC / ROAS keep value NULL + DATA_INCOMPLETE
--     with "meta_ads_spend_days_missing" (never 0, never computed without Meta's spend).
--   · Google Ads: spend NOT CONFIRMED → spend_expected stays NULL (UNKNOWN), config NOT_CONFIGURED; never assumed $0
--     (efficiency KPIs report "unknown_if_google_ads_has_spend").
-- Values are set by key; nothing else in measurement_sources changes. Later changes go through f360_measurement_source_set
-- (owner) as before.
-- Rollback: supabase/rollbacks/20261016000400_f360_sg0_spend_sources_state.down.sql
UPDATE f360.measurement_sources
   SET spend_expected = true, config_status = 'NOT_CONFIGURED',
       notes = 'Mario 2026-10-08: hay gasto en Meta; sin fuente integrada confiable → NOT_CONFIGURED hasta CSV válido o API de solo lectura.',
       updated_by_name = 'migración 20261016000400 (decisión Mario 2026-10-08)', updated_at = now()
 WHERE key = 'meta_ads';
UPDATE f360.measurement_sources
   SET spend_expected = NULL, config_status = 'NOT_CONFIGURED',
       notes = 'Mario 2026-10-08: gasto en Google Ads NO confirmado → desconocido (nunca $0) hasta confirmarlo.',
       updated_by_name = 'migración 20261016000400 (decisión Mario 2026-10-08)', updated_at = now()
 WHERE key = 'google_ads';
DO $$ BEGIN
  IF (SELECT count(*) FROM f360.measurement_sources WHERE key IN ('meta_ads', 'google_ads')) <> 2 THEN
    RAISE EXCEPTION 'ABORT: measurement_sources rows meta_ads / google_ads missing (20261014000600 first).';
  END IF;
END $$;
