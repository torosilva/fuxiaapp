-- Fuxia 360 Track C · C2 — Catalog mapping / migration preparation. STAGING. Additive, READ-ONLY on the legacy
-- inventory (public.channel_inventory is never written). Nothing moves stock; nothing switches a location.
--
--   f360.legacy_inventory_map   one row per legacy channel_inventory row: snapshot + proposed F360 variant + human review
--   f360_propose_legacy_mapping(location)       proposes matches (exact SKU, or model+color+size) — never auto-confirms
--   f360_review_legacy_mapping(row, decision)   a person confirms / discards / reopens
--   f360_location_migration_readiness(location) D-M1 gate: every product physically there must be mapped before C3
-- The legacy stock numbers are a SNAPSHOT for review only; the C3 opening balance comes from a physical count.
-- Rollback: supabase/rollbacks/20260930000200_f360_c2_legacy_mapping.down.sql

CREATE TABLE f360.legacy_inventory_map (
  channel_inventory_id  uuid PRIMARY KEY,                    -- no FK: legacy rows can be deleted; the snapshot survives
  location_id           uuid NOT NULL REFERENCES f360.locations(id) ON DELETE RESTRICT,
  channel_id            uuid NOT NULL,
  snap_product_name     text, snap_size text, snap_color text, snap_sku text, snap_price numeric(10,2),
  snap_stock            integer, snap_sold integer,
  snap_units            integer GENERATED ALWAYS AS (greatest(coalesce(snap_stock, 0) - coalesce(snap_sold, 0), 0)) STORED,
  snapshot_at           timestamptz NOT NULL DEFAULT now(),
  proposed_variant_id   uuid REFERENCES f360.product_variants(id) ON DELETE RESTRICT,
  proposal_reason       text,                                -- sku | modelo+color+talla
  candidates            integer NOT NULL DEFAULT 0,
  status                text NOT NULL DEFAULT 'sin_coincidencia'
                        CHECK (status IN ('propuesto', 'ambiguo', 'sin_coincidencia', 'confirmado', 'descartado')),
  confirmed_variant_id  uuid REFERENCES f360.product_variants(id) ON DELETE RESTRICT,
  reviewed_by_name      text, reviewed_at timestamptz, note text,
  CHECK (status <> 'confirmado' OR confirmed_variant_id IS NOT NULL)
);
CREATE INDEX legacy_inventory_map_location_idx ON f360.legacy_inventory_map (location_id, status);

CREATE FUNCTION f360.norm(p text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT nullif(regexp_replace(lower(translate(btrim(coalesce(p, '')),
    'áàäâãéèëêíìïîóòöôõúùüûñçÁÀÄÂÃÉÈËÊÍÌÏÎÓÒÖÔÕÚÙÜÛÑÇ', 'aaaaaeeeeiiiiooooouuuuncAAAAAEEEEIIIIOOOOOUUUUNC')), '\s+', ' ', 'g'), '')
$$;
CREATE FUNCTION f360.norm_size(p text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT nullif(regexp_replace(regexp_replace(lower(coalesce(p, '')), '(talla|t\.|mx|col)', '', 'g'), '[^0-9.,]', '', 'g'), '')
$$;

CREATE FUNCTION public.f360_propose_legacy_mapping(p_location_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; l f360.locations; ci record; v_cands uuid[]; v_reason text; n int := 0;
BEGIN
  r := f360.require_role('operator');
  SELECT * INTO l FROM f360.locations WHERE id = p_location_id AND status = 'active';
  IF l.id IS NULL OR l.legacy_channel_id IS NULL THEN RAISE EXCEPTION 'Esta ubicación no está ligada a una tienda/bazar del sistema anterior.'; END IF;
  FOR ci IN SELECT * FROM public.channel_inventory WHERE channel_id = l.legacy_channel_id LOOP   -- READ ONLY
    v_cands := NULL; v_reason := NULL;
    IF nullif(btrim(ci.sku), '') IS NOT NULL THEN
      SELECT array_agg(v.id) INTO v_cands FROM f360.product_variants v WHERE v.status = 'active' AND upper(v.sku) = upper(btrim(ci.sku));
      IF v_cands IS NOT NULL THEN v_reason := 'sku'; END IF;
    END IF;
    IF v_cands IS NULL THEN
      SELECT array_agg(v.id) INTO v_cands FROM f360.product_variants v
        JOIN f360.products p ON p.id = v.product_id JOIN f360.product_colors c ON c.id = v.color_id
        WHERE v.status = 'active' AND f360.norm(p.name) = f360.norm(ci.product_name)
          AND f360.norm(c.name) = f360.norm(ci.color) AND f360.norm_size(v.size_label) = f360.norm_size(ci.size);
      IF v_cands IS NOT NULL THEN v_reason := 'modelo+color+talla'; END IF;
    END IF;
    INSERT INTO f360.legacy_inventory_map (channel_inventory_id, location_id, channel_id, snap_product_name, snap_size, snap_color, snap_sku,
        snap_price, snap_stock, snap_sold, snapshot_at, proposed_variant_id, proposal_reason, candidates, status)
      VALUES (ci.id, l.id, l.legacy_channel_id, ci.product_name, ci.size, ci.color, ci.sku, ci.price, ci.stock, ci.sold, now(),
        CASE WHEN cardinality(v_cands) = 1 THEN v_cands[1] END, v_reason, coalesce(cardinality(v_cands), 0),
        CASE WHEN v_cands IS NULL THEN 'sin_coincidencia' WHEN cardinality(v_cands) = 1 THEN 'propuesto' ELSE 'ambiguo' END)
      ON CONFLICT (channel_inventory_id) DO UPDATE SET
        snap_product_name = EXCLUDED.snap_product_name, snap_size = EXCLUDED.snap_size, snap_color = EXCLUDED.snap_color, snap_sku = EXCLUDED.snap_sku,
        snap_price = EXCLUDED.snap_price, snap_stock = EXCLUDED.snap_stock, snap_sold = EXCLUDED.snap_sold, snapshot_at = now(),
        -- human decisions are never overwritten by a new proposal
        proposed_variant_id = CASE WHEN f360.legacy_inventory_map.status IN ('confirmado', 'descartado') THEN f360.legacy_inventory_map.proposed_variant_id ELSE EXCLUDED.proposed_variant_id END,
        proposal_reason = CASE WHEN f360.legacy_inventory_map.status IN ('confirmado', 'descartado') THEN f360.legacy_inventory_map.proposal_reason ELSE EXCLUDED.proposal_reason END,
        candidates = EXCLUDED.candidates,
        status = CASE WHEN f360.legacy_inventory_map.status IN ('confirmado', 'descartado') THEN f360.legacy_inventory_map.status ELSE EXCLUDED.status END;
    n := n + 1;
  END LOOP;
  INSERT INTO f360.access_changes (what, subject, after, by_name, by_user) VALUES ('legacy_mapping_proposal', l.id::text, jsonb_build_object('rows', n), r.display_name, r.auth_user_id);
  RETURN public.f360_location_migration_readiness(p_location_id);
END $$;

-- decision: confirmar (needs a variant: the proposed one or p_variant_id) | descartar (only rows with 0 units, D-M1) | reabrir
CREATE FUNCTION public.f360_review_legacy_mapping(p_channel_inventory_id uuid, p_decision text, p_variant_id uuid DEFAULT NULL, p_note text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; m f360.legacy_inventory_map; v uuid;
BEGIN
  r := f360.require_role('operator');
  SELECT * INTO m FROM f360.legacy_inventory_map WHERE channel_inventory_id = p_channel_inventory_id FOR UPDATE;
  IF m.channel_inventory_id IS NULL THEN RAISE EXCEPTION 'Fila no encontrada.'; END IF;
  IF p_decision = 'confirmar' THEN
    v := coalesce(p_variant_id, m.proposed_variant_id);
    IF v IS NULL OR NOT EXISTS (SELECT 1 FROM f360.product_variants WHERE id = v AND status = 'active') THEN RAISE EXCEPTION 'Elige a qué variante de Fuxia 360 corresponde.'; END IF;
    UPDATE f360.legacy_inventory_map SET status = 'confirmado', confirmed_variant_id = v, reviewed_by_name = r.display_name, reviewed_at = now(), note = nullif(btrim(p_note), '')
      WHERE channel_inventory_id = m.channel_inventory_id RETURNING * INTO m;
  ELSIF p_decision = 'descartar' THEN
    IF m.snap_units > 0 THEN RAISE EXCEPTION 'No se puede descartar un producto con existencias: primero debe existir en Fuxia 360 (D-M1).'; END IF;
    IF coalesce(btrim(p_note), '') = '' THEN RAISE EXCEPTION 'Explica por qué se descarta.'; END IF;
    UPDATE f360.legacy_inventory_map SET status = 'descartado', confirmed_variant_id = NULL, reviewed_by_name = r.display_name, reviewed_at = now(), note = btrim(p_note)
      WHERE channel_inventory_id = m.channel_inventory_id RETURNING * INTO m;
  ELSIF p_decision = 'reabrir' THEN
    UPDATE f360.legacy_inventory_map SET status = CASE WHEN proposed_variant_id IS NOT NULL THEN 'propuesto' WHEN candidates > 1 THEN 'ambiguo' ELSE 'sin_coincidencia' END,
      confirmed_variant_id = NULL, reviewed_by_name = r.display_name, reviewed_at = now(), note = nullif(btrim(p_note), '')
      WHERE channel_inventory_id = m.channel_inventory_id RETURNING * INTO m;
  ELSE
    RAISE EXCEPTION 'Decisión no válida.';
  END IF;
  INSERT INTO f360.access_changes (what, subject, after, by_name, by_user) VALUES ('legacy_mapping_review', m.channel_inventory_id::text, to_jsonb(m), r.display_name, r.auth_user_id);
  RETURN to_jsonb(m);
END $$;

-- D-M1 gate for C3: ready only if EVERY legacy row with units is confirmed to an F360 variant.
CREATE FUNCTION public.f360_location_migration_readiness(p_location_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE l f360.locations; s record;
BEGIN
  PERFORM f360.require_role('viewer');
  SELECT * INTO l FROM f360.locations WHERE id = p_location_id;
  IF l.id IS NULL THEN RAISE EXCEPTION 'Ubicación no válida.'; END IF;
  SELECT count(*) AS rows_total,
         count(*) FILTER (WHERE snap_units > 0) AS rows_with_units,
         coalesce(sum(snap_units), 0) AS units_total,
         count(*) FILTER (WHERE status = 'confirmado') AS confirmed,
         count(*) FILTER (WHERE status = 'confirmado' AND snap_units > 0) AS confirmed_with_units,
         count(*) FILTER (WHERE status = 'propuesto') AS proposed,
         count(*) FILTER (WHERE status = 'ambiguo') AS ambiguous,
         count(*) FILTER (WHERE status = 'sin_coincidencia') AS unmatched,
         count(*) FILTER (WHERE status = 'sin_coincidencia' AND snap_units > 0) AS unmatched_with_units,
         count(*) FILTER (WHERE status = 'descartado') AS discarded,
         max(snapshot_at) AS snapshot_at
    INTO s FROM f360.legacy_inventory_map WHERE location_id = p_location_id;
  RETURN jsonb_build_object('location', l.name, 'ledger_authority', l.ledger_authority, 'rows_total', s.rows_total, 'rows_with_units', s.rows_with_units,
    'units_total', s.units_total, 'confirmed', s.confirmed, 'proposed', s.proposed, 'ambiguous', s.ambiguous, 'unmatched', s.unmatched,
    'unmatched_with_units', s.unmatched_with_units, 'discarded', s.discarded, 'snapshot_at', s.snapshot_at,
    'catalog_ready', s.rows_total > 0 AND s.confirmed_with_units = s.rows_with_units,
    'note', 'Listo de catálogo no significa migrar: el saldo inicial sale de un conteo físico (C3).');
END $$;

REVOKE ALL ON f360.legacy_inventory_map FROM PUBLIC, anon, authenticated;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA f360 FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.f360_propose_legacy_mapping(uuid), public.f360_review_legacy_mapping(uuid, text, uuid, text),
  public.f360_location_migration_readiness(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_propose_legacy_mapping(uuid), public.f360_review_legacy_mapping(uuid, text, uuid, text),
  public.f360_location_migration_readiness(uuid) TO authenticated, service_role;
