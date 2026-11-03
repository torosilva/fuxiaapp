-- Bandeja → WhatsApp (20261105000400) — database tests (STAGING). One transaction, ROLLED BACK.
BEGIN;
CREATE TEMP TABLE t_results (n serial, status text, name text, detail text) ON COMMIT DROP;
CREATE FUNCTION pg_temp.ok(p_cond boolean, p_name text, p_detail text) RETURNS void LANGUAGE sql AS
$$ INSERT INTO t_results(status,name,detail) VALUES (CASE WHEN coalesce(p_cond, false) THEN 'PASS' ELSE 'FAIL' END, p_name, p_detail) $$;
DO $$
DECLARE c uuid; l uuid; v jsonb; n0 int; n int;
BEGIN
  SELECT count(*) INTO n0 FROM f360.whatsapp_outbox WHERE kind = 'aviso_equipo';
  INSERT INTO f360.customer_cases (kind, source, reason, summary, customer_name, country, product_name, color, size)
    VALUES ('escalacion', 'hilo_web', 'high_intent', E'Quiere el\nSueco', 'Prueba', 'co', 'Sueco cucarrón', 'Dorado', '37') RETURNING id INTO c;
  PERFORM pg_temp.ok((SELECT count(*) FROM f360.whatsapp_outbox WHERE kind = 'aviso_equipo') = n0, 'sin destinatarios no se encola nada', '');
  DELETE FROM f360.customer_cases WHERE id = c;
  INSERT INTO f360.staff_whatsapp (phone, name) VALUES ('+5215500000077', 'Prueba equipo');
  INSERT INTO f360.customer_cases (kind, source, reason, summary, customer_name, country, product_name, color, size)
    VALUES ('escalacion', 'hilo_web', 'high_intent', E'Quiere el\nSueco', 'Prueba', 'co', 'Sueco cucarrón', 'Dorado', '37') RETURNING id INTO c;
  SELECT variables INTO v FROM f360.whatsapp_outbox WHERE kind = 'aviso_equipo' AND ref_id = c || ':nuevo:+5215500000077';
  PERFORM pg_temp.ok(v->>'1' = 'quiere comprar', 'escalación nueva → aviso', v::text);
  PERFORM pg_temp.ok(position(E'\n' IN v::text) = 0 AND (v->>'3') NOT LIKE E'%\n%', 'sin saltos de línea', v->>'3');
  UPDATE f360.customer_cases SET phone = '+573001112233' WHERE id = c;
  SELECT variables INTO v FROM f360.whatsapp_outbox WHERE kind = 'aviso_equipo' AND ref_id = c || ':contacto:+5215500000077';
  PERFORM pg_temp.ok(v->>'1' = 'dejó su WhatsApp' AND (v->>'3') LIKE '%wa.me/573001112233%', 'dejó WhatsApp → aviso con su link', v->>'3');
  UPDATE f360.customer_cases SET summary = 'otra cosa' WHERE id = c;
  SELECT count(*) INTO n FROM f360.whatsapp_outbox WHERE kind = 'aviso_equipo' AND ref_id LIKE c || ':%';
  PERFORM pg_temp.ok(n = 2, 'otro cambio no repite aviso', n::text);
  UPDATE f360.customer_cases SET status = 'resuelta' WHERE id = c;
  UPDATE f360.customer_cases SET status = 'nueva' WHERE id = c;
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM f360.whatsapp_outbox WHERE kind = 'aviso_equipo' AND ref_id LIKE c || ':reabierto-%'), 'reabierto → aviso', '');
  INSERT INTO f360.customer_cases (kind, source, phone, country, summary, product_name) VALUES ('link_pago', 'web_checkout', '+5215500000001', 'mx', 'Pidió link', 'Paula 39') RETURNING id INTO l;
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM f360.whatsapp_outbox WHERE ref_id LIKE l || ':%'), 'link: nada antes de tener pedido', '');
  PERFORM public.f360_pay_link_done(l, 999123, '$5,600', 'https://x.test/pay', NULL);
  SELECT variables INTO v FROM f360.whatsapp_outbox WHERE kind = 'aviso_equipo' AND ref_id = l || ':nuevo:+5215500000077';
  PERFORM pg_temp.ok(v->>'1' = 'pidió link de pago' AND (v->>'3') LIKE '%pedido #999123%', 'link creado → aviso con pedido', v->>'3');
  PERFORM f360.bandeja_resumen();
  SELECT variables INTO v FROM f360.whatsapp_outbox WHERE kind = 'aviso_equipo' AND ref_type = 'resumen_diario' AND ref_id LIKE '%:+5215500000077';
  PERFORM pg_temp.ok(v->>'1' LIKE 'resumen: % sin atender', 'resumen diario', v::text);
  PERFORM f360.bandeja_resumen();
  PERFORM pg_temp.ok((SELECT count(*) FROM f360.whatsapp_outbox WHERE ref_type = 'resumen_diario' AND ref_id LIKE '%:+5215500000077') = 1, 'un resumen por día', '');
  PERFORM pg_temp.ok(NOT has_table_privilege('authenticated', 'f360.staff_whatsapp', 'SELECT'), 'teléfonos del equipo no expuestos', '');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'f360-bandeja-resumen'), 'cron del resumen', '');
END $$;
SELECT status || ' | ' || name || ' | ' || left(coalesce(detail,''), 150) FROM t_results ORDER BY n;
ROLLBACK;
