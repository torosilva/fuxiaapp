-- N2 · a channel's source location cannot be a system location ("En camino") — database tests (STAGING). ROLLED BACK.
BEGIN;
CREATE TEMP TABLE t_results (n serial, status text, name text, detail text) ON COMMIT DROP;
CREATE FUNCTION pg_temp.ok(p_cond boolean, p_name text, p_detail text) RETURNS void LANGUAGE sql AS
$$ INSERT INTO t_results(status,name,detail) VALUES (CASE WHEN coalesce(p_cond, false) THEN 'PASS' ELSE 'FAIL' END, p_name, p_detail) $$;

DO $$
DECLARE transit uuid := (SELECT id FROM f360.locations WHERE type = 'transit');
  bodega uuid := (SELECT id FROM f360.locations WHERE name = 'Bodega CDMX');
  tgt uuid := (SELECT id FROM f360.sales_targets WHERE key = 'woo_staging4');
  err text; nid uuid;
BEGIN
  PERFORM pg_temp.ok(transit IS NOT NULL AND bodega IS NOT NULL AND tgt IS NOT NULL, 'fixtures: En camino, Bodega CDMX, woo_staging4 exist', '');
  PERFORM pg_temp.ok((SELECT fulfillment_location_id FROM f360.sales_targets WHERE id = tgt) = bodega
    AND (SELECT sellable FROM f360.locations WHERE id = bodega) = false,
    'current channel woo_staging4 → Bodega CDMX (sellable=false) stays valid', '');

  BEGIN INSERT INTO f360.sales_targets (key, name, base_url, fulfillment_location_id, active)
    VALUES ('zz_n2_transit', 'ZZ N2', 'https://zz.invalid', transit, false); err := 'accepted';
  EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err LIKE '%En camino%', 'new channel with source "En camino" → refused', err);

  BEGIN UPDATE f360.sales_targets SET fulfillment_location_id = transit WHERE id = tgt; err := 'accepted';
  EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err LIKE '%En camino%' AND (SELECT fulfillment_location_id FROM f360.sales_targets WHERE id = tgt) = bodega,
    'changing an existing channel to "En camino" → refused, unchanged', err);

  INSERT INTO f360.sales_targets (key, name, base_url, fulfillment_location_id, active)
    VALUES ('zz_n2_ok', 'ZZ N2 ok', 'https://zz.invalid', bodega, false) RETURNING id INTO nid;
  PERFORM pg_temp.ok(nid IS NOT NULL, 'new channel with a real location (Bodega CDMX) → accepted', '');
  UPDATE f360.sales_targets SET name = 'ZZ N2 renombrado' WHERE id = nid;
  PERFORM pg_temp.ok((SELECT name FROM f360.sales_targets WHERE id = nid) = 'ZZ N2 renombrado', 'other columns still editable', '');

  BEGIN UPDATE f360.locations SET type = 'transit' WHERE id = bodega; err := 'accepted';
  EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err <> 'accepted', 'a channel source location cannot be turned into a transit location', err);
END $$;

SELECT status || ' | ' || name || ' | ' || left(coalesce(detail,''), 110) FROM t_results ORDER BY n;
ROLLBACK;
