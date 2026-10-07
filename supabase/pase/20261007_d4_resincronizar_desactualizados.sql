-- Fuxia 360 · pase D4 (2026-10-07) — conciliación de la tienda después de D1/D2 (Mario: "hazlo todo tú y concilia que todo está bien").
-- 16 modelos EN VIVO cuya copia en fuxiaballerinas.com no coincide con Fuxia 360 (published_hash ≠ publish_hash): Mafalda Láser
-- (color Talco nuevo de D1), Ibiza (descripción de D1) y 14 cuya re-sincronización de precios COP/USD de ayer quedó 'partial' por el
-- error "el producto está PÚBLICO" (ya corregido en 92b0284). Se pide una re-sincronización normal, como Mario: el publicador nunca
-- cambia la visibilidad de un producto en vivo; solo pone al día nombre, descripción, colores, tallas, fotos y precios.
-- Aplicar SOLO con scripts/f360/prod_sql.sh.
BEGIN;
SELECT set_config('request.jwt.claims', json_build_object('sub', 'd11a8d33-cae6-46a5-9d0f-bd2516e8712b', 'role', 'authenticated')::text, true);
CREATE TEMP TABLE d4 (modelo text, resultado text) ON COMMIT DROP;
DO $$ DECLARE x record; BEGIN
  FOR x IN SELECT p.id, p.name FROM f360.woo_product_links l JOIN f360.products p ON p.id = l.product_id
           JOIN f360.sales_targets t ON t.id = l.target_id AND t.key = 'woo_production'
           WHERE l.published_hash IS DISTINCT FROM f360.publish_hash(p.id)
             AND NOT EXISTS (SELECT 1 FROM f360.sync_jobs j WHERE j.product_id = p.id AND j.target_id = t.id AND j.status IN ('queued', 'running')) LOOP
    BEGIN PERFORM public.f360_request_publish(x.id, gen_random_uuid(), 'woo_production'); INSERT INTO d4 VALUES (x.name, 'en cola');
    EXCEPTION WHEN OTHERS THEN INSERT INTO d4 VALUES (x.name, 'NO: ' || SQLERRM); END;
  END LOOP;
END $$;
SELECT jsonb_agg(jsonb_build_object('modelo', modelo, 'resultado', resultado) ORDER BY modelo) FROM d4;
COMMIT;
