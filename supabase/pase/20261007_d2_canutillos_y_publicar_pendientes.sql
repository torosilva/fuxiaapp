-- Fuxia 360 · pase D2 (2026-10-07) — Mario: "hazlo todo tú y concilia que todo está bien".
--   1. "Ballerinas doradas con broche de piedras" (Woo 3228, tallas 35–40, verificadas hoy en fuxiaballerinas.com) ES Canutillos
--      color Dorado (Carolina, 2026-10-07). En la homologación había quedado "sin correspondencia · No existe". Se confirma en el canal
--      real (woo_production) talla por talla; la fila de staging4 se deja como historia. Bitácora en legacy_woo_map_log.
--   2. Publicación de los modelos activos que NO tienen producto nuevo en la tienda (su ropa vieja por color sigue a la venta):
--      · con productos viejos homologados → f360_consolidate_start (igual que el botón "Unir"): retira las ligas viejas para que
--        un pedido viejo se siga reconociendo y pide la publicación como BORRADOR;
--      · sin productos viejos → f360_request_publish (BORRADOR).
--      Un modelo que no está listo se salta y se reporta con lo que le falta. Nada sale en vivo aquí: "Poner EN VIVO" lo hace una
--      dueña desde el admin (el publicador oculta entonces los productos viejos del modelo y deja su URL funcionando).
-- Hecho como Mario (dueño), con las mismas funciones que usa el admin: queda auditado.
-- Aplicar SOLO con scripts/f360/prod_sql.sh (dry-run primero).
BEGIN;
SELECT set_config('request.jwt.claims', json_build_object('sub', 'd11a8d33-cae6-46a5-9d0f-bd2516e8712b', 'role', 'authenticated')::text, true);

-- 1 · Canutillos Dorado ← Woo 3228
CREATE TEMP TABLE d2_map (woo_variation_id int, talla text, variant_id uuid) ON COMMIT DROP;
INSERT INTO d2_map VALUES
  (3229, '35', 'ad4e1275-4bc7-4bec-9d6c-f4e89eddba70'), (3230, '36', '74e5888e-d0f0-453f-9494-e892cb725fcc'),
  (3231, '37', '1c5eb436-f9c2-4bcc-9ac3-6d2e10b005c9'), (3232, '38', '413cacee-f43c-4012-acb0-1fe5f737c005'),
  (3233, '39', 'a8a53915-7017-453b-9e61-1c483ac09a95'), (3234, '40', '758cbcbc-ed75-45cb-ba52-fe96fc8c7025');
DO $$ BEGIN
  IF (SELECT count(*) FROM d2_map d JOIN f360.product_variants v ON v.id = d.variant_id JOIN f360.product_colors c ON c.id = v.color_id
      WHERE v.product_id = 'cc6a999d-1691-4ccd-94f0-fdd39c3e4b84' AND c.name = 'Dorado' AND v.sku = 'F360-CANUTILLOS-DORADO-' || d.talla) <> 6 THEN
    RAISE EXCEPTION 'D2: las variantes de Canutillos Dorado no son las esperadas.';
  END IF;
END $$;
INSERT INTO f360.legacy_woo_map (target_id, woo_variation_id, woo_product_id, woo_product_name, woo_parent_sku, woo_category, woo_size, woo_color,
  woo_regular_price, sold_all, sold_90d, snapshot_at, proposed_model, proposed_product_id, proposed_color, proposed_size, proposed_status, confidence,
  proposal_reason, proposed_at, status, human_locked, confirmed_variant_id, decided_by, decided_by_name, decided_at, note)
SELECT p.id, m.woo_variation_id, m.woo_product_id, m.woo_product_name, m.woo_parent_sku, m.woo_category, m.woo_size, m.woo_color,
  m.woo_regular_price, m.sold_all, m.sold_90d, m.snapshot_at, 'Canutillos', 'cc6a999d-1691-4ccd-94f0-fdd39c3e4b84', 'Dorado', d.talla, m.proposed_status, m.confidence,
  m.proposal_reason, m.proposed_at, 'confirmado', true, d.variant_id, 'd11a8d33-cae6-46a5-9d0f-bd2516e8712b', 'Mario Silva', clock_timestamp(),
  'Es Canutillos Dorado (Carolina 2026-10-07); antes "No existe" [pase D2, canal real]'
FROM f360.legacy_woo_map m
JOIN f360.sales_targets s ON s.id = m.target_id AND s.key = 'woo_staging4'
JOIN d2_map d ON d.woo_variation_id = m.woo_variation_id
CROSS JOIN f360.sales_targets p
WHERE p.key = 'woo_production' AND m.woo_product_id = 3228;
INSERT INTO f360.legacy_woo_map_log (target_id, woo_variation_id, action, from_status, to_status, variant_id, actor_auth_user_id, actor_name, note)
SELECT t.id, d.woo_variation_id, 'confirm', 'sin_correspondencia', 'confirmado', d.variant_id, 'd11a8d33-cae6-46a5-9d0f-bd2516e8712b', 'Mario Silva',
  'pase D2: Ballerinas doradas con broche de piedras = Canutillos Dorado (Carolina 2026-10-07)'
FROM d2_map d CROSS JOIN f360.sales_targets t WHERE t.key = 'woo_production';

-- 2 · publicar (BORRADOR) los modelos activos sin producto nuevo en la tienda
CREATE TEMP TABLE d2_pub (modelo text, via text, resultado text) ON COMMIT DROP;
DO $$ DECLARE t f360.sales_targets; ids uuid[]; res jsonb; x record; BEGIN
  SELECT * INTO t FROM f360.sales_targets WHERE key = 'woo_production';
  -- with old store products (Carolina's confirmed homologation in the real channel)
  SELECT array_agg(DISTINCT v.product_id) INTO ids FROM f360.legacy_woo_map m JOIN f360.product_variants v ON v.id = m.confirmed_variant_id
    JOIN f360.products p ON p.id = v.product_id
    WHERE m.target_id = t.id AND m.status = 'confirmado' AND p.status = 'active'
      AND NOT EXISTS (SELECT 1 FROM f360.woo_product_links l WHERE l.target_id = t.id AND l.product_id = p.id);
  IF ids IS NOT NULL THEN
    res := public.f360_consolidate_start('woo_production', ids, '{}'::jsonb);
    INSERT INTO d2_pub SELECT i->>'name', 'unir', 'en cola (' || coalesce(i->>'status', '') || ')' FROM jsonb_array_elements(res->'items') i;
    INSERT INTO d2_pub SELECT s->>'name', 'unir', 'NO: falta ' || (s->'missing')::text FROM jsonb_array_elements(res->'skipped') s;
  END IF;
  -- without old store products
  FOR x IN SELECT p.id, p.name FROM f360.products p WHERE p.status = 'active'
      AND NOT EXISTS (SELECT 1 FROM f360.woo_product_links l WHERE l.target_id = t.id AND l.product_id = p.id)
      AND NOT EXISTS (SELECT 1 FROM f360.legacy_consolidations c WHERE c.target_id = t.id AND c.product_id = p.id) LOOP
    BEGIN PERFORM public.f360_request_publish(x.id, gen_random_uuid(), 'woo_production'); INSERT INTO d2_pub VALUES (x.name, 'nuevo', 'en cola');
    EXCEPTION WHEN OTHERS THEN INSERT INTO d2_pub VALUES (x.name, 'nuevo', 'NO: ' || SQLERRM); END;
  END LOOP;
END $$;
SELECT jsonb_build_object(
  'canutillos_dorado', (SELECT count(*) FROM f360.legacy_woo_map m JOIN f360.sales_targets t ON t.id = m.target_id
                        WHERE t.key = 'woo_production' AND m.woo_product_id = 3228 AND m.status = 'confirmado'),
  'publicacion', (SELECT jsonb_agg(jsonb_build_object('modelo', modelo, 'via', via, 'resultado', resultado) ORDER BY modelo) FROM d2_pub));
COMMIT;
