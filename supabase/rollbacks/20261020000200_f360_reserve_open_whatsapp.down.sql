-- Rollback of 20261020000200_f360_reserve_open_whatsapp.sql: back to Fuxia Gold only, 2 hours, availability through active channels only.
-- Holds already made keep their expiry. Customers registered through the web hold stay (they are real customers).
DROP FUNCTION IF EXISTS public.f360_reserve_with_code(text, text, text, uuid, uuid, text);
DROP FUNCTION IF EXISTS public.f360_reserve_code_issue(text, text);
DROP FUNCTION IF EXISTS f360.reserve_code_hash(text, text);
DROP TABLE IF EXISTS f360.reserve_codes;

CREATE OR REPLACE FUNCTION f360.reserve(p_customer uuid, p_location uuid, p_variant uuid, p_channel text, p_by text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE l f360.locations; v_tier text; v_open int; v_on int; res f360.reservations;
BEGIN
  SELECT lc.tier INTO v_tier FROM public.loyalty_cards lc WHERE lc.customer_id = p_customer ORDER BY lc.total_points DESC NULLS LAST LIMIT 1;
  IF coalesce(v_tier, '') <> 'gold' THEN RAISE EXCEPTION 'El apartado de 2 horas es un beneficio Fuxia Gold.'; END IF;
  SELECT * INTO l FROM f360.locations WHERE id = p_location;
  IF l.id IS NULL OR l.status <> 'active' OR NOT l.sellable OR l.type NOT IN ('store', 'bazaar') OR l.ledger_authority <> 'f360' OR f360.location_in_cutover(l.id) THEN
    RAISE EXCEPTION 'Esa tienda no tiene apartados disponibles.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM f360.product_variants WHERE id = p_variant AND status = 'active') THEN RAISE EXCEPTION 'Esa talla no existe.'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('f360-res-cust:' || p_customer, 0));
  SELECT count(*) INTO v_open FROM f360.reservations WHERE customer_id = p_customer AND status = 'activa' AND expires_at > clock_timestamp();
  IF v_open >= 2 THEN RAISE EXCEPTION 'Ya tienes 2 pares apartados. Recógelos o cancela uno para apartar otro.'; END IF;
  SELECT on_hand INTO v_on FROM f360.inventory_balances WHERE variant_id = p_variant AND location_id = l.id FOR UPDATE;
  IF coalesce(v_on, 0) - f360.reserved_qty(p_variant, l.id) < 1 THEN RAISE EXCEPTION 'Ya no hay ese par disponible en %.', l.name; END IF;
  INSERT INTO f360.reservations (location_id, variant_id, customer_id, channel, expires_at)
    VALUES (l.id, p_variant, p_customer, p_channel, clock_timestamp() + interval '2 hours') RETURNING * INTO res;
  RETURN jsonb_build_object('id', res.id, 'store', l.name, 'variant', f360.variant_label(p_variant), 'expires_at', res.expires_at, 'status', res.status);
END $$;

CREATE OR REPLACE FUNCTION public.f360_store_availability(p_variant_id uuid DEFAULT NULL, p_woo_variation_id int DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE v uuid := p_variant_id;
BEGIN
  IF v IS NULL AND p_woo_variation_id IS NOT NULL THEN
    SELECT vl.variant_id INTO v FROM f360.woo_variant_links vl JOIN f360.sales_targets t ON t.id = vl.target_id AND t.active
      WHERE vl.woo_variation_id = p_woo_variation_id ORDER BY t.created_at LIMIT 1;
    IF v IS NULL THEN
      SELECT m.confirmed_variant_id INTO v FROM f360.legacy_woo_map m JOIN f360.sales_targets t ON t.id = m.target_id AND t.active
        WHERE m.woo_variation_id = p_woo_variation_id AND m.status = 'confirmado' ORDER BY t.created_at LIMIT 1;
    END IF;
  END IF;
  IF v IS NULL THEN RETURN jsonb_build_object('variant_id', NULL, 'stores', '[]'::jsonb); END IF;
  RETURN jsonb_build_object('variant_id', v, 'stores', f360.store_availability(v));
END $$;
