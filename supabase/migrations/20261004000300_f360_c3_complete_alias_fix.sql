-- Track C · C3 fix (STAGING): in f360.cutover_do_complete the SQL alias "x" collided with the PL/pgSQL record variable
-- "x" ("record x is not assigned yet"), so a legitimate completion failed (safely: rolled back and audited as
-- complete_failed; the location stayed legacy). Found by the C3 suite. Only change: the alias is now "rv".
-- Rollback: previous definition in 20261004000100_f360_c3_cutover_and_f360_sale.sql (same signature).

CREATE OR REPLACE FUNCTION f360.cutover_do_complete(p_key uuid, c f360.location_cutovers, r f360.user_roles) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE l f360.locations; gate jsonb; v_event uuid; x record; bad int; total int := 0;
BEGIN
  SELECT * INTO l FROM f360.locations WHERE id = c.location_id FOR UPDATE;
  IF l.ledger_authority <> 'legacy' THEN RAISE EXCEPTION '% ya no es legacy.', l.name; END IF;

  -- 1 · C2 gate, LIVE: every legacy row of this store with units must be confirmed to an F360 variant
  SELECT count(*) INTO bad FROM public.channel_inventory ci
    LEFT JOIN f360.legacy_inventory_map m ON m.channel_inventory_id = ci.id
    WHERE ci.channel_id = c.legacy_channel_id AND coalesce(ci.stock, 0) - coalesce(ci.sold, 0) > 0
      AND (m.channel_inventory_id IS NULL OR m.status <> 'confirmado' OR m.confirmed_variant_id IS NULL);
  IF bad > 0 THEN RAISE EXCEPTION 'C2 incompleto: % productos con existencia en el sistema anterior no están mapeados a Fuxia 360.', bad; END IF;
  gate := public.f360_location_migration_readiness(l.id);
  IF NOT coalesce((gate->>'catalog_ready')::boolean, false) THEN RAISE EXCEPTION 'C2 incompleto: el mapeo del catálogo no está listo.'; END IF;

  -- 2 · double control complete
  IF NOT EXISTS (SELECT 1 FROM f360.cutover_counts WHERE cutover_id = c.id) THEN RAISE EXCEPTION 'No hay conteo.'; END IF;
  IF EXISTS (SELECT 1 FROM f360.cutover_counts WHERE cutover_id = c.id AND (status <> 'verified' OR verified_by IS NULL OR verified_by = counted_by OR verified_qty <> counted_qty)) THEN
    RAISE EXCEPTION 'El conteo no tiene doble control completo.';
  END IF;
  IF EXISTS (SELECT 1 FROM f360.cutover_required_variants(c.id) rv
             WHERE NOT EXISTS (SELECT 1 FROM f360.cutover_counts k WHERE k.cutover_id = c.id AND k.variant_id = rv.variant_id)) THEN
    RAISE EXCEPTION 'Faltan tallas por contar.';
  END IF;

  -- 3 · never two opening balances: the location must have no ledger history at all
  IF EXISTS (SELECT 1 FROM f360.inventory_movements WHERE from_location_id = l.id OR to_location_id = l.id)
     OR EXISTS (SELECT 1 FROM f360.inventory_balances WHERE location_id = l.id AND on_hand <> 0) THEN
    RAISE EXCEPTION '% ya tiene movimientos en Fuxia 360: no puede recibir un segundo saldo inicial.', l.name;
  END IF;

  -- 4 · the opening event + one movement per counted variant (quantity 0 = no movement)
  INSERT INTO f360.inventory_events (event_type, idempotency_key, actor_auth_user_id, actor_name, actor_role, note, business_reference_type, business_reference_id)
    VALUES ('OPENING_PHYSICAL_COUNT', p_key, r.auth_user_id, r.display_name, r.role, 'Saldo inicial por conteo físico verificado · ' || l.name, 'location_cutover', l.id::text)
    RETURNING id INTO v_event;
  FOR x IN SELECT variant_id, counted_qty FROM f360.cutover_counts WHERE cutover_id = c.id AND counted_qty > 0 ORDER BY variant_id LOOP
    PERFORM f360.ledger_move(v_event, x.variant_id, NULL, l.id, x.counted_qty);
    total := total + x.counted_qty;
  END LOOP;

  -- 5 · balances == physical count, exactly (every variant, both directions)
  SELECT count(*) INTO bad FROM (
    SELECT variant_id, counted_qty AS q FROM f360.cutover_counts WHERE cutover_id = c.id AND counted_qty > 0) k
    FULL JOIN (SELECT variant_id, on_hand AS q FROM f360.inventory_balances WHERE location_id = l.id AND on_hand <> 0) b ON b.variant_id = k.variant_id
    WHERE coalesce(k.q, -1) <> coalesce(b.q, -1);
  IF bad > 0 THEN RAISE EXCEPTION 'Los saldos no coinciden con el conteo (% diferencias).', bad; END IF;

  -- 6 · mark completed, THEN switch authority (the location trigger requires the completed, verified cutover)
  UPDATE f360.location_cutovers SET status = 'completed', complete_key = p_key, completed_by_name = r.display_name, completed_at = now(),
      opening_event_id = v_event, c2_readiness = gate, counted_pairs = total WHERE id = c.id;
  UPDATE f360.locations SET ledger_authority = 'f360', is_authoritative = true, sales_sync_pending = false WHERE id = l.id;
  -- 7 · legacy writes for this store are now frozen by channel_inventory_freeze / offline_sales_client_guard (authority = f360)
  RETURN v_event;
END $$;
