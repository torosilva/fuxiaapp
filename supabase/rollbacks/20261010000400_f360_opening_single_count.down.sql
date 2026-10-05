-- Rollback of 20261010000400_f360_opening_single_count.sql: back to D3's double count only.
-- Sizes counted once in 'simple' mode go back to 'contado_1' (they will need the second count).
DROP FUNCTION public.f360_opening_easy_sheet(uuid);
DROP FUNCTION public.f360_opening_set_simple(uuid);
UPDATE f360.opening_count_lines SET status = 'contado_1', final_qty = NULL, final_at = NULL WHERE status = 'contado';
ALTER TABLE f360.opening_count_lines DROP CONSTRAINT opening_count_lines_status_check;
ALTER TABLE f360.opening_count_lines ADD CONSTRAINT opening_count_lines_status_check
  CHECK (status IN ('pendiente', 'contado_1', 'doble_ok', 'diferencia', 'recontado', 'recontar'));
CREATE OR REPLACE FUNCTION f360.opening_summary(p_count uuid) RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object(
    'lines', count(*) FILTER (WHERE in_scope),
    'pendiente', count(*) FILTER (WHERE in_scope AND status = 'pendiente'),
    'contado_1', count(*) FILTER (WHERE in_scope AND status = 'contado_1'),
    'doble_ok', count(*) FILTER (WHERE in_scope AND status = 'doble_ok'),
    'diferencia', count(*) FILTER (WHERE in_scope AND status = 'diferencia'),
    'recontado', count(*) FILTER (WHERE in_scope AND status = 'recontado'),
    'recontar', count(*) FILTER (WHERE in_scope AND status = 'recontar'),
    'final_lines', count(*) FILTER (WHERE in_scope AND final_qty IS NOT NULL AND status IN ('doble_ok', 'recontado')),
    'final_pairs', coalesce(sum(final_qty) FILTER (WHERE in_scope AND status IN ('doble_ok', 'recontado')), 0),
    'out_of_scope', count(*) FILTER (WHERE NOT in_scope),
    'unlisted_open', (SELECT count(*) FROM f360.opening_count_unlisted u WHERE u.count_id = p_count AND u.status = 'abierto'),
    'unlisted_pairs', (SELECT coalesce(sum(quantity), 0) FROM f360.opening_count_unlisted u WHERE u.count_id = p_count AND u.status = 'abierto'))
  FROM f360.opening_count_lines WHERE count_id = p_count
$$;

CREATE OR REPLACE FUNCTION f360.opening_blockers(p_count uuid) RETURNS text[] LANGUAGE sql STABLE AS $$
  SELECT array_remove(ARRAY[
    CASE WHEN c.status <> 'congelado' THEN 'Primero congela la bodega (ventana corta antes de aprobar)' END,
    CASE WHEN (s->>'lines')::int = 0 THEN 'No hay tallas en el conteo' END,
    CASE WHEN (s->>'pendiente')::int + (s->>'contado_1')::int > 0 THEN format('%s tallas sin doble conteo', (s->>'pendiente')::int + (s->>'contado_1')::int) END,
    CASE WHEN (s->>'diferencia')::int > 0 THEN format('%s tallas con diferencia entre conteo 1 y 2 (falta reconteo)', s->>'diferencia') END,
    CASE WHEN (s->>'recontar')::int > 0 THEN format('%s tallas con ventas o movimientos después de contarse (falta reconteo)', s->>'recontar') END,
    CASE WHEN (s->>'unlisted_open')::int > 0 THEN format('%s registros de pares sin ficha por resolver', s->>'unlisted_open') END,
    CASE WHEN c.reconciled_at IS NULL OR c.reconciled_at < c.frozen_at THEN 'Falta reconciliar después de congelar' END,
    CASE WHEN EXISTS (SELECT 1 FROM f360.opening_count_lines l WHERE l.count_id = c.id AND l.in_scope AND l.final_at > c.reconciled_at)
      THEN 'Hubo reconteos después de la última reconciliación: reconcilia de nuevo' END
  ], NULL)
  FROM f360.opening_counts c, LATERAL (SELECT f360.opening_summary(c.id) AS s) x WHERE c.id = p_count
$$;

CREATE OR REPLACE FUNCTION public.f360_opening_record(p_count_id uuid, p_round text, p_lines jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; c f360.opening_counts; x record; l f360.opening_count_lines; n int := 0; v_status text; v_final int; v_final_at timestamptz;
BEGIN
  r := f360.require_role('operator');
  IF p_round NOT IN ('1', '2', 're') THEN RAISE EXCEPTION 'Ronda no válida.'; END IF;
  SELECT * INTO c FROM f360.opening_counts WHERE id = p_count_id FOR UPDATE;
  IF c.id IS NULL OR c.status NOT IN ('preliminar', 'congelado') THEN RAISE EXCEPTION 'El conteo no está abierto.'; END IF;
  IF p_lines IS NULL OR jsonb_typeof(p_lines) <> 'array' THEN RAISE EXCEPTION 'No hay cantidades.'; END IF;
  FOR x IN SELECT y.variant_id, y.qty FROM jsonb_to_recordset(p_lines) y(variant_id uuid, qty int) WHERE y.qty IS NOT NULL ORDER BY y.variant_id LOOP
    IF x.qty < 0 THEN RAISE EXCEPTION 'Las cantidades no pueden ser negativas.'; END IF;
    SELECT * INTO l FROM f360.opening_count_lines WHERE count_id = c.id AND variant_id = x.variant_id FOR UPDATE;
    IF l.variant_id IS NULL OR NOT l.in_scope THEN RAISE EXCEPTION 'Una de las tallas no está en este conteo.'; END IF;
    IF p_round = '1' THEN
      IF l.count2 IS NOT NULL THEN RAISE EXCEPTION 'La talla % ya tiene conteo 2: usa el reconteo.', f360.variant_label(l.variant_id); END IF;
      IF l.count1_by IS NOT NULL AND l.count1_by <> auth.uid() THEN RAISE EXCEPTION 'El conteo 1 de % lo hizo otra persona: usa el reconteo si hay que corregirlo.', f360.variant_label(l.variant_id); END IF;
      UPDATE f360.opening_count_lines SET count1 = x.qty, count1_by = auth.uid(), count1_by_name = r.display_name, count1_at = clock_timestamp(), status = 'contado_1'
        WHERE count_id = c.id AND variant_id = l.variant_id;
    ELSIF p_round = '2' THEN
      IF l.count1 IS NULL THEN RAISE EXCEPTION 'La talla % todavía no tiene conteo 1.', f360.variant_label(l.variant_id); END IF;
      IF l.count1_by = auth.uid() THEN RAISE EXCEPTION 'El conteo 2 lo debe hacer otra persona (doble control).'; END IF;
      IF l.count2 IS NOT NULL THEN RAISE EXCEPTION 'La talla % ya tiene conteo 2: usa el reconteo.', f360.variant_label(l.variant_id); END IF;
      v_status := CASE WHEN x.qty = l.count1 THEN 'doble_ok' ELSE 'diferencia' END;
      UPDATE f360.opening_count_lines SET count2 = x.qty, count2_by = auth.uid(), count2_by_name = r.display_name, count2_at = clock_timestamp(), status = v_status,
          final_qty = CASE WHEN v_status = 'doble_ok' THEN x.qty END, final_at = CASE WHEN v_status = 'doble_ok' THEN clock_timestamp() END, affected = NULL
        WHERE count_id = c.id AND variant_id = l.variant_id;
    ELSE
      IF l.status NOT IN ('diferencia', 'recontar') THEN RAISE EXCEPTION 'La talla % no necesita reconteo.', f360.variant_label(l.variant_id); END IF;
      UPDATE f360.opening_count_lines SET recount = x.qty, recount_by = auth.uid(), recount_by_name = r.display_name, recount_at = clock_timestamp(), status = 'recontado',
          final_qty = x.qty, final_at = clock_timestamp(), affected = NULL
        WHERE count_id = c.id AND variant_id = l.variant_id;
    END IF;
    n := n + 1;
  END LOOP;
  IF n = 0 THEN RAISE EXCEPTION 'Escribe al menos una cantidad.'; END IF;
  PERFORM f360.opening_log(c.id, 'count_' || p_round, jsonb_build_object('lines', n), r);
  RETURN public.f360_opening_state(c.id);
END $$;

CREATE OR REPLACE FUNCTION public.f360_opening_reconcile(p_count_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; c f360.opening_counts; n int;
BEGIN
  r := f360.require_role('operator');
  SELECT * INTO c FROM f360.opening_counts WHERE id = p_count_id FOR UPDATE;
  IF c.id IS NULL OR c.status NOT IN ('preliminar', 'congelado') THEN RAISE EXCEPTION 'El conteo no está abierto.'; END IF;
  WITH since AS (
    SELECT l.variant_id, coalesce(l.final_at, l.count2_at, l.count1_at) AS t FROM f360.opening_count_lines l
    WHERE l.count_id = c.id AND l.in_scope AND l.status IN ('doble_ok', 'recontado')   -- final sizes; a size with only count 1 is settled by count 2 / recount
  ), hits AS (
    SELECT s.variant_id,
      (SELECT coalesce(sum(o.quantity), 0) FROM f360.woo_order_lines o
        WHERE o.target_id = c.target_id AND o.created_at > s.t
          AND (o.variant_id = s.variant_id OR o.woo_variation_id IN (SELECT m.woo_variation_id FROM f360.legacy_woo_map m WHERE m.target_id = c.target_id AND m.confirmed_variant_id = s.variant_id))) AS woo_sold,
      (SELECT count(*) FROM f360.inventory_movements mv JOIN f360.inventory_events e ON e.id = mv.event_id
        WHERE mv.variant_id = s.variant_id AND c.location_id IN (mv.from_location_id, mv.to_location_id) AND e.occurred_at > s.t) AS moves
    FROM since s
  )
  UPDATE f360.opening_count_lines l SET status = 'recontar', affected = jsonb_build_object('woo_sold', h.woo_sold, 'moves', h.moves, 'checked_at', clock_timestamp())
  FROM hits h WHERE l.count_id = c.id AND l.variant_id = h.variant_id AND (h.woo_sold > 0 OR h.moves > 0);
  GET DIAGNOSTICS n = ROW_COUNT;
  UPDATE f360.opening_counts SET reconciled_at = clock_timestamp(), reconciled_by_name = r.display_name WHERE id = c.id;
  PERFORM f360.opening_log(c.id, 'reconcile', jsonb_build_object('to_recount', n), r);
  RETURN public.f360_opening_state(c.id) || jsonb_build_object('to_recount', n);
END $$;

CREATE OR REPLACE FUNCTION public.f360_opening_state(p_count_id uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE c f360.opening_counts;
BEGIN
  PERFORM f360.require_role('operator');
  IF p_count_id IS NULL THEN
    SELECT * INTO c FROM f360.opening_counts ORDER BY (status IN ('preliminar', 'congelado')) DESC, started_at DESC LIMIT 1;
  ELSE SELECT * INTO c FROM f360.opening_counts WHERE id = p_count_id; END IF;
  IF c.id IS NULL THEN RETURN jsonb_build_object('count', NULL); END IF;
  RETURN jsonb_build_object('count', jsonb_build_object('id', c.id, 'status', c.status, 'location', (SELECT name FROM f360.locations WHERE id = c.location_id),
      'target', (SELECT jsonb_build_object('key', key, 'name', name) FROM f360.sales_targets WHERE id = c.target_id),
      'started_by', c.started_by_name, 'started_at', c.started_at, 'frozen_by', c.frozen_by_name, 'frozen_at', c.frozen_at,
      'reconciled_at', c.reconciled_at, 'approved_by', c.approved_by_name, 'approved_at', c.approved_at, 'approval_note', c.approval_note,
      'cancelled_at', c.cancelled_at, 'cancel_reason', c.cancel_reason),
    'summary', f360.opening_summary(c.id), 'blockers', to_jsonb(f360.opening_blockers(c.id)));
END $$;
ALTER TABLE f360.opening_counts DROP COLUMN mode;
