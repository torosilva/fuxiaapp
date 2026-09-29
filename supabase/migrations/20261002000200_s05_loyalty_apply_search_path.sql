-- S0.5 fix — the EXISTING trigger function public.trg_update_purchase_stats (production, unchanged) references
-- `loyalty_cards` without a schema. Inside loyalty_apply (search_path pg_catalog, pg_temp) it failed with
-- "relation loyalty_cards does not exist". Found by the BEFORE/AFTER economics harness. pg_catalog stays first;
-- public is added so the existing triggers behave exactly as they do today. The trigger itself is not modified.
ALTER FUNCTION public.loyalty_apply(uuid, jsonb, numeric, text, text, text, text, jsonb, text) SET search_path = pg_catalog, public, pg_temp;
