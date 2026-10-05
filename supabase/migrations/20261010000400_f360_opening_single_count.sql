-- Fuxia 360 · Conteo de apertura en MODO SIMPLE (un solo conteo). STAGING.
-- Decision: Mario 2026-10-05, option (b): "un solo conteo y aprobación de Carolina, para que Carolina lo haga ya".
-- The admin screen starts every new count in 'simple' (f360_opening_start + f360_opening_set_simple). The column default
-- stays 'doble' so D3's API and tests keep their meaning; existing counts keep mode 'doble'.
-- What stays (it is not the double count, it protects the opening balance):
--   * short freeze + reconciliation: a size sold online / moved after it was counted must be recounted;
--   * pairs "sin ficha" resolved before approval;
--   * approval by an owner; loading the balance remains the separate D4 step (f360_opening_load).
-- In 'simple' mode the first count IS the final quantity (status 'contado'), and any operator may correct it while the
-- count is open; every write is in the append-only change log.
-- Rollback: supabase/rollbacks/20261010000400_f360_opening_single_count.down.sql

ALTER TABLE f360.opening_counts ADD COLUMN mode text NOT NULL DEFAULT 'doble' CHECK (mode IN ('doble', 'simple'));

ALTER TABLE f360.opening_count_lines DROP CONSTRAINT opening_count_lines_status_check;
ALTER TABLE f360.opening_count_lines ADD CONSTRAINT opening_count_lines_status_check
  CHECK (status IN ('pendiente', 'contado_1', 'doble_ok', 'diferencia', 'recontado', 'recontar', 'contado'));

CREATE OR REPLACE FUNCTION f360.opening_summary(p_count uuid) RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object(
    'mode', (SELECT mode FROM f360.opening_counts WHERE id = p_count),
    'lines', count(*) FILTER (WHERE in_scope),
    'pendiente', count(*) FILTER (WHERE in_scope AND status = 'pendiente'),
    'contado_1', count(*) FILTER (WHERE in_scope AND status = 'contado_1'),
    'contado', count(*) FILTER (WHERE in_scope AND status = 'contado'),
    'doble_ok', count(*) FILTER (WHERE in_scope AND status = 'doble_ok'),
    'diferencia', count(*) FILTER (WHERE in_scope AND status = 'diferencia'),
    'recontado', count(*) FILTER (WHERE in_scope AND status = 'recontado'),
    'recontar', count(*) FILTER (WHERE in_scope AND status = 'recontar'),
    'final_lines', count(*) FILTER (WHERE in_scope AND final_qty IS NOT NULL AND status IN ('doble_ok', 'recontado', 'contado')),
    'final_pairs', coalesce(sum(final_qty) FILTER (WHERE in_scope AND status IN ('doble_ok', 'recontado', 'contado')), 0),
    'out_of_scope', count(*) FILTER (WHERE NOT in_scope),
    'unlisted_open', (SELECT count(*) FROM f360.opening_count_unlisted u WHERE u.count_id = p_count AND u.status = 'abierto'),
    'unlisted_pairs', (SELECT coalesce(sum(quantity), 0) FROM f360.opening_count_unlisted u WHERE u.count_id = p_count AND u.status = 'abierto'))
  FROM f360.opening_count_lines WHERE count_id = p_count
$$;

CREATE OR REPLACE FUNCTION f360.opening_blockers(p_count uuid) RETURNS text[] LANGUAGE sql STABLE AS $$
  SELECT array_remove(ARRAY[
    CASE WHEN c.status <> 'congelado' THEN 'Primero congela la bodega (ventana corta antes de aprobar)' END,
    CASE WHEN (s->>'lines')::int = 0 THEN 'No hay tallas en el conteo' END,
    CASE WHEN c.mode = 'simple' AND (s->>'pendiente')::int > 0 THEN format('%s tallas sin contar (escribe 0 si no hay pares)', s->>'pendiente') END,
    CASE WHEN c.mode = 'doble' AND (s->>'pendiente')::int + (s->>'contado_1')::int > 0 THEN format('%s tallas sin doble conteo', (s->>'pendiente')::int + (s->>'contado_1')::int) END,
    CASE WHEN (s->>'diferencia')::int > 0 THEN format('%s tallas con diferencia entre conteo 1 y 2 (falta reconteo)', s->>'diferencia') END,
    CASE WHEN (s->>'recontar')::int > 0 THEN format('%s tallas con ventas o movimientos después de contarse (falta reconteo)', s->>'recontar') END,
    CASE WHEN (s->>'unlisted_open')::int > 0 THEN format('%s registros de pares sin ficha por resolver', s->>'unlisted_open') END,
    CASE WHEN c.reconciled_at IS NULL OR c.reconciled_at < c.frozen_at THEN 'Falta reconciliar después de congelar' END,
    CASE WHEN EXISTS (SELECT 1 FROM f360.opening_count_lines l WHERE l.count_id = c.id AND l.in_scope AND l.final_at > c.reconciled_at)
      THEN 'Hubo conteos o reconteos después de la última reconciliación: reconcilia de nuevo' END
  ], NULL)
  FROM f360.opening_counts c, LATERAL (SELECT f360.opening_summary(c.id) AS s) x WHERE c.id = p_count
$$;

CREATE OR REPLACE FUNCTION public.f360_opening_record(p_count_id uuid, p_round text, p_lines jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; c f360.opening_counts; x record; l f360.opening_count_lines; n int := 0; v_status text;
BEGIN
  r := f360.require_role('operator');
  IF p_round NOT IN ('1', '2', 're') THEN RAISE EXCEPTION 'Ronda no válida.'; END IF;
  SELECT * INTO c FROM f360.opening_counts WHERE id = p_count_id FOR UPDATE;
  IF c.id IS NULL OR c.status NOT IN ('preliminar', 'congelado') THEN RAISE EXCEPTION 'El conteo no está abierto.'; END IF;
  IF c.mode = 'simple' AND p_round = '2' THEN RAISE EXCEPTION 'Este conteo es de una sola vuelta: no lleva segundo conteo.'; END IF;
  IF p_lines IS NULL OR jsonb_typeof(p_lines) <> 'array' THEN RAISE EXCEPTION 'No hay cantidades.'; END IF;
  FOR x IN SELECT y.variant_id, y.qty FROM jsonb_to_recordset(p_lines) y(variant_id uuid, qty int) WHERE y.qty IS NOT NULL ORDER BY y.variant_id LOOP
    IF x.qty < 0 THEN RAISE EXCEPTION 'Las cantidades no pueden ser negativas.'; END IF;
    IF x.qty > 9999 THEN RAISE EXCEPTION 'Revisa la cantidad: % pares en una sola talla.', x.qty; END IF;
    SELECT * INTO l FROM f360.opening_count_lines WHERE count_id = c.id AND variant_id = x.variant_id FOR UPDATE;
    IF l.variant_id IS NULL OR NOT l.in_scope THEN RAISE EXCEPTION 'Una de las tallas no está en este conteo.'; END IF;
    IF c.mode = 'simple' AND p_round = '1' THEN
      -- one count: it is the final quantity. Correctable by any operator while open (logged). After reconciliation flags
      -- a size ('recontar'), it is settled with the recount round.
      IF l.status = 'recontar' THEN RAISE EXCEPTION 'La talla % se vendió o movió después de contarse: usa "Recontar".', f360.variant_label(l.variant_id); END IF;
      UPDATE f360.opening_count_lines SET count1 = x.qty, count1_by = auth.uid(), count1_by_name = r.display_name, count1_at = clock_timestamp(),
          status = 'contado', final_qty = x.qty, final_at = clock_timestamp(), affected = NULL
        WHERE count_id = c.id AND variant_id = l.variant_id;
    ELSIF p_round = '1' THEN
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
  PERFORM f360.opening_log(c.id, 'count_' || p_round, jsonb_build_object('lines', n, 'mode', c.mode,
    'values', (SELECT jsonb_agg(jsonb_build_object('variant_id', y.variant_id, 'qty', y.qty)) FROM jsonb_to_recordset(p_lines) y(variant_id uuid, qty int) WHERE y.qty IS NOT NULL)), r);
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
    WHERE l.count_id = c.id AND l.in_scope AND l.status IN ('doble_ok', 'recontado', 'contado')
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
  RETURN jsonb_build_object('count', jsonb_build_object('id', c.id, 'status', c.status, 'mode', c.mode, 'location', (SELECT name FROM f360.locations WHERE id = c.location_id),
      'target', (SELECT jsonb_build_object('key', key, 'name', name) FROM f360.sales_targets WHERE id = c.target_id),
      'started_by', c.started_by_name, 'started_at', c.started_at, 'frozen_by', c.frozen_by_name, 'frozen_at', c.frozen_at,
      'reconciled_at', c.reconciled_at, 'approved_by', c.approved_by_name, 'approved_at', c.approved_at, 'approval_note', c.approval_note,
      'cancelled_at', c.cancelled_at, 'cancel_reason', c.cancel_reason),
    'summary', f360.opening_summary(c.id), 'blockers', to_jsonb(f360.opening_blockers(c.id)));
END $$;

-- An open double count can be switched to simple by an owner (sizes with only count 1 become final). Not back.
CREATE FUNCTION public.f360_opening_set_simple(p_count_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('owner'); c f360.opening_counts; n int;
BEGIN
  SELECT * INTO c FROM f360.opening_counts WHERE id = p_count_id FOR UPDATE;
  IF c.id IS NULL OR c.status <> 'preliminar' THEN RAISE EXCEPTION 'Solo un conteo preliminar puede cambiar a una sola vuelta.'; END IF;
  IF c.mode = 'simple' THEN RETURN public.f360_opening_state(c.id); END IF;
  UPDATE f360.opening_count_lines SET status = 'contado', final_qty = count1, final_at = count1_at
    WHERE count_id = c.id AND status = 'contado_1';
  GET DIAGNOSTICS n = ROW_COUNT;
  UPDATE f360.opening_counts SET mode = 'simple' WHERE id = c.id;
  PERFORM f360.opening_log(c.id, 'set_simple', jsonb_build_object('sizes_made_final', n, 'decision', 'Mario 2026-10-05 (b)'), r);
  RETURN public.f360_opening_state(c.id);
END $$;

-- The easy count screen: one call with every model (photo, colors, sizes, current count), searchable on the phone.
CREATE FUNCTION public.f360_opening_easy_sheet(p_count_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('operator'); c f360.opening_counts;
BEGIN
  SELECT * INTO c FROM f360.opening_counts WHERE id = p_count_id;
  IF c.id IS NULL THEN RAISE EXCEPTION 'Conteo no encontrado.'; END IF;
  RETURN jsonb_build_object('count_id', c.id, 'status', c.status, 'mode', c.mode, 'me', r.display_name,
    'location', (SELECT name FROM f360.locations WHERE id = c.location_id),
    'models', (SELECT coalesce(jsonb_agg(jsonb_build_object('product_id', pm.id, 'model', pm.name, 'image', pm.image_path, 'colors', pm.colors,
                 'sizes_total', pm.n, 'sizes_done', pm.done) ORDER BY pm.name), '[]') FROM (
      SELECT p.id, p.name, p.image_path, sum(pc.n)::int n, sum(pc.done)::int done,
             jsonb_agg(jsonb_build_object('color', pc.name, 'hex', pc.hex, 'sizes', pc.sizes) ORDER BY pc.sort, pc.name) AS colors
      FROM f360.products p JOIN LATERAL (
        SELECT co.name, co.hex, co.sort, count(*) n, count(*) FILTER (WHERE l.final_qty IS NOT NULL AND l.status <> 'recontar') done,
          jsonb_agg(jsonb_build_object('variant_id', v.id, 'size', v.size_label, 'status', l.status, 'qty', CASE WHEN l.status = 'recontar' THEN NULL ELSE l.final_qty END,
            'by', coalesce(l.recount_by_name, l.count1_by_name)) ORDER BY ps.sort) AS sizes
        FROM f360.product_colors co JOIN f360.product_variants v ON v.color_id = co.id
        JOIN f360.product_sizes ps ON ps.product_id = v.product_id AND ps.label = v.size_label
        JOIN f360.opening_count_lines l ON l.count_id = c.id AND l.variant_id = v.id AND l.in_scope
        WHERE co.product_id = p.id GROUP BY co.id, co.name, co.hex, co.sort) pc ON true
      GROUP BY p.id, p.name, p.image_path) pm),
    'summary', f360.opening_summary(c.id));
END $$;

REVOKE ALL ON FUNCTION public.f360_opening_set_simple(uuid), public.f360_opening_easy_sheet(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_opening_set_simple(uuid), public.f360_opening_easy_sheet(uuid) TO authenticated;
