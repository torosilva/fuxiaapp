-- Fuxia 360 · PRODUCCIÓN · Growth P0: primer relleno de Instagram orgánico (token con instagram_basic + instagram_manage_insights,
-- generado por Mario el 2026-10-28). Pide a f360-instagram el historial desde el 30 jun (máximo 120 días por llamada); la función
-- guarda solo lo que la API devuelve. Solo lectura de Instagram; escribe en ig_* y measurement_runs.
-- 2do intento tras corregir la llamada de la cuenta (el 1ro falló con HTTP 500 de Meta).
BEGIN;
SELECT f360.growth_source_tick('f360-instagram', '{"action":"backfill","from":"2026-06-30"}'::jsonb);
COMMIT;
