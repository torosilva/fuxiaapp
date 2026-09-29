-- Track C · Transfers fix (STAGING): Supabase loads pg_safeupdate for API connections, which rejects a DELETE without
-- WHERE — even on the function's own temp table. Found by the real-concurrency harness (the rolled-back SQL suite runs
-- outside PostgREST). Only change: `DELETE FROM pg_temp.t_send/t_recv WHERE true`. Rollback: the previous definitions
-- are in 20261003000100_f360_transfers.sql (same signatures).

CREATE OR REPLACE FUNCTION f360.transfer_do_send(p_key uuid, p_transfer uuid, p_lines jsonb, r f360.user_roles) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE t f360.transfers; v_transit uuid := f360.transit_location(); v_event uuid; x record; v_total int := 0; v_audit jsonb := '[]';
BEGIN
  SELECT * INTO t FROM f360.transfers WHERE id = p_transfer FOR UPDATE;
  IF t.id IS NULL THEN RAISE EXCEPTION 'Transferencia no encontrada.'; END IF;
  IF t.status <> 'requested' THEN RAISE EXCEPTION 'La transferencia % ya no está pendiente de envío (%).', t.number, t.status; END IF;
  PERFORM f360.assert_ledger_location(t.from_location_id);
  PERFORM f360.assert_ledger_location(t.to_location_id);

  -- quantities to send: explicit lines (≤ requested; 0 allowed) or, if omitted, exactly what was requested
  CREATE TEMP TABLE IF NOT EXISTS pg_temp.t_send (variant_id uuid PRIMARY KEY, quantity int) ON COMMIT DROP;
  DELETE FROM pg_temp.t_send WHERE true;
  IF p_lines IS NULL THEN
    INSERT INTO pg_temp.t_send SELECT l.variant_id, l.requested_qty FROM f360.transfer_lines l WHERE l.transfer_id = t.id;
  ELSE
    INSERT INTO pg_temp.t_send SELECT * FROM f360.transfer_qty_lines(p_lines, true);
    IF EXISTS (SELECT 1 FROM pg_temp.t_send s LEFT JOIN f360.transfer_lines l ON l.transfer_id = t.id AND l.variant_id = s.variant_id WHERE l.variant_id IS NULL) THEN
      RAISE EXCEPTION 'Solo se pueden enviar tallas que están en la solicitud.';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_temp.t_send s JOIN f360.transfer_lines l ON l.transfer_id = t.id AND l.variant_id = s.variant_id WHERE s.quantity > l.requested_qty) THEN
      RAISE EXCEPTION 'No puedes enviar más pares de los solicitados.';
    END IF;
    INSERT INTO pg_temp.t_send SELECT l.variant_id, 0 FROM f360.transfer_lines l WHERE l.transfer_id = t.id ON CONFLICT DO NOTHING;
  END IF;
  IF (SELECT coalesce(sum(quantity), 0) FROM pg_temp.t_send) = 0 THEN RAISE EXCEPTION 'Escribe al menos un par para enviar.'; END IF;

  -- lock origin balances in variant order (same order as every other stock writer → no deadlocks), then validate all
  PERFORM 1 FROM f360.inventory_balances b JOIN pg_temp.t_send s ON s.variant_id = b.variant_id
    WHERE b.location_id = t.from_location_id AND s.quantity > 0 ORDER BY b.variant_id FOR UPDATE OF b;
  FOR x IN SELECT s.variant_id, s.quantity, coalesce(b.on_hand, 0) AS on_hand FROM pg_temp.t_send s
           LEFT JOIN f360.inventory_balances b ON b.variant_id = s.variant_id AND b.location_id = t.from_location_id
           WHERE s.quantity > 0 ORDER BY s.variant_id LOOP
    IF x.on_hand < x.quantity THEN
      RAISE EXCEPTION 'No hay suficientes pares de % en % (hay %, quieres enviar %). No se envió nada.',
        f360.variant_label(x.variant_id), (SELECT name FROM f360.locations WHERE id = t.from_location_id), x.on_hand, x.quantity;
    END IF;
  END LOOP;

  INSERT INTO f360.inventory_events (event_type, idempotency_key, actor_auth_user_id, actor_name, actor_role, note, business_reference_type, business_reference_id)
    VALUES ('TRANSFER', p_key, r.auth_user_id, r.display_name, r.role, 'Enviado · ' || t.number, 'transfer', t.number) RETURNING id INTO v_event;
  FOR x IN SELECT * FROM pg_temp.t_send ORDER BY variant_id LOOP
    PERFORM f360.ledger_move(v_event, x.variant_id, t.from_location_id, v_transit, x.quantity);
    UPDATE f360.transfer_lines SET sent_qty = x.quantity WHERE transfer_id = t.id AND variant_id = x.variant_id;
    v_total := v_total + x.quantity;
    v_audit := v_audit || jsonb_build_object('variant_id', x.variant_id, 'label', f360.variant_label(x.variant_id), 'quantity', x.quantity);
  END LOOP;
  UPDATE f360.transfers SET status = 'in_transit', sent_by_name = r.display_name, sent_at = now(), send_event_id = v_event WHERE id = t.id;
  SELECT * INTO t FROM f360.transfers WHERE id = t.id;
  PERFORM f360.transfer_audit(t, p_key, 'send', 'requested', v_audit, NULL, ARRAY[v_event], r);
END $$;

CREATE OR REPLACE FUNCTION public.f360_receive_transfer(p_idempotency_key uuid, p_transfer_id uuid, p_lines jsonb DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; prior jsonb; t f360.transfers; v_transit uuid := f360.transit_location(); v_event uuid; x record;
        v_total int := 0; v_short boolean := false; v_audit jsonb := '[]';
BEGIN
  r := f360.require_role('viewer');
  prior := f360.transfer_replay(p_idempotency_key, p_transfer_id, 'receive', r);
  IF prior IS NOT NULL THEN RETURN prior; END IF;
  SELECT * INTO t FROM f360.transfers WHERE id = p_transfer_id FOR UPDATE;
  IF t.id IS NULL OR NOT f360.can_see_transfer(r, t) THEN RAISE EXCEPTION 'Transferencia no encontrada.'; END IF;
  IF r.role = 'viewer' THEN RAISE EXCEPTION 'Tu cuenta no tiene permiso para esta acción.' USING ERRCODE = 'insufficient_privilege'; END IF;
  IF r.role = 'seller' THEN PERFORM f360.require_location(t.to_location_id); END IF;   -- live: a revoked assignment fails here
  IF t.status <> 'in_transit' THEN RAISE EXCEPTION 'La transferencia % no está en camino (%).', t.number, t.status; END IF;
  PERFORM f360.assert_ledger_location(t.to_location_id);

  CREATE TEMP TABLE IF NOT EXISTS pg_temp.t_recv (variant_id uuid PRIMARY KEY, quantity int) ON COMMIT DROP;
  DELETE FROM pg_temp.t_recv WHERE true;
  IF p_lines IS NULL THEN
    INSERT INTO pg_temp.t_recv SELECT l.variant_id, l.sent_qty FROM f360.transfer_lines l WHERE l.transfer_id = t.id;
  ELSE
    INSERT INTO pg_temp.t_recv SELECT * FROM f360.transfer_qty_lines(p_lines, true);
    IF EXISTS (SELECT 1 FROM pg_temp.t_recv s LEFT JOIN f360.transfer_lines l ON l.transfer_id = t.id AND l.variant_id = s.variant_id WHERE l.variant_id IS NULL) THEN
      RAISE EXCEPTION 'Esa talla no viene en esta transferencia.';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_temp.t_recv s JOIN f360.transfer_lines l ON l.transfer_id = t.id AND l.variant_id = s.variant_id WHERE s.quantity > l.sent_qty) THEN
      RAISE EXCEPTION 'No puedes recibir más pares de los que se enviaron.';
    END IF;
    INSERT INTO pg_temp.t_recv SELECT l.variant_id, 0 FROM f360.transfer_lines l WHERE l.transfer_id = t.id ON CONFLICT DO NOTHING;
  END IF;

  PERFORM 1 FROM f360.inventory_balances b JOIN pg_temp.t_recv s ON s.variant_id = b.variant_id
    WHERE b.location_id = v_transit AND s.quantity > 0 ORDER BY b.variant_id FOR UPDATE OF b;
  IF (SELECT coalesce(sum(quantity), 0) FROM pg_temp.t_recv) > 0 THEN
    INSERT INTO f360.inventory_events (event_type, idempotency_key, actor_auth_user_id, actor_name, actor_role, note, business_reference_type, business_reference_id)
      VALUES ('TRANSFER', p_idempotency_key, r.auth_user_id, r.display_name, r.role, 'Recibido · ' || t.number, 'transfer', t.number) RETURNING id INTO v_event;
  END IF;
  FOR x IN SELECT s.variant_id, s.quantity, l.sent_qty FROM pg_temp.t_recv s JOIN f360.transfer_lines l ON l.transfer_id = t.id AND l.variant_id = s.variant_id ORDER BY s.variant_id LOOP
    IF x.quantity > 0 THEN PERFORM f360.ledger_move(v_event, x.variant_id, v_transit, t.to_location_id, x.quantity); END IF;
    UPDATE f360.transfer_lines SET received_qty = x.quantity WHERE transfer_id = t.id AND variant_id = x.variant_id;
    v_total := v_total + x.quantity;
    v_short := v_short OR x.quantity < coalesce(x.sent_qty, 0);
    v_audit := v_audit || jsonb_build_object('variant_id', x.variant_id, 'label', f360.variant_label(x.variant_id), 'sent', x.sent_qty, 'quantity', x.quantity);
  END LOOP;
  UPDATE f360.transfers SET status = CASE WHEN v_short THEN 'with_difference' ELSE 'received' END,
      received_by_name = r.display_name, received_at = now(), receive_event_id = v_event WHERE id = t.id RETURNING * INTO t;
  PERFORM f360.transfer_audit(t, p_idempotency_key, 'receive', 'in_transit', v_audit, NULL, CASE WHEN v_event IS NULL THEN NULL ELSE ARRAY[v_event] END, r);
  RETURN f360.transfer_json(t.id, r) || jsonb_build_object('replayed', false);
END $$;

REVOKE ALL ON FUNCTION f360.transfer_do_send(uuid, uuid, jsonb, f360.user_roles) FROM PUBLIC, anon, authenticated;
