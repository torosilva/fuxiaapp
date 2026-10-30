-- Rollback of 20261105000300_f360_bandeja_seguimiento. Cases already resolved automatically stay resolved (status is data).
BEGIN;
DROP TRIGGER IF EXISTS commerce_woo_orders_case_paid ON f360.commerce_woo_orders;
DROP FUNCTION IF EXISTS f360.case_close_paid();
DROP FUNCTION IF EXISTS public.f360_inbox_open_count();
CREATE OR REPLACE FUNCTION public.f360_pay_link_done(p_id uuid, p_order bigint, p_total text, p_url text, p_error text DEFAULT NULL) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE c f360.customer_cases; rc f360.notification_recipients;
BEGIN
  UPDATE f360.customer_cases SET
    summary = left(summary || CASE WHEN p_error IS NULL THEN E'\nPedido #' || p_order || ' · total ' || coalesce(p_total, '—') || E'\nLink de pago: ' || p_url
                                   ELSE E'\nNo se pudo crear el pedido: ' || left(p_error, 200) END, 2000),
    status = CASE WHEN p_error IS NULL THEN status ELSE 'nueva' END, updated_at = clock_timestamp()
  WHERE id = p_id AND kind = 'link_pago' RETURNING * INTO c;
  IF c.id IS NULL OR p_error IS NOT NULL THEN RETURN; END IF;
  SELECT * INTO rc FROM f360.notification_recipients WHERE kind = 'customer_case';
  IF rc.kind IS NULL THEN RETURN; END IF;
  INSERT INTO f360.email_outbox (kind, ref_id, to_email, subject, body_text)
  VALUES ('customer_case_link', c.id, rc.email,
    rc.prefix || 'Link de pago generado · pedido #' || p_order || coalesce(' · ' || c.customer_name, ''),
    'Una clienta tuvo problemas en el checkout y pidió un link de pago.' || E'\n\n' ||
    'Pedido: #' || p_order || ' (pendiente de pago) · total ' || coalesce(p_total, '—') || E'\n' ||
    coalesce('Productos: ' || c.product_name || E'\n', '') ||
    coalesce('Nombre: ' || c.customer_name || E'\n', '') ||
    'WhatsApp: ' || c.phone || '  (https://wa.me/' || regexp_replace(c.phone, '\D', '', 'g') || ')' || E'\n' ||
    coalesce('Correo: ' || c.email || E'\n', '') ||
    'Link de pago: ' || p_url || E'\n\n' ||
    'Si no paga en un rato, escríbele por WhatsApp. En Fuxia 360 → Bandeja de clientas.')
  ON CONFLICT (kind, ref_id) DO NOTHING;
  BEGIN PERFORM f360.email_tick(); EXCEPTION WHEN OTHERS THEN NULL; END;
END $$;
DROP INDEX IF EXISTS f360.customer_cases_woo_order_idx;
ALTER TABLE f360.customer_cases DROP COLUMN IF EXISTS woo_order_id;
DELETE FROM supabase_migrations.schema_migrations WHERE version = '20261105000300';
COMMIT;
