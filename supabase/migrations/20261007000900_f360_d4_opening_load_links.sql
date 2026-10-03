-- Fuxia 360 Track D · D4 (STAGING) — Mario 2026-10-02: "dale con D4" + "los productos no existentes: una opción para quitarlos".
--   1. Store visibility requests: a person asks to HIDE (Woo status 'private') a store product marked "no existe" in the
--      homologation, or to SHOW it again (previous status). Executed by f360-woo-sync for its own (non-production)
--      channel; never deletes anything in Woo. Production channels are refused by target_by_key.
--   2. f360_opening_load: loads the opening balance of a location from an APPROVED count (owner, idempotent): one
--      OPENING_PHYSICAL_COUNT event (one per location, ever — C3 index), refused if any counted size sold/moved after its
--      count or if the location already holds pairs of those sizes. Then the count is 'cargado' and the freeze ends.
--   3. f360_legacy_link_channel / f360_legacy_unlink_channel: adopt the confirmed homologation on the channel
--      (woo_variant_links legacy_adopted, only after the opening was loaded) and queue a stock push for every linked
--      size; unlink = rehearsal rollback (Woo keeps the last pushed numbers until pushed again).
-- Rollback: supabase/rollbacks/20261007000900_f360_d4_opening_load_links.down.sql

-- ── 1 · store visibility (hide / show) ───────────────────────────────────────
CREATE TABLE f360.woo_visibility_requests (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  target_id          uuid NOT NULL REFERENCES f360.sales_targets(id) ON DELETE RESTRICT,
  woo_product_id     integer NOT NULL CHECK (woo_product_id > 0),
  woo_product_name   text NOT NULL,
  kind               text NOT NULL CHECK (kind IN ('ocultar', 'mostrar')),
  reason             text NOT NULL,
  status             text NOT NULL DEFAULT 'pendiente' CHECK (status IN ('pendiente', 'hecho', 'error')),
  requested_by       uuid, requested_by_name text NOT NULL, requested_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  claimed_at         timestamptz, attempts integer NOT NULL DEFAULT 0,
  done_at            timestamptz, woo_status_before text, woo_status_after text, error text
);
CREATE UNIQUE INDEX woo_visibility_one_pending ON f360.woo_visibility_requests (target_id, woo_product_id) WHERE status = 'pendiente';

-- What the store shows for a Woo product, as far as F360 asked (latest done request).
CREATE FUNCTION f360.woo_visibility(p_target uuid, p_woo_product int) RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object('pending', (SELECT kind FROM f360.woo_visibility_requests WHERE target_id = p_target AND woo_product_id = p_woo_product AND status = 'pendiente'),
    'last', (SELECT jsonb_build_object('kind', kind, 'status', status, 'by', requested_by_name, 'at', coalesce(done_at, requested_at), 'error', error, 'before', woo_status_before)
             FROM f360.woo_visibility_requests WHERE target_id = p_target AND woo_product_id = p_woo_product ORDER BY requested_at DESC LIMIT 1))
$$;

CREATE FUNCTION public.f360_store_visibility_request(p_target_key text, p_woo_product_id int, p_kind text, p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; t f360.sales_targets; v_name text; v_last f360.woo_visibility_requests;
BEGIN
  r := f360.require_role('operator');
  t := f360.target_by_key(p_target_key);
  IF p_kind NOT IN ('ocultar', 'mostrar') THEN RAISE EXCEPTION 'Acción no válida.'; END IF;
  IF coalesce(length(btrim(p_reason)), 0) < 3 THEN RAISE EXCEPTION 'Escribe el motivo.'; END IF;
  SELECT min(woo_product_name) INTO v_name FROM f360.legacy_woo_map WHERE target_id = t.id AND woo_product_id = p_woo_product_id;
  IF v_name IS NULL THEN RAISE EXCEPTION 'Ese producto no está en el catálogo leído de la tienda.'; END IF;
  IF p_kind = 'ocultar' AND EXISTS (SELECT 1 FROM f360.legacy_woo_map WHERE target_id = t.id AND woo_product_id = p_woo_product_id
       AND NOT (status = 'sin_correspondencia' AND human_locked)) THEN
    RAISE EXCEPTION 'Solo se ocultan productos que se marcaron “no existe” en todas sus tallas.';
  END IF;
  IF EXISTS (SELECT 1 FROM f360.woo_visibility_requests WHERE target_id = t.id AND woo_product_id = p_woo_product_id AND status = 'pendiente') THEN
    RAISE EXCEPTION 'Ya hay una solicitud pendiente para “%”.', v_name;
  END IF;
  SELECT * INTO v_last FROM f360.woo_visibility_requests WHERE target_id = t.id AND woo_product_id = p_woo_product_id AND status = 'hecho' ORDER BY done_at DESC LIMIT 1;
  IF p_kind = 'mostrar' AND (v_last.id IS NULL OR v_last.kind <> 'ocultar') THEN RAISE EXCEPTION '“%” no se ocultó desde Fuxia 360.', v_name; END IF;
  IF p_kind = 'ocultar' AND v_last.kind = 'ocultar' THEN RAISE EXCEPTION '“%” ya está oculto.', v_name; END IF;
  INSERT INTO f360.woo_visibility_requests (target_id, woo_product_id, woo_product_name, kind, reason, requested_by, requested_by_name)
    VALUES (t.id, p_woo_product_id, v_name, p_kind, btrim(p_reason), auth.uid(), r.display_name);
  RETURN f360.woo_visibility(t.id, p_woo_product_id) || jsonb_build_object('woo_product_id', p_woo_product_id, 'name', v_name);
END $$;

-- worker side (service_role only)
CREATE FUNCTION public.f360_visibility_claim(p_target_key text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE t f360.sales_targets; out jsonb;
BEGIN
  t := f360.target_by_key(p_target_key);
  WITH c AS (
    UPDATE f360.woo_visibility_requests q SET claimed_at = clock_timestamp(), attempts = attempts + 1
    WHERE q.id IN (SELECT id FROM f360.woo_visibility_requests WHERE target_id = t.id AND status = 'pendiente'
                     AND (claimed_at IS NULL OR claimed_at < clock_timestamp() - interval '2 minutes') ORDER BY requested_at LIMIT 50 FOR UPDATE SKIP LOCKED)
    RETURNING q.id, q.woo_product_id, q.kind,
      (SELECT p.woo_status_before FROM f360.woo_visibility_requests p WHERE p.target_id = q.target_id AND p.woo_product_id = q.woo_product_id
         AND p.kind = 'ocultar' AND p.status = 'hecho' ORDER BY p.done_at DESC LIMIT 1) AS restore_status)
  SELECT coalesce(jsonb_agg(jsonb_build_object('id', id, 'woo_product_id', woo_product_id, 'kind', kind, 'restore_status', restore_status)), '[]') INTO out FROM c;
  RETURN out;
END $$;

-- p_results: [{id, ok, before, after, error}]
CREATE FUNCTION public.f360_visibility_result(p_target_key text, p_results jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE t f360.sales_targets; n_ok int; n_err int;
BEGIN
  t := f360.target_by_key(p_target_key);
  UPDATE f360.woo_visibility_requests q SET status = CASE WHEN x.ok THEN 'hecho' WHEN q.attempts >= 3 THEN 'error' ELSE 'pendiente' END,
      done_at = CASE WHEN x.ok THEN clock_timestamp() END, woo_status_before = coalesce(x.before, q.woo_status_before), woo_status_after = x.after,
      error = x.error, claimed_at = NULL
    FROM jsonb_to_recordset(coalesce(p_results, '[]')) x(id uuid, ok boolean, before text, after text, error text)
    WHERE q.id = x.id AND q.target_id = t.id;
  SELECT count(*) FILTER (WHERE (x->>'ok')::boolean), count(*) FILTER (WHERE NOT (x->>'ok')::boolean) INTO n_ok, n_err FROM jsonb_array_elements(coalesce(p_results, '[]')) x;
  RETURN jsonb_build_object('ok', n_ok, 'failed', n_err);
END $$;

-- ── 2 · opening load from an approved count ─────────────────────────────────
ALTER TABLE f360.opening_counts DROP CONSTRAINT opening_counts_status_check;
ALTER TABLE f360.opening_counts ADD CONSTRAINT opening_counts_status_check CHECK (status IN ('preliminar', 'congelado', 'aprobado', 'cargado', 'cancelado'));
ALTER TABLE f360.opening_counts ADD COLUMN loaded_by_name text, ADD COLUMN loaded_at timestamptz,
  ADD COLUMN load_event_id uuid REFERENCES f360.inventory_events(id) ON DELETE RESTRICT;

CREATE FUNCTION public.f360_opening_load(p_count_id uuid, p_idempotency_key uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; c f360.opening_counts; v_event uuid; v_bad text; n int; v_pairs int;
BEGIN
  r := f360.require_role('owner');
  IF p_idempotency_key IS NULL THEN RAISE EXCEPTION 'Falta la llave de la operación.'; END IF;
  SELECT id INTO v_event FROM f360.inventory_events WHERE idempotency_key = p_idempotency_key;
  IF v_event IS NOT NULL THEN RETURN public.f360_opening_state(p_count_id) || jsonb_build_object('replayed', true); END IF;
  SELECT * INTO c FROM f360.opening_counts WHERE id = p_count_id FOR UPDATE;
  IF c.id IS NULL OR c.status <> 'aprobado' THEN RAISE EXCEPTION 'Solo se carga un conteo aprobado por Mario.'; END IF;
  -- last check: nothing sold or moved after its count (between approval and load)
  SELECT string_agg(f360.variant_label(l.variant_id), ', ') INTO v_bad FROM f360.opening_count_lines l
  WHERE l.count_id = c.id AND l.in_scope AND l.final_qty IS NOT NULL AND (
    EXISTS (SELECT 1 FROM f360.woo_order_lines o WHERE o.target_id = c.target_id AND o.created_at > l.final_at
            AND (o.variant_id = l.variant_id OR o.woo_variation_id IN (SELECT m.woo_variation_id FROM f360.legacy_woo_map m WHERE m.target_id = c.target_id AND m.confirmed_variant_id = l.variant_id)))
    OR EXISTS (SELECT 1 FROM f360.inventory_movements mv JOIN f360.inventory_events e ON e.id = mv.event_id
               WHERE mv.variant_id = l.variant_id AND c.location_id IN (mv.from_location_id, mv.to_location_id) AND e.occurred_at > l.final_at));
  IF v_bad IS NOT NULL THEN RAISE EXCEPTION 'Hubo ventas o movimientos después de contar: %. Cancela el conteo y vuelve a contar esas tallas.', v_bad; END IF;
  IF EXISTS (SELECT 1 FROM f360.inventory_balances b JOIN f360.opening_count_lines l ON l.variant_id = b.variant_id AND l.count_id = c.id AND l.in_scope
             WHERE b.location_id = c.location_id AND b.on_hand <> 0) THEN
    RAISE EXCEPTION 'La ubicación ya tiene pares de estas tallas: el saldo inicial solo se carga sobre cero.';
  END IF;
  INSERT INTO f360.inventory_events (event_type, idempotency_key, actor_auth_user_id, actor_name, actor_role, note, business_reference_type, business_reference_id)
    VALUES ('OPENING_PHYSICAL_COUNT', p_idempotency_key, auth.uid(), r.display_name, r.role,
            'Saldo inicial por conteo físico aprobado · ' || (SELECT name FROM f360.locations WHERE id = c.location_id), 'opening_count', c.location_id::text)
    RETURNING id INTO v_event;
  INSERT INTO f360.inventory_movements (event_id, variant_id, from_location_id, to_location_id, quantity)
    SELECT v_event, l.variant_id, NULL, c.location_id, l.final_qty FROM f360.opening_count_lines l
    WHERE l.count_id = c.id AND l.in_scope AND l.final_qty > 0 ORDER BY l.variant_id;
  GET DIAGNOSTICS n = ROW_COUNT;
  INSERT INTO f360.inventory_balances (variant_id, location_id, on_hand, last_event_id, updated_at)
    SELECT l.variant_id, c.location_id, l.final_qty, v_event, now() FROM f360.opening_count_lines l
    WHERE l.count_id = c.id AND l.in_scope AND l.final_qty > 0
  ON CONFLICT (variant_id, location_id) DO UPDATE SET on_hand = EXCLUDED.on_hand, last_event_id = v_event, updated_at = now();
  SELECT coalesce(sum(final_qty), 0) INTO v_pairs FROM f360.opening_count_lines WHERE count_id = c.id AND in_scope AND final_qty > 0;
  UPDATE f360.opening_counts SET status = 'cargado', loaded_by_name = r.display_name, loaded_at = clock_timestamp(), load_event_id = v_event WHERE id = c.id;
  PERFORM f360.opening_log(c.id, 'load', jsonb_build_object('event', v_event, 'sizes', n, 'pairs', v_pairs), r);
  RETURN public.f360_opening_state(c.id) || jsonb_build_object('replayed', false, 'loaded_sizes', n, 'loaded_pairs', v_pairs);
END $$;

-- ── 3 · adopt the homologation on the channel ───────────────────────────────
CREATE FUNCTION public.f360_legacy_link_channel(p_target_key text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; t f360.sales_targets; n_link int; n_queue int;
BEGIN
  r := f360.require_role('owner');
  t := f360.target_by_key(p_target_key);
  IF NOT EXISTS (SELECT 1 FROM f360.opening_counts WHERE target_id = t.id AND location_id = t.fulfillment_location_id AND status = 'cargado') THEN
    RAISE EXCEPTION 'Primero se carga el saldo inicial (conteo aprobado) de la ubicación de origen.';
  END IF;
  INSERT INTO f360.woo_variant_links (target_id, variant_id, woo_variation_id, origin, woo_product_id)
    SELECT t.id, m.confirmed_variant_id, m.woo_variation_id, 'legacy_adopted', m.woo_product_id FROM f360.legacy_woo_map m
    WHERE m.target_id = t.id AND m.status = 'confirmado'
      AND NOT EXISTS (SELECT 1 FROM f360.woo_variant_links vl WHERE vl.target_id = t.id AND (vl.variant_id = m.confirmed_variant_id OR vl.woo_variation_id = m.woo_variation_id));
  GET DIAGNOSTICS n_link = ROW_COUNT;
  INSERT INTO f360.stock_sync_queue (target_id, variant_id, reason)
    SELECT t.id, vl.variant_id, 'legacy_link' FROM f360.woo_variant_links vl WHERE vl.target_id = t.id AND vl.origin = 'legacy_adopted'
  ON CONFLICT (target_id, variant_id) DO UPDATE SET next_attempt_at = clock_timestamp(), claimed_at = NULL, reason = 'legacy_link';
  GET DIAGNOSTICS n_queue = ROW_COUNT;
  RETURN jsonb_build_object('linked', n_link, 'queued', n_queue,
    'total_links', (SELECT count(*) FROM f360.woo_variant_links WHERE target_id = t.id AND origin = 'legacy_adopted'), 'by', r.display_name);
END $$;

-- REHEARSAL (staging): link only the chosen models, without waiting for the whole opening count, so the team can see a
-- model's real Bodega numbers in the staging store. Owner, reason required; production channels are refused
-- (target_by_key). The full-channel link above keeps requiring the approved + loaded opening count.
CREATE FUNCTION public.f360_legacy_link_products(p_target_key text, p_product_ids uuid[], p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; t f360.sales_targets; n_link int; n_queue int;
BEGIN
  r := f360.require_role('owner');
  t := f360.target_by_key(p_target_key);
  IF t.is_production THEN RAISE EXCEPTION 'En producción se liga el canal completo después del conteo aprobado.'; END IF;
  IF coalesce(length(btrim(p_reason)), 0) < 3 THEN RAISE EXCEPTION 'Escribe el motivo del ensayo.'; END IF;
  IF coalesce(cardinality(p_product_ids), 0) = 0 THEN RAISE EXCEPTION 'Elige al menos un modelo.'; END IF;
  INSERT INTO f360.woo_variant_links (target_id, variant_id, woo_variation_id, origin, woo_product_id)
    SELECT t.id, m.confirmed_variant_id, m.woo_variation_id, 'legacy_adopted', m.woo_product_id
    FROM f360.legacy_woo_map m JOIN f360.product_variants v ON v.id = m.confirmed_variant_id
    WHERE m.target_id = t.id AND m.status = 'confirmado' AND v.product_id = ANY (p_product_ids)
      AND NOT EXISTS (SELECT 1 FROM f360.woo_variant_links vl WHERE vl.target_id = t.id AND (vl.variant_id = m.confirmed_variant_id OR vl.woo_variation_id = m.woo_variation_id));
  GET DIAGNOSTICS n_link = ROW_COUNT;
  INSERT INTO f360.stock_sync_queue (target_id, variant_id, reason)
    SELECT t.id, vl.variant_id, 'legacy_link_ensayo' FROM f360.woo_variant_links vl JOIN f360.product_variants v ON v.id = vl.variant_id
    WHERE vl.target_id = t.id AND vl.origin = 'legacy_adopted' AND v.product_id = ANY (p_product_ids)
  ON CONFLICT (target_id, variant_id) DO UPDATE SET next_attempt_at = clock_timestamp(), claimed_at = NULL, reason = 'legacy_link_ensayo';
  GET DIAGNOSTICS n_queue = ROW_COUNT;
  RETURN jsonb_build_object('linked', n_link, 'queued', n_queue, 'by', r.display_name, 'reason', btrim(p_reason));
END $$;

CREATE FUNCTION public.f360_legacy_unlink_channel(p_target_key text, p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; t f360.sales_targets; n int;
BEGIN
  r := f360.require_role('owner');
  t := f360.target_by_key(p_target_key);
  IF coalesce(length(btrim(p_reason)), 0) < 3 THEN RAISE EXCEPTION 'Escribe el motivo.'; END IF;
  DELETE FROM f360.stock_sync_queue WHERE target_id = t.id AND variant_id IN (SELECT variant_id FROM f360.woo_variant_links WHERE target_id = t.id AND origin = 'legacy_adopted');
  DELETE FROM f360.woo_variant_links WHERE target_id = t.id AND origin = 'legacy_adopted';
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN jsonb_build_object('unlinked', n, 'by', r.display_name, 'reason', btrim(p_reason),
    'note', 'La tienda conserva los últimos números enviados hasta que se vuelvan a enviar.');
END $$;

-- Channel status for the screens: links, queue, last pushes, visibility requests.
CREATE FUNCTION public.f360_legacy_channel_state(p_target_key text DEFAULT 'woo_staging4') RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE t f360.sales_targets;
BEGIN
  PERFORM f360.require_role('operator');
  t := f360.target_by_key(p_target_key);
  RETURN jsonb_build_object('target', t.key,
    'links', (SELECT count(*) FROM f360.woo_variant_links WHERE target_id = t.id AND origin = 'legacy_adopted'),
    'queue', (SELECT count(*) FROM f360.stock_sync_queue WHERE target_id = t.id),
    'last_push', (SELECT max(created_at) FROM f360.stock_sync_log WHERE target_id = t.id),
    'opening_loaded', EXISTS (SELECT 1 FROM f360.opening_counts WHERE target_id = t.id AND status = 'cargado'),
    'visibility', (SELECT coalesce(jsonb_agg(jsonb_build_object('woo_product_id', x.woo_product_id) || f360.woo_visibility(t.id, x.woo_product_id)), '[]')
                   FROM (SELECT DISTINCT woo_product_id FROM f360.woo_visibility_requests WHERE target_id = t.id) x));
END $$;

REVOKE ALL ON f360.woo_visibility_requests FROM PUBLIC, anon, authenticated;
GRANT ALL ON f360.woo_visibility_requests TO service_role;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA f360 FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.f360_store_visibility_request(text, int, text, text), public.f360_visibility_claim(text), public.f360_visibility_result(text, jsonb),
  public.f360_opening_load(uuid, uuid), public.f360_legacy_link_channel(text), public.f360_legacy_unlink_channel(text, text),
  public.f360_legacy_channel_state(text), public.f360_legacy_link_products(text, uuid[], text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.f360_store_visibility_request(text, int, text, text), public.f360_opening_load(uuid, uuid),
  public.f360_legacy_link_channel(text), public.f360_legacy_unlink_channel(text, text), public.f360_legacy_channel_state(text),
  public.f360_legacy_link_products(text, uuid[], text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.f360_visibility_claim(text), public.f360_visibility_result(text, jsonb) TO service_role;
