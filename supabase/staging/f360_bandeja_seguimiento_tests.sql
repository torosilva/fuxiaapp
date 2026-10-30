-- Bandeja · seguimiento (20261105000300) — database tests (STAGING). One transaction, ROLLED BACK.
BEGIN;
CREATE TEMP TABLE t_results (n serial, status text, name text, detail text) ON COMMIT DROP;
CREATE FUNCTION pg_temp.ok(p_cond boolean, p_name text, p_detail text) RETURNS void LANGUAGE sql AS
$$ INSERT INTO t_results(status,name,detail) VALUES (CASE WHEN coalesce(p_cond, false) THEN 'PASS' ELSE 'FAIL' END, p_name, p_detail) $$;
DO $$
DECLARE o f360.commerce_woo_orders; c_mx uuid; c_co uuid; c_old uuid; st text;
BEGIN
  SELECT * INTO o FROM f360.commerce_woo_orders WHERE market = 'MX' ORDER BY woo_created_at DESC LIMIT 1;
  UPDATE f360.commerce_woo_orders SET ever_paid = false WHERE target_id = o.target_id AND woo_order_id = o.woo_order_id;
  INSERT INTO f360.customer_cases (kind, source, phone, country, summary) VALUES ('link_pago', 'web_checkout', '+5215500000001', 'mx', 'Pidió link de pago desde el checkout')
    RETURNING id INTO c_mx;
  PERFORM public.f360_pay_link_done(c_mx, o.woo_order_id, '$1', 'https://x.test/pay', NULL);
  PERFORM pg_temp.ok((SELECT woo_order_id FROM f360.customer_cases WHERE id = c_mx) = o.woo_order_id, 'pay_link_done guarda el pedido', o.woo_order_id::text);
  INSERT INTO f360.customer_cases (kind, source, phone, country, summary, woo_order_id) VALUES ('link_pago', 'web_checkout', '+5730000000001', 'co', 'otro mercado', o.woo_order_id)
    RETURNING id INTO c_co;
  INSERT INTO f360.customer_cases (kind, source, phone, country, summary, woo_order_id, status) VALUES ('link_pago', 'web_checkout', '+5215500000002', 'mx', 'descartado', o.woo_order_id, 'descartada')
    RETURNING id INTO c_old;
  PERFORM pg_temp.ok((SELECT status FROM f360.customer_cases WHERE id = c_mx) = 'nueva', 'sin pagar sigue nueva', '');
  UPDATE f360.commerce_woo_orders SET ever_paid = true WHERE target_id = o.target_id AND woo_order_id = o.woo_order_id;
  SELECT status INTO st FROM f360.customer_cases WHERE id = c_mx;
  PERFORM pg_temp.ok(st = 'resuelta', 'al pagarse se resuelve sola', st || ' · ' || (SELECT updated_by FROM f360.customer_cases WHERE id = c_mx));
  PERFORM pg_temp.ok((SELECT status FROM f360.customer_cases WHERE id = c_co) = 'nueva', 'mismo número en otro mercado NO se toca', '');
  PERFORM pg_temp.ok((SELECT status FROM f360.customer_cases WHERE id = c_old) = 'descartada', 'una descartada no cambia', '');
  PERFORM pg_temp.ok(NOT has_function_privilege('anon', 'public.f360_inbox_open_count()', 'EXECUTE'), 'anon no lee el contador', '');
  PERFORM pg_temp.ok(NOT has_function_privilege('authenticated', 'public.f360_pay_link_done(uuid,bigint,text,text,text)', 'EXECUTE'), 'pay_link_done solo service_role', '');
END $$;
SELECT status || ' | ' || name || ' | ' || left(coalesce(detail,''), 110) FROM t_results ORDER BY n;
ROLLBACK;
