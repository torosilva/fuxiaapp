-- Fuxia 360 Track D · D2 — Homologation of the legacy Woo catalog (STAGING). Additive. Decisions: Mario 2026-10-02.
--
--   f360.legacy_woo_map       one row per legacy Woo VARIATION per channel: read-only Woo snapshot + system proposal + human decision
--   f360.legacy_woo_map_log   append-only history of every human decision (confirm / mark / reopen)
--
-- Rules enforced here:
--   * The technical anchor is woo_variation_id. The legacy Woo SKU is stored as REFERENCE ONLY (never identity, never changed).
--   * F360 keeps PRODUCT/MODEL → COLOR → SIZE: several Woo products (one per colour) map to ONE F360 model and different variants.
--   * The system only PROPOSES (f360_legacy_propose, service_role). Only a person confirms (f360_legacy_confirm, operator+).
--   * A human decision is never overwritten by an automatic inference (trigger legacy_woo_map_guard + human_locked).
--   * One F360 variant ↔ at most one Woo variation per channel (unique index), so a sale can never be counted twice.
--   * Nothing here touches inventory, Woo links, stock, prices, Woo or the legacy SKUs. Confirming creates catalog rows only.
-- Rollback: supabase/rollbacks/20261007000100_f360_d2_legacy_homologation.down.sql

CREATE TABLE f360.legacy_woo_map (
  target_id             uuid NOT NULL REFERENCES f360.sales_targets(id) ON DELETE RESTRICT,
  woo_variation_id      integer NOT NULL CHECK (woo_variation_id > 0),
  -- read-only snapshot of Woo (what the store has today; never written back)
  woo_product_id        integer NOT NULL CHECK (woo_product_id > 0),
  woo_product_name      text NOT NULL,
  woo_parent_sku        text,                 -- REFERENCE ONLY. Legacy variations have no SKU of their own (D1 H1).
  woo_category          text,
  woo_size              text,
  woo_color             text,                 -- colour attribute of the variation itself; NULL = "any colour" / colour only in the name
  woo_regular_price     numeric(10,2),
  sold_all              integer NOT NULL DEFAULT 0 CHECK (sold_all >= 0),   -- aggregated Woo sales: context only, NEVER inventory
  sold_90d              integer NOT NULL DEFAULT 0 CHECK (sold_90d >= 0),
  snapshot_at           timestamptz NOT NULL,
  -- system proposal (never applied by itself)
  proposed_model        text,
  proposed_product_id   uuid REFERENCES f360.products(id) ON DELETE RESTRICT,
  proposed_color        text,
  proposed_size         text,
  proposed_status       text CHECK (proposed_status IN ('propuesto', 'requiere_revision', 'sin_correspondencia')),
  confidence            text CHECK (confidence IN ('alta', 'media', 'baja')),
  proposal_reason       text,
  proposed_at           timestamptz,
  -- state shown to Carolina
  status                text NOT NULL DEFAULT 'sin_correspondencia'
                        CHECK (status IN ('propuesto', 'confirmado', 'requiere_revision', 'conflicto', 'sin_correspondencia')),
  human_locked          boolean NOT NULL DEFAULT false,
  confirmed_variant_id  uuid REFERENCES f360.product_variants(id) ON DELETE RESTRICT,
  decided_by            uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  decided_by_name       text,
  decided_at            timestamptz,
  note                  text,
  PRIMARY KEY (target_id, woo_variation_id),
  CHECK ((status = 'confirmado') = (confirmed_variant_id IS NOT NULL)),
  CHECK (status <> 'confirmado' OR human_locked)
);
CREATE UNIQUE INDEX legacy_woo_map_variant_key ON f360.legacy_woo_map (target_id, confirmed_variant_id) WHERE confirmed_variant_id IS NOT NULL;
CREATE INDEX legacy_woo_map_product_idx ON f360.legacy_woo_map (target_id, woo_product_id);

CREATE TABLE f360.legacy_woo_map_log (
  id                  bigserial PRIMARY KEY,
  target_id           uuid NOT NULL REFERENCES f360.sales_targets(id) ON DELETE RESTRICT,
  woo_variation_id    integer NOT NULL,
  action              text NOT NULL CHECK (action IN ('confirm', 'mark', 'reopen')),
  from_status         text,
  to_status           text NOT NULL,
  variant_id          uuid,
  actor_auth_user_id  uuid,
  actor_name          text NOT NULL,
  note                text,
  at                  timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX legacy_woo_map_log_idx ON f360.legacy_woo_map_log (target_id, woo_variation_id, at);

CREATE FUNCTION f360.legacy_log_append_only() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'El historial de homologación no se puede modificar.';
END $$;
CREATE TRIGGER legacy_woo_map_log_append_only BEFORE UPDATE OR DELETE ON f360.legacy_woo_map_log
  FOR EACH ROW EXECUTE FUNCTION f360.legacy_log_append_only();

-- A human decision is final for the machine: an automatic process (f360.legacy_actor = 'system') can never change the
-- decision fields of a human_locked row, human_locked can never go back to false, and rows are never deleted.
CREATE FUNCTION f360.legacy_woo_map_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'Una fila de homologación no se borra; se reabre o se marca.'; END IF;
  IF OLD.human_locked AND NOT NEW.human_locked THEN
    RAISE EXCEPTION 'Una decisión de una persona no se puede desmarcar (variación %).', OLD.woo_variation_id;
  END IF;
  IF OLD.human_locked AND coalesce(current_setting('f360.legacy_actor', true), '') <> 'human'
     AND (NEW.status, NEW.confirmed_variant_id, NEW.proposed_model, NEW.proposed_product_id, NEW.proposed_color, NEW.proposed_size, NEW.proposed_status)
         IS DISTINCT FROM (OLD.status, OLD.confirmed_variant_id, OLD.proposed_model, OLD.proposed_product_id, OLD.proposed_color, OLD.proposed_size, OLD.proposed_status) THEN
    RAISE EXCEPTION 'Una inferencia automática no puede cambiar una decisión de una persona (variación %).', OLD.woo_variation_id;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER legacy_woo_map_guard BEFORE UPDATE OR DELETE ON f360.legacy_woo_map
  FOR EACH ROW EXECUTE FUNCTION f360.legacy_woo_map_guard();

-- Status of the rows that are NOT human-locked = their proposal, or 'conflicto' when two rows would land on the same
-- F360 model + colour + size (between proposals, or a proposal against a confirmed variant). Human rows are never touched.
CREATE FUNCTION f360.legacy_refresh_status(p_target uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('f360.legacy_actor', 'system', true);
  WITH k AS (
    SELECT m.woo_variation_id,
      CASE WHEN m.status = 'confirmado' THEN f360.norm(p.name) || '|' || f360.norm(c.name) || '|' || f360.norm(v.size_label)
           WHEN NOT m.human_locked AND m.proposed_color IS NOT NULL AND m.proposed_size IS NOT NULL AND coalesce(pp.name, m.proposed_model) IS NOT NULL
             THEN f360.norm(coalesce(pp.name, m.proposed_model)) || '|' || f360.norm(m.proposed_color) || '|' || f360.norm(m.proposed_size) END AS key
    FROM f360.legacy_woo_map m
    LEFT JOIN f360.product_variants v ON v.id = m.confirmed_variant_id
    LEFT JOIN f360.products p ON p.id = v.product_id
    LEFT JOIN f360.product_colors c ON c.id = v.color_id
    LEFT JOIN f360.products pp ON pp.id = m.proposed_product_id
    WHERE m.target_id = p_target
  ), dup AS (SELECT key FROM k WHERE key IS NOT NULL GROUP BY key HAVING count(*) > 1),
  want AS (
    SELECT m.woo_variation_id, CASE WHEN k.key IN (SELECT key FROM dup) THEN 'conflicto' ELSE m.proposed_status END AS st
    FROM f360.legacy_woo_map m JOIN k ON k.woo_variation_id = m.woo_variation_id
    WHERE m.target_id = p_target AND NOT m.human_locked AND m.proposed_status IS NOT NULL
  )
  UPDATE f360.legacy_woo_map m SET status = want.st FROM want
  WHERE m.target_id = p_target AND m.woo_variation_id = want.woo_variation_id AND m.status IS DISTINCT FROM want.st;
END $$;

CREATE FUNCTION f360.legacy_summary(p_target uuid) RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object(
    'variations', count(*),
    'woo_products', count(DISTINCT m.woo_product_id),
    'propuesto', count(*) FILTER (WHERE m.status = 'propuesto'),
    'confirmado', count(*) FILTER (WHERE m.status = 'confirmado'),
    'requiere_revision', count(*) FILTER (WHERE m.status = 'requiere_revision'),
    'conflicto', count(*) FILTER (WHERE m.status = 'conflicto'),
    'sin_correspondencia', count(*) FILTER (WHERE m.status = 'sin_correspondencia'),
    'models_proposed', count(DISTINCT f360.norm(coalesce(pp.name, m.proposed_model))) FILTER (WHERE coalesce(pp.name, m.proposed_model) IS NOT NULL),
    'models_confirmed', count(DISTINCT v.product_id),
    'coverage_pct', CASE WHEN count(*) = 0 THEN 0 ELSE round(100.0 * count(*) FILTER (WHERE m.status = 'confirmado') / count(*), 1) END,
    'snapshot_at', max(m.snapshot_at))
  FROM f360.legacy_woo_map m
  LEFT JOIN f360.products pp ON pp.id = m.proposed_product_id
  LEFT JOIN f360.product_variants v ON v.id = m.confirmed_variant_id
  WHERE m.target_id = p_target
$$;

-- ── System side (service_role only) ─────────────────────────────────────────
-- Loads / refreshes the read-only Woo snapshot. A variation whose product, size or colour changed in Woo is refused:
-- it needs a person, not a silent update.
CREATE FUNCTION public.f360_legacy_load_snapshot(p_target_key text, p_rows jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE t f360.sales_targets; x jsonb; o f360.legacy_woo_map; n_new int := 0; n_upd int := 0;
BEGIN
  t := f360.target_by_key(p_target_key);   -- refuses production targets
  PERFORM set_config('f360.legacy_actor', 'system', true);
  FOR x IN SELECT * FROM jsonb_array_elements(coalesce(p_rows, '[]')) LOOP
    SELECT * INTO o FROM f360.legacy_woo_map WHERE target_id = t.id AND woo_variation_id = (x->>'woo_variation_id')::int FOR UPDATE;
    IF o.woo_variation_id IS NULL THEN
      INSERT INTO f360.legacy_woo_map (target_id, woo_variation_id, woo_product_id, woo_product_name, woo_parent_sku, woo_category,
          woo_size, woo_color, woo_regular_price, sold_all, sold_90d, snapshot_at)
        VALUES (t.id, (x->>'woo_variation_id')::int, (x->>'woo_product_id')::int, x->>'woo_product_name', nullif(x->>'woo_parent_sku', ''),
          nullif(x->>'woo_category', ''), nullif(btrim(x->>'woo_size'), ''), nullif(btrim(x->>'woo_color'), ''),
          nullif(x->>'woo_regular_price', '')::numeric, coalesce((x->>'sold_all')::int, 0), coalesce((x->>'sold_90d')::int, 0),
          coalesce((x->>'snapshot_at')::timestamptz, now()));
      n_new := n_new + 1;
    ELSE
      IF o.woo_product_id <> (x->>'woo_product_id')::int OR f360.norm(o.woo_size) IS DISTINCT FROM f360.norm(x->>'woo_size')
         OR f360.norm(o.woo_color) IS DISTINCT FROM f360.norm(x->>'woo_color') THEN
        RAISE EXCEPTION 'La variación Woo % cambió de producto, talla o color desde la última lectura: requiere revisión humana.', o.woo_variation_id;
      END IF;
      UPDATE f360.legacy_woo_map SET woo_product_name = x->>'woo_product_name', woo_parent_sku = nullif(x->>'woo_parent_sku', ''),
          woo_category = nullif(x->>'woo_category', ''), woo_regular_price = nullif(x->>'woo_regular_price', '')::numeric,
          sold_all = coalesce((x->>'sold_all')::int, 0), sold_90d = coalesce((x->>'sold_90d')::int, 0),
          snapshot_at = coalesce((x->>'snapshot_at')::timestamptz, now())
        WHERE target_id = t.id AND woo_variation_id = o.woo_variation_id;
      n_upd := n_upd + 1;
    END IF;
  END LOOP;
  RETURN jsonb_build_object('new', n_new, 'updated', n_upd, 'summary', f360.legacy_summary(t.id));
END $$;

-- p_rows: [{woo_variation_id, model, product_id, color, size, confidence, reason, status}]. Rows decided by a person are skipped.
CREATE FUNCTION public.f360_legacy_propose(p_target_key text, p_rows jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE t f360.sales_targets; n int; skipped int;
BEGIN
  t := f360.target_by_key(p_target_key);
  PERFORM set_config('f360.legacy_actor', 'system', true);
  IF EXISTS (SELECT 1 FROM jsonb_to_recordset(coalesce(p_rows, '[]')) x(status text) WHERE x.status NOT IN ('propuesto', 'requiere_revision', 'sin_correspondencia')) THEN
    RAISE EXCEPTION 'Una propuesta solo puede ser propuesto, requiere_revision o sin_correspondencia.';
  END IF;
  SELECT count(*) INTO skipped FROM jsonb_to_recordset(coalesce(p_rows, '[]')) x(woo_variation_id int)
    JOIN f360.legacy_woo_map m ON m.target_id = t.id AND m.woo_variation_id = x.woo_variation_id AND m.human_locked;
  UPDATE f360.legacy_woo_map m SET proposed_model = nullif(btrim(x.model), ''), proposed_product_id = x.product_id,
      proposed_color = nullif(btrim(x.color), ''), proposed_size = nullif(btrim(x.size), ''), confidence = x.confidence,
      proposal_reason = x.reason, proposed_status = x.status, proposed_at = now()
    FROM jsonb_to_recordset(coalesce(p_rows, '[]')) AS x(woo_variation_id int, model text, product_id uuid, color text, size text, confidence text, reason text, status text)
    WHERE m.target_id = t.id AND m.woo_variation_id = x.woo_variation_id AND NOT m.human_locked;
  GET DIAGNOSTICS n = ROW_COUNT;
  PERFORM f360.legacy_refresh_status(t.id);
  RETURN jsonb_build_object('proposed', n, 'skipped_human', skipped, 'summary', f360.legacy_summary(t.id));
END $$;

-- ── Carolina's side (operator+) ─────────────────────────────────────────────
CREATE FUNCTION public.f360_legacy_homologation(p_target_key text DEFAULT 'woo_staging4') RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; t f360.sales_targets;
BEGIN
  r := f360.require_role('operator');
  t := f360.target_by_key(p_target_key);
  RETURN jsonb_build_object(
    'target', jsonb_build_object('key', t.key, 'name', t.name, 'is_production', t.is_production),
    'can_edit', true,
    'summary', f360.legacy_summary(t.id),
    'categories', (SELECT coalesce(jsonb_agg(jsonb_build_object('key', key, 'name', name) ORDER BY sort), '[]') FROM f360.categories),
    'models', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name, 'category_key', p.category_key,
        'published', EXISTS (SELECT 1 FROM f360.woo_product_links pl WHERE pl.product_id = p.id),
        'colors', (SELECT coalesce(jsonb_agg(c.name ORDER BY c.sort, c.created_at), '[]') FROM f360.product_colors c WHERE c.product_id = p.id))
        ORDER BY p.name), '[]') FROM f360.products p WHERE p.status = 'active'),
    'rows', (SELECT coalesce(jsonb_agg(jsonb_build_object(
        'woo_variation_id', m.woo_variation_id, 'woo_product_id', m.woo_product_id, 'woo_product_name', m.woo_product_name,
        'woo_parent_sku', m.woo_parent_sku, 'woo_category', m.woo_category, 'woo_size', m.woo_size, 'woo_color', m.woo_color,
        'woo_regular_price', m.woo_regular_price, 'sold_all', m.sold_all, 'sold_90d', m.sold_90d,
        'proposed_model', coalesce(pp.name, m.proposed_model), 'proposed_product_id', m.proposed_product_id, 'proposed_color', m.proposed_color,
        'proposed_size', m.proposed_size, 'confidence', m.confidence, 'proposal_reason', m.proposal_reason,
        'status', m.status, 'human_locked', m.human_locked, 'note', m.note, 'decided_by_name', m.decided_by_name, 'decided_at', m.decided_at,
        'confirmed', CASE WHEN v.id IS NULL THEN NULL ELSE jsonb_build_object('variant_id', v.id, 'product_id', p.id, 'product_name', p.name,
          'color', c.name, 'size', v.size_label, 'sku', v.sku) END)
        ORDER BY m.woo_product_name, m.woo_product_id, m.woo_color NULLS FIRST, m.woo_size), '[]')
      FROM f360.legacy_woo_map m
      LEFT JOIN f360.products pp ON pp.id = m.proposed_product_id
      LEFT JOIN f360.product_variants v ON v.id = m.confirmed_variant_id
      LEFT JOIN f360.products p ON p.id = v.product_id
      LEFT JOIN f360.product_colors c ON c.id = v.color_id
      WHERE m.target_id = t.id));
END $$;

-- Confirms a set of Woo variations (usually one Woo product = one colour) as MODEL + COLOUR, one variant per size.
-- Model: an existing F360 product (p_product_id) or a new one (p_new_model_name). Colour and variants are created if missing.
-- Creates catalog rows only: no inventory, no Woo link, no stock, no price, nothing in Woo.
CREATE FUNCTION public.f360_legacy_confirm(p_target_key text, p_variation_ids integer[], p_product_id uuid, p_new_model_name text,
  p_category_key text, p_color_name text, p_note text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; t f360.sales_targets; v_ids integer[]; v_pid uuid; v_name text; v_color uuid; v_cname text := btrim(p_color_name);
  m f360.legacy_woo_map; v_var uuid; v_other text; v_size text; n int := 0;
BEGIN
  r := f360.require_role('operator');
  t := f360.target_by_key(p_target_key);
  PERFORM set_config('f360.legacy_actor', 'human', true);
  v_ids := ARRAY(SELECT DISTINCT unnest(p_variation_ids));
  IF cardinality(v_ids) = 0 THEN RAISE EXCEPTION 'Elige al menos una variación.'; END IF;
  IF coalesce(v_cname, '') = '' THEN RAISE EXCEPTION 'Escribe el color F360.'; END IF;
  PERFORM 1 FROM f360.legacy_woo_map WHERE target_id = t.id AND woo_variation_id = ANY (v_ids) ORDER BY woo_variation_id FOR UPDATE;
  IF (SELECT count(*) FROM f360.legacy_woo_map WHERE target_id = t.id AND woo_variation_id = ANY (v_ids)) <> cardinality(v_ids) THEN
    RAISE EXCEPTION 'Alguna variación no está en el catálogo leído de Woo.';
  END IF;
  SELECT * INTO m FROM f360.legacy_woo_map WHERE target_id = t.id AND woo_variation_id = ANY (v_ids) AND status = 'confirmado' LIMIT 1;
  IF m.woo_variation_id IS NOT NULL THEN
    RAISE EXCEPTION 'La variación % (%, talla %) ya está confirmada. Reábrela primero si quieres cambiarla.', m.woo_variation_id, m.woo_product_name, m.woo_size;
  END IF;
  SELECT * INTO m FROM f360.legacy_woo_map WHERE target_id = t.id AND woo_variation_id = ANY (v_ids) AND woo_size IS NULL LIMIT 1;
  IF m.woo_variation_id IS NOT NULL THEN RAISE EXCEPTION 'La variación % no tiene talla en Woo: no se puede homologar.', m.woo_variation_id; END IF;
  SELECT woo_size INTO v_size FROM f360.legacy_woo_map WHERE target_id = t.id AND woo_variation_id = ANY (v_ids) GROUP BY woo_size HAVING count(*) > 1 LIMIT 1;
  IF v_size IS NOT NULL THEN
    RAISE EXCEPTION 'Dos variaciones elegidas tienen la talla %. Una variante F360 es un color y una talla: confírmalas por separado.', v_size;
  END IF;

  IF p_product_id IS NOT NULL THEN
    SELECT id INTO v_pid FROM f360.products WHERE id = p_product_id AND status = 'active';
    IF v_pid IS NULL THEN RAISE EXCEPTION 'Modelo F360 no encontrado.'; END IF;
    IF EXISTS (SELECT 1 FROM f360.woo_product_links WHERE product_id = v_pid) THEN
      RAISE EXCEPTION 'Este modelo ya se publica desde Fuxia 360 como producto nuevo; no se mezcla con productos Woo anteriores.';
    END IF;
  ELSE
    v_name := btrim(p_new_model_name);
    IF coalesce(v_name, '') = '' THEN RAISE EXCEPTION 'Escribe el nombre del modelo o elige uno existente.'; END IF;
    IF EXISTS (SELECT 1 FROM f360.products WHERE slug = f360.slugify(v_name)) THEN
      RAISE EXCEPTION 'Ya existe un modelo llamado "%". Elígelo de la lista.', v_name;
    END IF;
    IF p_category_key IS NOT NULL AND NOT EXISTS (SELECT 1 FROM f360.categories WHERE key = p_category_key) THEN
      RAISE EXCEPTION 'Elige una categoría válida.';
    END IF;
    INSERT INTO f360.products (name, slug, code, category_key, created_by)
      VALUES (v_name, f360.slugify(v_name), f360.next_code(f360.code_from(v_name), ARRAY(SELECT code FROM f360.products)), p_category_key, auth.uid())
      RETURNING id INTO v_pid;
  END IF;

  -- sizes the model does not have yet (Woo labels kept as they are: 35 … 40)
  INSERT INTO f360.product_sizes (product_id, label, sort)
    SELECT v_pid, s.label, (SELECT coalesce(max(sort), 0) FROM f360.product_sizes WHERE product_id = v_pid) + row_number() OVER (ORDER BY s.n NULLS LAST, s.label)
    FROM (SELECT DISTINCT woo_size AS label, CASE WHEN woo_size ~ '^\d+(\.\d+)?$' THEN woo_size::numeric END AS n
          FROM f360.legacy_woo_map WHERE target_id = t.id AND woo_variation_id = ANY (v_ids)) s
    WHERE NOT EXISTS (SELECT 1 FROM f360.product_sizes ps WHERE ps.product_id = v_pid AND ps.label = s.label);

  SELECT id INTO v_color FROM f360.product_colors WHERE product_id = v_pid AND lower(name) = lower(v_cname);
  IF v_color IS NULL THEN
    INSERT INTO f360.product_colors (product_id, name, code, sort)
      VALUES (v_pid, v_cname, f360.next_code(f360.code_from(v_cname), ARRAY(SELECT code FROM f360.product_colors WHERE product_id = v_pid)),
              (SELECT coalesce(max(sort), 0) + 1 FROM f360.product_colors WHERE product_id = v_pid))
      RETURNING id INTO v_color;
  END IF;

  FOR m IN SELECT * FROM f360.legacy_woo_map WHERE target_id = t.id AND woo_variation_id = ANY (v_ids) ORDER BY woo_variation_id LOOP
    SELECT id INTO v_var FROM f360.product_variants WHERE color_id = v_color AND size_label = m.woo_size;
    IF v_var IS NULL THEN
      INSERT INTO f360.product_variants (product_id, color_id, size_label) VALUES (v_pid, v_color, m.woo_size) RETURNING id INTO v_var;
    END IF;
    SELECT format('"%s" (variación %s)', woo_product_name, woo_variation_id) INTO v_other
      FROM f360.legacy_woo_map WHERE target_id = t.id AND confirmed_variant_id = v_var;
    IF v_other IS NOT NULL THEN
      RAISE EXCEPTION 'Conflicto: % / % / talla % ya está confirmada para %. Revisa cuál es la correcta.',
        (SELECT name FROM f360.products WHERE id = v_pid), v_cname, m.woo_size, v_other;
    END IF;
    UPDATE f360.legacy_woo_map SET status = 'confirmado', human_locked = true, confirmed_variant_id = v_var,
        decided_by = auth.uid(), decided_by_name = r.display_name, decided_at = now(), note = coalesce(nullif(btrim(p_note), ''), note)
      WHERE target_id = t.id AND woo_variation_id = m.woo_variation_id;
    INSERT INTO f360.legacy_woo_map_log (target_id, woo_variation_id, action, from_status, to_status, variant_id, actor_auth_user_id, actor_name, note)
      VALUES (t.id, m.woo_variation_id, 'confirm', m.status, 'confirmado', v_var, auth.uid(), r.display_name, nullif(btrim(p_note), ''));
    n := n + 1;
  END LOOP;

  PERFORM f360.refresh_skus(v_pid);                       -- F360 SKU for the new variants; legacy Woo SKUs are untouched
  UPDATE f360.products SET updated_at = now() WHERE id = v_pid;
  PERFORM f360.legacy_refresh_status(t.id);
  RETURN jsonb_build_object('product_id', v_pid, 'confirmed', n, 'summary', f360.legacy_summary(t.id));
END $$;

-- A person marks variations as "requiere revisión" (e.g. colour cannot be determined: blocked for cutover) or
-- "sin correspondencia" (no F360 counterpart). Locks them against automatic proposals.
CREATE FUNCTION public.f360_legacy_mark(p_target_key text, p_variation_ids integer[], p_status text, p_note text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; t f360.sales_targets; m f360.legacy_woo_map; n int := 0;
BEGIN
  r := f360.require_role('operator');
  t := f360.target_by_key(p_target_key);
  PERFORM set_config('f360.legacy_actor', 'human', true);
  IF p_status NOT IN ('requiere_revision', 'sin_correspondencia') THEN RAISE EXCEPTION 'Estado no válido.'; END IF;
  IF coalesce(btrim(p_note), '') = '' THEN RAISE EXCEPTION 'Escribe el motivo.'; END IF;
  FOR m IN SELECT * FROM f360.legacy_woo_map WHERE target_id = t.id AND woo_variation_id = ANY (p_variation_ids) ORDER BY woo_variation_id FOR UPDATE LOOP
    IF m.status = 'confirmado' THEN RAISE EXCEPTION 'La variación % está confirmada: reábrela primero.', m.woo_variation_id; END IF;
    UPDATE f360.legacy_woo_map SET status = p_status, human_locked = true, decided_by = auth.uid(), decided_by_name = r.display_name,
        decided_at = now(), note = btrim(p_note)
      WHERE target_id = t.id AND woo_variation_id = m.woo_variation_id;
    INSERT INTO f360.legacy_woo_map_log (target_id, woo_variation_id, action, from_status, to_status, actor_auth_user_id, actor_name, note)
      VALUES (t.id, m.woo_variation_id, 'mark', m.status, p_status, auth.uid(), r.display_name, btrim(p_note));
    n := n + 1;
  END LOOP;
  IF n = 0 THEN RAISE EXCEPTION 'Elige al menos una variación.'; END IF;
  PERFORM f360.legacy_refresh_status(t.id);
  RETURN jsonb_build_object('marked', n, 'summary', f360.legacy_summary(t.id));
END $$;

-- Undo a confirmation (reason required). The row goes back to "requiere revisión" and stays human-locked: the machine
-- will not re-propose over it. The F360 catalog rows created stay (nothing is deleted).
CREATE FUNCTION public.f360_legacy_reopen(p_target_key text, p_variation_ids integer[], p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; t f360.sales_targets; m f360.legacy_woo_map; n int := 0;
BEGIN
  r := f360.require_role('operator');
  t := f360.target_by_key(p_target_key);
  PERFORM set_config('f360.legacy_actor', 'human', true);
  IF coalesce(btrim(p_reason), '') = '' THEN RAISE EXCEPTION 'Escribe por qué se reabre.'; END IF;
  FOR m IN SELECT * FROM f360.legacy_woo_map WHERE target_id = t.id AND woo_variation_id = ANY (p_variation_ids) ORDER BY woo_variation_id FOR UPDATE LOOP
    IF m.status <> 'confirmado' THEN CONTINUE; END IF;
    IF EXISTS (SELECT 1 FROM f360.woo_variant_links WHERE target_id = t.id AND woo_variation_id = m.woo_variation_id) THEN
      RAISE EXCEPTION 'La variación % ya está ligada al canal; no se puede reabrir en homologación.', m.woo_variation_id;
    END IF;
    UPDATE f360.legacy_woo_map SET status = 'requiere_revision', confirmed_variant_id = NULL, decided_by = auth.uid(),
        decided_by_name = r.display_name, decided_at = now(), note = btrim(p_reason)
      WHERE target_id = t.id AND woo_variation_id = m.woo_variation_id;
    INSERT INTO f360.legacy_woo_map_log (target_id, woo_variation_id, action, from_status, to_status, variant_id, actor_auth_user_id, actor_name, note)
      VALUES (t.id, m.woo_variation_id, 'reopen', 'confirmado', 'requiere_revision', m.confirmed_variant_id, auth.uid(), r.display_name, btrim(p_reason));
    n := n + 1;
  END LOOP;
  IF n = 0 THEN RAISE EXCEPTION 'Ninguna de esas variaciones estaba confirmada.'; END IF;
  PERFORM f360.legacy_refresh_status(t.id);
  RETURN jsonb_build_object('reopened', n, 'summary', f360.legacy_summary(t.id));
END $$;

REVOKE ALL ON f360.legacy_woo_map, f360.legacy_woo_map_log FROM PUBLIC, anon, authenticated;
REVOKE ALL ON SEQUENCE f360.legacy_woo_map_log_id_seq FROM PUBLIC, anon, authenticated;
GRANT ALL ON f360.legacy_woo_map, f360.legacy_woo_map_log TO service_role;
GRANT USAGE, SELECT ON SEQUENCE f360.legacy_woo_map_log_id_seq TO service_role;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA f360 FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.f360_legacy_load_snapshot(text, jsonb), public.f360_legacy_propose(text, jsonb),
  public.f360_legacy_homologation(text), public.f360_legacy_confirm(text, integer[], uuid, text, text, text, text),
  public.f360_legacy_mark(text, integer[], text, text), public.f360_legacy_reopen(text, integer[], text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.f360_legacy_load_snapshot(text, jsonb), public.f360_legacy_propose(text, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.f360_legacy_homologation(text), public.f360_legacy_confirm(text, integer[], uuid, text, text, text, text),
  public.f360_legacy_mark(text, integer[], text, text), public.f360_legacy_reopen(text, integer[], text) TO authenticated, service_role;
