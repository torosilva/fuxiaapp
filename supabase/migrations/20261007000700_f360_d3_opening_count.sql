-- Fuxia 360 Track D · D3 — Physical OPENING COUNT of a fulfillment location (Bodega CDMX) for the legacy catalog (STAGING).
-- Decisions: Mario 2026-10-02.
--   * The opening balance comes ONLY from the physical count, never from Woo's stock.
--   * Double control: count 1 and count 2 by DIFFERENT people, count 2 blind; any difference → recount.
--   * A preliminary count is allowed; before approval a SHORT FREEZE window blocks F360 moves at the location and a
--     reconciliation marks every size with Woo sales / F360 movements after its count → it must be recounted.
--   * Pairs found without a homologated variant are recorded as "sin ficha" and must be resolved before approval.
--   * NOTHING here writes inventory. Approval (owner) only seals the count; loading the opening balance is a separate,
--     explicitly approved step (D4 / cutover) that is NOT part of this migration.
-- Rollback: supabase/rollbacks/20261007000700_f360_d3_opening_count.down.sql

CREATE TABLE f360.opening_counts (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  target_id          uuid NOT NULL REFERENCES f360.sales_targets(id) ON DELETE RESTRICT,
  location_id        uuid NOT NULL REFERENCES f360.locations(id) ON DELETE RESTRICT,
  status             text NOT NULL DEFAULT 'preliminar' CHECK (status IN ('preliminar', 'congelado', 'aprobado', 'cancelado')),
  started_by_name    text NOT NULL,
  started_at         timestamptz NOT NULL DEFAULT clock_timestamp(),
  frozen_by_name     text, frozen_at timestamptz,
  reconciled_at      timestamptz, reconciled_by_name text,
  approved_by        uuid REFERENCES auth.users(id) ON DELETE SET NULL, approved_by_name text, approved_at timestamptz, approval_note text,
  cancelled_by_name  text, cancelled_at timestamptz, cancel_reason text,
  note               text
);
CREATE UNIQUE INDEX opening_counts_one_open ON f360.opening_counts (location_id) WHERE status IN ('preliminar', 'congelado');

CREATE TABLE f360.opening_count_lines (
  count_id         uuid NOT NULL REFERENCES f360.opening_counts(id) ON DELETE RESTRICT,
  variant_id       uuid NOT NULL REFERENCES f360.product_variants(id) ON DELETE RESTRICT,
  in_scope         boolean NOT NULL DEFAULT true,          -- false = its homologation was reopened after the count started
  count1           integer CHECK (count1 >= 0), count1_by uuid, count1_by_name text, count1_at timestamptz,
  count2           integer CHECK (count2 >= 0), count2_by uuid, count2_by_name text, count2_at timestamptz,
  recount          integer CHECK (recount >= 0), recount_by uuid, recount_by_name text, recount_at timestamptz,
  final_qty        integer CHECK (final_qty >= 0),
  final_at         timestamptz,                            -- when the final quantity was established (for reconciliation)
  status           text NOT NULL DEFAULT 'pendiente'
                   CHECK (status IN ('pendiente', 'contado_1', 'doble_ok', 'diferencia', 'recontado', 'recontar')),
  affected         jsonb,                                  -- what happened after its count (Woo sales / F360 moves)
  woo_managed      boolean, woo_stock integer,             -- Woo reference only (never the opening balance)
  PRIMARY KEY (count_id, variant_id),
  CHECK (count2_by IS NULL OR count1_by IS NULL OR count2_by <> count1_by)
);

CREATE TABLE f360.opening_count_unlisted (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  count_id         uuid NOT NULL REFERENCES f360.opening_counts(id) ON DELETE RESTRICT,
  description      text NOT NULL,
  size_label       text,
  quantity         integer NOT NULL CHECK (quantity > 0),
  found_by_name    text NOT NULL,
  found_at         timestamptz NOT NULL DEFAULT clock_timestamp(),
  status           text NOT NULL DEFAULT 'abierto' CHECK (status IN ('abierto', 'resuelto')),
  resolution       text, resolved_by_name text, resolved_at timestamptz
);

CREATE TABLE f360.opening_count_changes (
  id          bigserial PRIMARY KEY,
  count_id    uuid NOT NULL REFERENCES f360.opening_counts(id) ON DELETE RESTRICT,
  action      text NOT NULL,
  detail      jsonb,
  actor_auth_user_id uuid,
  actor_name  text NOT NULL,
  at          timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE FUNCTION f360.opening_changes_append_only() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'El historial del conteo no se puede modificar.';
END $$;
CREATE TRIGGER opening_count_changes_append_only BEFORE UPDATE OR DELETE ON f360.opening_count_changes
  FOR EACH ROW EXECUTE FUNCTION f360.opening_changes_append_only();

-- A frozen opening count blocks F360 moves at its location, exactly like a C3 store cutover
-- (assert_ledger_location → receive, transfer, adjustment and store sales are refused there).
CREATE OR REPLACE FUNCTION f360.location_in_cutover(p_location uuid) RETURNS boolean LANGUAGE sql STABLE AS
$$ SELECT EXISTS (SELECT 1 FROM f360.location_cutovers WHERE location_id = p_location AND status IN ('preparing', 'counting', 'verification', 'ready'))
       OR EXISTS (SELECT 1 FROM f360.opening_counts WHERE location_id = p_location AND status IN ('congelado', 'aprobado')) $$;

CREATE FUNCTION f360.opening_log(p_count uuid, p_action text, p_detail jsonb, r f360.user_roles) RETURNS void LANGUAGE sql AS $$
  INSERT INTO f360.opening_count_changes (count_id, action, detail, actor_auth_user_id, actor_name) VALUES (p_count, p_action, p_detail, r.auth_user_id, r.display_name)
$$;

-- Lines = every variant confirmed in the homologation of the session's channel (added if missing; out of scope if reopened).
CREATE FUNCTION f360.opening_sync_scope(p_count uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE c f360.opening_counts; n_add int; n_out int; n_back int;
BEGIN
  SELECT * INTO c FROM f360.opening_counts WHERE id = p_count;
  INSERT INTO f360.opening_count_lines (count_id, variant_id)
    SELECT DISTINCT c.id, m.confirmed_variant_id FROM f360.legacy_woo_map m
    WHERE m.target_id = c.target_id AND m.status = 'confirmado'
    ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS n_add = ROW_COUNT;
  UPDATE f360.opening_count_lines l SET in_scope = false WHERE l.count_id = c.id AND l.in_scope
    AND NOT EXISTS (SELECT 1 FROM f360.legacy_woo_map m WHERE m.target_id = c.target_id AND m.status = 'confirmado' AND m.confirmed_variant_id = l.variant_id);
  GET DIAGNOSTICS n_out = ROW_COUNT;
  UPDATE f360.opening_count_lines l SET in_scope = true WHERE l.count_id = c.id AND NOT l.in_scope
    AND EXISTS (SELECT 1 FROM f360.legacy_woo_map m WHERE m.target_id = c.target_id AND m.status = 'confirmado' AND m.confirmed_variant_id = l.variant_id);
  GET DIAGNOSTICS n_back = ROW_COUNT;
  RETURN jsonb_build_object('added', n_add, 'out_of_scope', n_out, 'back_in_scope', n_back);
END $$;

CREATE FUNCTION f360.opening_summary(p_count uuid) RETURNS jsonb LANGUAGE sql STABLE AS $$
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

-- Why the count cannot be approved yet (empty = it can).
CREATE FUNCTION f360.opening_blockers(p_count uuid) RETURNS text[] LANGUAGE sql STABLE AS $$
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

-- ── RPCs ─────────────────────────────────────────────────────────────────────
CREATE FUNCTION public.f360_opening_start(p_target_key text, p_note text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; t f360.sales_targets; l f360.locations; v_id uuid; sc jsonb;
BEGIN
  r := f360.require_role('owner');
  t := f360.target_by_key(p_target_key);                    -- refuses production channels
  SELECT * INTO l FROM f360.locations WHERE id = t.fulfillment_location_id;
  IF l.ledger_authority <> 'f360' OR l.type = 'transit' THEN RAISE EXCEPTION 'La ubicación de origen del canal no admite conteo de apertura.'; END IF;
  IF EXISTS (SELECT 1 FROM f360.opening_counts WHERE location_id = l.id AND status IN ('preliminar', 'congelado')) THEN
    RAISE EXCEPTION 'Ya hay un conteo abierto en %.', l.name;
  END IF;
  INSERT INTO f360.opening_counts (target_id, location_id, started_by_name, note) VALUES (t.id, l.id, r.display_name, nullif(btrim(p_note), ''))
    RETURNING id INTO v_id;
  sc := f360.opening_sync_scope(v_id);
  PERFORM f360.opening_log(v_id, 'start', sc, r);
  RETURN public.f360_opening_state(v_id);
END $$;

CREATE FUNCTION public.f360_opening_refresh_scope(p_count_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; c f360.opening_counts; sc jsonb;
BEGIN
  r := f360.require_role('operator');
  SELECT * INTO c FROM f360.opening_counts WHERE id = p_count_id FOR UPDATE;
  IF c.id IS NULL OR c.status NOT IN ('preliminar', 'congelado') THEN RAISE EXCEPTION 'El conteo no está abierto.'; END IF;
  sc := f360.opening_sync_scope(c.id);
  PERFORM f360.opening_log(c.id, 'refresh_scope', sc, r);
  RETURN public.f360_opening_state(c.id) || jsonb_build_object('scope_change', sc);
END $$;

-- Header + summary + blockers of the current (or a given) count.
CREATE FUNCTION public.f360_opening_state(p_count_id uuid DEFAULT NULL) RETURNS jsonb
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

-- The sheet, grouped model → colour → size. p_view: 'conteo1' | 'conteo2' (blind: hides count 1) | 'reconteo' | 'reporte'.
CREATE FUNCTION public.f360_opening_sheet(p_count_id uuid, p_view text) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; c f360.opening_counts;
BEGIN
  r := f360.require_role('operator');
  IF p_view NOT IN ('conteo1', 'conteo2', 'reconteo', 'reporte') THEN RAISE EXCEPTION 'Vista no válida.'; END IF;
  SELECT * INTO c FROM f360.opening_counts WHERE id = p_count_id;
  IF c.id IS NULL THEN RAISE EXCEPTION 'Conteo no encontrado.'; END IF;
  RETURN jsonb_build_object('view', p_view, 'me', r.display_name, 'models', (
    SELECT coalesce(jsonb_agg(jsonb_build_object('product_id', pm.id, 'model', pm.name, 'colors', pm.colors) ORDER BY pm.name), '[]') FROM (
      SELECT p.id, p.name, jsonb_agg(jsonb_build_object('color', pc.name, 'hex', pc.hex, 'sizes', pc.sizes) ORDER BY pc.sort, pc.name) AS colors
      FROM f360.products p JOIN LATERAL (
        SELECT co.name, co.hex, co.sort, jsonb_agg(jsonb_build_object(
            'variant_id', v.id, 'size', v.size_label, 'sku', v.sku, 'status', l.status, 'in_scope', l.in_scope,
            'woo_variations', (SELECT jsonb_agg(m.woo_variation_id ORDER BY m.woo_variation_id) FROM f360.legacy_woo_map m WHERE m.target_id = c.target_id AND m.confirmed_variant_id = v.id),
            'count1', CASE WHEN p_view = 'conteo2' AND l.count2 IS NULL THEN NULL ELSE l.count1 END,
            'count1_by', CASE WHEN p_view = 'conteo2' AND l.count2 IS NULL THEN NULL ELSE l.count1_by_name END,
            'count1_done', l.count1 IS NOT NULL,
            'count2', CASE WHEN p_view = 'conteo1' AND l.count2 IS NOT NULL AND l.count1 IS NULL THEN NULL ELSE l.count2 END, 'count2_by', l.count2_by_name,
            'recount', l.recount, 'recount_by', l.recount_by_name, 'final_qty', l.final_qty, 'affected', l.affected,
            'woo_managed', l.woo_managed, 'woo_stock', l.woo_stock,
            'difference', CASE WHEN l.final_qty IS NOT NULL AND l.woo_managed THEN l.final_qty - coalesce(l.woo_stock, 0) END)
            ORDER BY ps.sort) AS sizes
        FROM f360.product_colors co JOIN f360.product_variants v ON v.color_id = co.id
        JOIN f360.product_sizes ps ON ps.product_id = v.product_id AND ps.label = v.size_label
        JOIN f360.opening_count_lines l ON l.count_id = c.id AND l.variant_id = v.id
        WHERE co.product_id = p.id AND (l.in_scope OR p_view = 'reporte')
        GROUP BY co.id, co.name, co.hex, co.sort) pc ON true
      GROUP BY p.id, p.name) pm),
    'unlisted', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'description', u.description, 'size', u.size_label, 'quantity', u.quantity,
        'found_by', u.found_by_name, 'found_at', u.found_at, 'status', u.status, 'resolution', u.resolution, 'resolved_by', u.resolved_by_name) ORDER BY u.found_at), '[]')
      FROM f360.opening_count_unlisted u WHERE u.count_id = c.id));
END $$;

-- p_round: '1' | '2' | 're'. p_lines: [{variant_id, qty}]. Writes count rows only — never inventory.
CREATE FUNCTION public.f360_opening_record(p_count_id uuid, p_round text, p_lines jsonb) RETURNS jsonb
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

CREATE FUNCTION public.f360_opening_add_unlisted(p_count_id uuid, p_description text, p_size text, p_quantity int) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; c f360.opening_counts;
BEGIN
  r := f360.require_role('operator');
  SELECT * INTO c FROM f360.opening_counts WHERE id = p_count_id;
  IF c.id IS NULL OR c.status NOT IN ('preliminar', 'congelado') THEN RAISE EXCEPTION 'El conteo no está abierto.'; END IF;
  IF coalesce(length(btrim(p_description)), 0) < 3 THEN RAISE EXCEPTION 'Describe el zapato (modelo y color como lo ves).'; END IF;
  IF p_quantity IS NULL OR p_quantity <= 0 THEN RAISE EXCEPTION 'La cantidad debe ser mayor a cero.'; END IF;
  INSERT INTO f360.opening_count_unlisted (count_id, description, size_label, quantity, found_by_name)
    VALUES (c.id, btrim(p_description), nullif(btrim(p_size), ''), p_quantity, r.display_name);
  PERFORM f360.opening_log(c.id, 'unlisted_add', jsonb_build_object('description', btrim(p_description), 'size', p_size, 'quantity', p_quantity), r);
  RETURN public.f360_opening_state(c.id);
END $$;

CREATE FUNCTION public.f360_opening_resolve_unlisted(p_unlisted_id uuid, p_resolution text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; u f360.opening_count_unlisted;
BEGIN
  r := f360.require_role('owner');
  SELECT * INTO u FROM f360.opening_count_unlisted WHERE id = p_unlisted_id FOR UPDATE;
  IF u.id IS NULL OR u.status <> 'abierto' THEN RAISE EXCEPTION 'Registro no encontrado o ya resuelto.'; END IF;
  IF coalesce(length(btrim(p_resolution)), 0) < 3 THEN RAISE EXCEPTION 'Escribe cómo se resolvió.'; END IF;
  UPDATE f360.opening_count_unlisted SET status = 'resuelto', resolution = btrim(p_resolution), resolved_by_name = r.display_name, resolved_at = clock_timestamp()
    WHERE id = u.id;
  PERFORM f360.opening_log(u.count_id, 'unlisted_resolve', jsonb_build_object('id', u.id, 'resolution', btrim(p_resolution)), r);
  RETURN public.f360_opening_state(u.count_id);
END $$;

-- Start the short freeze window: F360 moves at the location are refused from now on (see location_in_cutover).
CREATE FUNCTION public.f360_opening_freeze(p_count_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; c f360.opening_counts;
BEGIN
  r := f360.require_role('owner');
  SELECT * INTO c FROM f360.opening_counts WHERE id = p_count_id FOR UPDATE;
  IF c.id IS NULL OR c.status <> 'preliminar' THEN RAISE EXCEPTION 'Solo un conteo preliminar se puede congelar.'; END IF;
  UPDATE f360.opening_counts SET status = 'congelado', frozen_by_name = r.display_name, frozen_at = clock_timestamp() WHERE id = c.id;
  PERFORM f360.opening_log(c.id, 'freeze', NULL, r);
  RETURN public.f360_opening_state(c.id);
END $$;

-- Marks every counted size that had Woo sales (legacy order lines on the channel) or F360 movements at the location
-- AFTER its count → 'recontar'. Reads order lines already recorded by the webhook (aggregates only, no customer data).
CREATE FUNCTION public.f360_opening_reconcile(p_count_id uuid) RETURNS jsonb
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

-- Mario's approval: seals the count. Writes NO inventory (the opening balance load is a separate approved step).
CREATE FUNCTION public.f360_opening_approve(p_count_id uuid, p_note text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; c f360.opening_counts; b text[];
BEGIN
  r := f360.require_role('owner');
  SELECT * INTO c FROM f360.opening_counts WHERE id = p_count_id FOR UPDATE;
  IF c.id IS NULL THEN RAISE EXCEPTION 'Conteo no encontrado.'; END IF;
  b := f360.opening_blockers(c.id);
  IF cardinality(b) > 0 THEN RAISE EXCEPTION 'No se puede aprobar: %.', array_to_string(b, '; '); END IF;
  IF coalesce(length(btrim(p_note)), 0) < 3 THEN RAISE EXCEPTION 'Escribe una nota de aprobación.'; END IF;
  UPDATE f360.opening_counts SET status = 'aprobado', approved_by = auth.uid(), approved_by_name = r.display_name, approved_at = clock_timestamp(), approval_note = btrim(p_note)
    WHERE id = c.id;
  PERFORM f360.opening_log(c.id, 'approve', jsonb_build_object('summary', f360.opening_summary(c.id), 'note', btrim(p_note)), r);
  RETURN public.f360_opening_state(c.id);
END $$;

CREATE FUNCTION public.f360_opening_cancel(p_count_id uuid, p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; c f360.opening_counts;
BEGIN
  r := f360.require_role('owner');
  SELECT * INTO c FROM f360.opening_counts WHERE id = p_count_id FOR UPDATE;
  IF c.id IS NULL OR c.status = 'cancelado' THEN RAISE EXCEPTION 'Conteo no encontrado o ya cancelado.'; END IF;
  IF coalesce(length(btrim(p_reason)), 0) < 3 THEN RAISE EXCEPTION 'Escribe el motivo.'; END IF;
  UPDATE f360.opening_counts SET status = 'cancelado', cancelled_by_name = r.display_name, cancelled_at = clock_timestamp(), cancel_reason = btrim(p_reason) WHERE id = c.id;
  PERFORM f360.opening_log(c.id, 'cancel', jsonb_build_object('reason', btrim(p_reason)), r);
  RETURN public.f360_opening_state(c.id);
END $$;

-- Woo reference per variant (service_role; from a read-only GET of the store). Reference only — never the opening balance.
CREATE FUNCTION public.f360_opening_set_woo_reference(p_count_id uuid, p_rows jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE c f360.opening_counts; n int;
BEGIN
  SELECT * INTO c FROM f360.opening_counts WHERE id = p_count_id;
  IF c.id IS NULL THEN RAISE EXCEPTION 'Conteo no encontrado.'; END IF;
  WITH x AS (SELECT * FROM jsonb_to_recordset(p_rows) y(woo_variation_id int, managed boolean, stock int)),
  per AS (SELECT m.confirmed_variant_id AS variant_id, bool_and(coalesce(x.managed, false)) AS managed,
                 CASE WHEN bool_and(coalesce(x.managed, false)) THEN sum(coalesce(x.stock, 0)) END AS stock
          FROM x JOIN f360.legacy_woo_map m ON m.target_id = c.target_id AND m.woo_variation_id = x.woo_variation_id AND m.status = 'confirmado'
          GROUP BY m.confirmed_variant_id)
  UPDATE f360.opening_count_lines l SET woo_managed = per.managed, woo_stock = per.stock FROM per WHERE l.count_id = c.id AND l.variant_id = per.variant_id;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN jsonb_build_object('updated', n);
END $$;

REVOKE ALL ON f360.opening_counts, f360.opening_count_lines, f360.opening_count_unlisted, f360.opening_count_changes FROM PUBLIC, anon, authenticated;
GRANT ALL ON f360.opening_counts, f360.opening_count_lines, f360.opening_count_unlisted, f360.opening_count_changes TO service_role;
GRANT USAGE, SELECT ON SEQUENCE f360.opening_count_changes_id_seq TO service_role;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA f360 FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.f360_opening_start(text, text), public.f360_opening_refresh_scope(uuid), public.f360_opening_state(uuid),
  public.f360_opening_sheet(uuid, text), public.f360_opening_record(uuid, text, jsonb), public.f360_opening_add_unlisted(uuid, text, text, int),
  public.f360_opening_resolve_unlisted(uuid, text), public.f360_opening_freeze(uuid), public.f360_opening_reconcile(uuid),
  public.f360_opening_approve(uuid, text), public.f360_opening_cancel(uuid, text), public.f360_opening_set_woo_reference(uuid, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.f360_opening_start(text, text), public.f360_opening_refresh_scope(uuid), public.f360_opening_state(uuid),
  public.f360_opening_sheet(uuid, text), public.f360_opening_record(uuid, text, jsonb), public.f360_opening_add_unlisted(uuid, text, text, int),
  public.f360_opening_resolve_unlisted(uuid, text), public.f360_opening_freeze(uuid), public.f360_opening_reconcile(uuid),
  public.f360_opening_approve(uuid, text), public.f360_opening_cancel(uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.f360_opening_set_woo_reference(uuid, jsonb) TO service_role;
