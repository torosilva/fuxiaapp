-- Fuxia 360 — CRO-5a · Guard de inventario certificado para escasez (STAGING). Decisión: Mario 2026-10-04 (D-CRO-01).
-- No quantitative scarcity ("último par", "quedan 2", "quedan X") unless the stock behind the online ATS is CERTIFIED.
-- Certification is DERIVED from operational evidence — never a flag someone can switch on:
--
--   A size (variant) is certified at a location when the location has its one-and-only OPENING_PHYSICAL_COUNT event
--   (append-only, unique per location, f360.inventory_events) and:
--     (a) the event came from a completed store cutover (business_reference_type 'location_cutover': the whole location
--         was counted with double control) → every size of that location; or
--     (b) the event came from a loaded opening count (business_reference_type 'opening_count', opening_counts 'cargado')
--         → the sizes that were IN SCOPE of that count, plus sizes created after the load (their stock was born recorded).
--         A size that existed but was out of scope (its homologation was reopened during the count) is NOT certified.
--
--   The online ATS of a size is reliable for scarcity only when EVERY eligible location of f360.online_ats is certified
--   for it: the target's fulfillment location (Bodega CDMX) and every online store (f360.online_store_locations()).
--   All of them — not only those holding pairs today: an uncertified "0" is just as unverified as an uncertified "2".
--   One uncertified eligible location ⇒ inventory_reliable_for_scarcity = false.
--
-- Read-only helpers. Nothing here changes online_ats, the Woo sync, orders, make_to_order or Gold.
-- Rollback: supabase/rollbacks/20261007002400_f360_scarcity_guard.down.sql

CREATE FUNCTION f360.variant_inventory_certified(p_variant uuid, p_location uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT EXISTS (
      SELECT 1 FROM f360.inventory_events e
      WHERE e.event_type = 'OPENING_PHYSICAL_COUNT' AND e.business_reference_id = p_location::text
        AND e.business_reference_type = 'location_cutover')
    OR EXISTS (
      SELECT 1 FROM f360.opening_counts c JOIN f360.inventory_events e ON e.id = c.load_event_id AND e.event_type = 'OPENING_PHYSICAL_COUNT'
      WHERE c.location_id = p_location AND c.status = 'cargado'
        AND (EXISTS (SELECT 1 FROM f360.opening_count_lines l WHERE l.count_id = c.id AND l.variant_id = p_variant AND l.in_scope)
             OR (SELECT v.created_at FROM f360.product_variants v WHERE v.id = p_variant) > c.loaded_at))
$$;

-- The locations whose stock makes up the online ATS of a size (same set as f360.online_ats).
CREATE FUNCTION f360.online_ats_locations(p_fulfillment uuid) RETURNS SETOF uuid LANGUAGE sql STABLE AS $$
  SELECT p_fulfillment UNION SELECT x FROM f360.online_store_locations() x
$$;

CREATE FUNCTION f360.online_scarcity_reliable(p_variant uuid, p_fulfillment uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT NOT EXISTS (SELECT 1 FROM f360.online_ats_locations(p_fulfillment) loc WHERE NOT f360.variant_inventory_certified(p_variant, loc))
$$;

-- Store page (anon): may the stock count of this Woo variation be shown? Only a boolean — no quantities, no locations.
-- Unknown variation ⇒ false (fail closed).
CREATE FUNCTION public.f360_scarcity_state(p_woo_variation_id int) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE v uuid; v_fulfillment uuid;
BEGIN
  SELECT vl.variant_id, st.fulfillment_location_id INTO v, v_fulfillment FROM f360.woo_variant_links vl
    JOIN f360.sales_targets st ON st.id = vl.target_id AND st.active
    WHERE vl.woo_variation_id = p_woo_variation_id ORDER BY st.created_at LIMIT 1;
  IF v IS NULL THEN RETURN jsonb_build_object('reliable', false); END IF;
  RETURN jsonb_build_object('reliable', f360.online_scarcity_reliable(v, v_fulfillment));
END $$;

-- Team view (operator+): which locations are certified, how and since when.
CREATE FUNCTION public.f360_inventory_certification() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  PERFORM f360.require_role('operator');
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('location_id', l.id, 'name', l.name, 'type', l.type,
      'certified', e.id IS NOT NULL, 'via', CASE e.business_reference_type WHEN 'location_cutover' THEN 'cutover' WHEN 'opening_count' THEN 'conteo de apertura' END,
      'since', e.occurred_at,
      'online', l.id IN (SELECT f360.online_store_locations()) OR l.id IN (SELECT fulfillment_location_id FROM f360.sales_targets WHERE active))
      ORDER BY l.sort, l.name), '[]')
    FROM f360.locations l LEFT JOIN f360.inventory_events e ON e.event_type = 'OPENING_PHYSICAL_COUNT' AND e.business_reference_id = l.id::text
    WHERE l.status = 'active' AND l.type <> 'transit');
END $$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA f360 FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.f360_scarcity_state(int), public.f360_inventory_certification() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.f360_scarcity_state(int) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.f360_inventory_certification() TO authenticated, service_role;
