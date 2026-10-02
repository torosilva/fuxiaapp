-- Fuxia 360 — inventory ADJUSTMENT by hand (STAGING). Additive. Decision: Mario 2026-10-02 ("hacer la 2").
-- Rules: owner only · reason mandatory · one event per adjustment (event_type ADJUSTMENT, note 'Ajuste · <reason>')
--        · never negative · only at locations whose ledger is F360 (assert_ledger_location: not "En camino",
--        not a legacy-ledger store, not during a cutover count) · idempotent (same key → same event, applied once).
-- Removing pairs = movement from the location to nowhere; adding = from nowhere to the location (like a receipt).
-- Rollback: supabase/rollbacks/20261007000600_f360_inventory_adjustment.down.sql

-- p_lines: [{variant_id, delta}]  delta < 0 removes pairs, delta > 0 adds pairs
CREATE FUNCTION public.f360_adjust_inventory(p_idempotency_key uuid, p_location_id uuid, p_lines jsonb, p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; l f360.locations; v_event uuid; x record; v_on int; v_n int := 0;
BEGIN
  r := f360.require_role('owner');
  IF p_idempotency_key IS NULL THEN RAISE EXCEPTION 'Falta la llave de la operación.'; END IF;
  SELECT id INTO v_event FROM f360.inventory_events WHERE idempotency_key = p_idempotency_key;
  IF v_event IS NOT NULL THEN RETURN f360.event_json(v_event) || jsonb_build_object('replayed', true); END IF;
  IF coalesce(length(btrim(p_reason)), 0) < 3 THEN RAISE EXCEPTION 'Escribe el motivo del ajuste.'; END IF;
  l := f360.assert_ledger_location(p_location_id);
  IF p_lines IS NULL OR jsonb_typeof(p_lines) <> 'array' THEN RAISE EXCEPTION 'No hay cantidades para ajustar.'; END IF;
  IF EXISTS (SELECT 1 FROM jsonb_to_recordset(p_lines) y(variant_id uuid, delta int) GROUP BY y.variant_id HAVING count(*) > 1) THEN
    RAISE EXCEPTION 'Cada talla va una sola vez en el ajuste.';
  END IF;

  INSERT INTO f360.inventory_events (event_type, idempotency_key, actor_auth_user_id, actor_name, actor_role, note, business_reference_type)
    VALUES ('ADJUSTMENT', p_idempotency_key, auth.uid(), r.display_name, r.role, 'Ajuste · ' || btrim(p_reason), 'adjustment')
    RETURNING id INTO v_event;

  -- lock the affected balances in a stable order (concurrent sales / moves of the same pairs serialize here)
  FOR x IN SELECT y.variant_id, y.delta FROM jsonb_to_recordset(p_lines) y(variant_id uuid, delta int)
           WHERE coalesce(y.delta, 0) <> 0 ORDER BY y.variant_id LOOP
    IF NOT EXISTS (SELECT 1 FROM f360.product_variants WHERE id = x.variant_id AND status = 'active') THEN
      RAISE EXCEPTION 'Una de las tallas no es válida.';
    END IF;
    INSERT INTO f360.inventory_balances (variant_id, location_id, on_hand) VALUES (x.variant_id, l.id, 0)
      ON CONFLICT (variant_id, location_id) DO NOTHING;
    SELECT on_hand INTO v_on FROM f360.inventory_balances WHERE variant_id = x.variant_id AND location_id = l.id FOR UPDATE;
    IF v_on + x.delta < 0 THEN
      RAISE EXCEPTION 'No se pueden quitar % pares de % en %: solo hay %.', -x.delta, f360.variant_label(x.variant_id), l.name, v_on;
    END IF;
    INSERT INTO f360.inventory_movements (event_id, variant_id, from_location_id, to_location_id, quantity)
      VALUES (v_event, x.variant_id, CASE WHEN x.delta < 0 THEN l.id END, CASE WHEN x.delta > 0 THEN l.id END, abs(x.delta));
    UPDATE f360.inventory_balances SET on_hand = on_hand + x.delta, last_event_id = v_event, updated_at = now()
      WHERE variant_id = x.variant_id AND location_id = l.id;
    v_n := v_n + 1;
  END LOOP;
  IF v_n = 0 THEN RAISE EXCEPTION 'Escribe al menos un par para ajustar.'; END IF;
  UPDATE f360.products SET updated_at = now()
    WHERE id IN (SELECT v.product_id FROM f360.inventory_movements m JOIN f360.product_variants v ON v.id = m.variant_id WHERE m.event_id = v_event);
  RETURN f360.event_json(v_event) || jsonb_build_object('replayed', false);
END $$;

REVOKE ALL ON FUNCTION public.f360_adjust_inventory(uuid, uuid, jsonb, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_adjust_inventory(uuid, uuid, jsonb, text) TO authenticated, service_role;
