-- Rollback of 20261007000900_f360_d4_opening_load_links.sql. Refuses while legacy links exist (unlink first) or a
-- count is 'cargado' (its OPENING event stays in the ledger by design; reverting the schema would orphan the status).
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM f360.woo_variant_links WHERE origin = 'legacy_adopted') THEN RAISE EXCEPTION 'Hay vínculos legacy: usa f360_legacy_unlink_channel antes.'; END IF;
  IF EXISTS (SELECT 1 FROM f360.opening_counts WHERE status = 'cargado') THEN RAISE EXCEPTION 'Hay un saldo inicial cargado: no se revierte el esquema.'; END IF;
END $$;
DROP FUNCTION IF EXISTS public.f360_legacy_channel_state(text);
DROP FUNCTION IF EXISTS public.f360_legacy_link_products(text, uuid[], text);
DROP FUNCTION IF EXISTS public.f360_legacy_unlink_channel(text, text);
DROP FUNCTION IF EXISTS public.f360_legacy_link_channel(text);
DROP FUNCTION IF EXISTS public.f360_opening_load(uuid, uuid);
ALTER TABLE f360.opening_counts DROP COLUMN IF EXISTS load_event_id, DROP COLUMN IF EXISTS loaded_at, DROP COLUMN IF EXISTS loaded_by_name;
ALTER TABLE f360.opening_counts DROP CONSTRAINT opening_counts_status_check;
ALTER TABLE f360.opening_counts ADD CONSTRAINT opening_counts_status_check CHECK (status IN ('preliminar', 'congelado', 'aprobado', 'cancelado'));
DROP FUNCTION IF EXISTS public.f360_visibility_result(text, jsonb);
DROP FUNCTION IF EXISTS public.f360_visibility_claim(text);
DROP FUNCTION IF EXISTS public.f360_store_visibility_request(text, int, text, text);
DROP FUNCTION IF EXISTS f360.woo_visibility(uuid, int);
DROP TABLE IF EXISTS f360.woo_visibility_requests;
