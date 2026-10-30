-- Fuxia 360 — Bandeja de clientas: que nada se quede sin ver (Mario 2026-10-30: "se quedaron muchas cosas y Carolina ni yo
-- nunca supimos"). In production all 6 cases were still 'nueva' 6–22 days later and none of the 9 notice e-mails had gone out.
--   * A "link de pago" case remembers its WooCommerce order (woo_order_id) and RESOLVES ITSELF when that order is paid
--     (trigger on f360.commerce_woo_orders, same market). Before: order #5776 paid 2 minutes after the link, case still 'nueva'.
--   * public.f360_inbox_open_count(): open cases + the oldest one's age, for the menu badge (cheap; no personal data).
-- Writes nothing the customer sends; the trigger never blocks order capture (any error is swallowed).
-- Rollback: supabase/rollbacks/20261105000300_f360_bandeja_seguimiento.down.sql

ALTER TABLE f360.customer_cases ADD COLUMN woo_order_id bigint;
UPDATE f360.customer_cases SET woo_order_id = (substring(summary FROM 'Pedido #([0-9]+)'))::bigint
  WHERE kind = 'link_pago' AND summary ~ 'Pedido #[0-9]+';
CREATE INDEX customer_cases_woo_order_idx ON f360.customer_cases (woo_order_id) WHERE woo_order_id IS NOT NULL;

-- Same as 20261009000200 plus woo_order_id.
CREATE OR REPLACE FUNCTION public.f360_pay_link_done(p_id uuid, p_order bigint, p_total text, p_url text, p_error text DEFAULT NULL) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE c f360.customer_cases; rc f360.notification_recipients;
BEGIN
  UPDATE f360.customer_cases SET
    summary = left(summary || CASE WHEN p_error IS NULL THEN E'\nPedido #' || p_order || ' · total ' || coalesce(p_total, '—') || E'\nLink de pago: ' || p_url
                                   ELSE E'\nNo se pudo crear el pedido: ' || left(p_error, 200) END, 2000),
    woo_order_id = CASE WHEN p_error IS NULL THEN p_order ELSE woo_order_id END,
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

CREATE FUNCTION f360.case_close_paid() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  IF NEW.ever_paid AND (TG_OP = 'INSERT' OR NOT coalesce(OLD.ever_paid, false)) THEN
    BEGIN
      UPDATE f360.customer_cases SET status = 'resuelta', updated_at = clock_timestamp(),
             updated_by = 'Automático: pagó el pedido #' || NEW.woo_order_id
       WHERE kind = 'link_pago' AND woo_order_id = NEW.woo_order_id AND status IN ('nueva', 'en_atencion')
         AND upper(coalesce(country, NEW.market)) = upper(NEW.market);
    EXCEPTION WHEN OTHERS THEN NULL;   -- never block order capture
    END;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER commerce_woo_orders_case_paid AFTER INSERT OR UPDATE OF ever_paid ON f360.commerce_woo_orders
  FOR EACH ROW EXECUTE FUNCTION f360.case_close_paid();

-- Links already paid before this migration.
UPDATE f360.customer_cases c SET status = 'resuelta', updated_at = clock_timestamp(), updated_by = 'Automático: pagó el pedido #' || c.woo_order_id
  FROM f360.commerce_woo_orders o
 WHERE c.kind = 'link_pago' AND c.status IN ('nueva', 'en_atencion') AND o.woo_order_id = c.woo_order_id AND o.ever_paid
   AND upper(coalesce(c.country, o.market)) = upper(o.market);

CREATE FUNCTION public.f360_inbox_open_count() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  PERFORM f360.require_role('viewer');
  RETURN (SELECT jsonb_build_object('open', count(*), 'oldest_days', coalesce(max(extract(day FROM now() - created_at))::int, 0))
            FROM f360.customer_cases WHERE status IN ('nueva', 'en_atencion'));
END $$;

REVOKE ALL ON FUNCTION f360.case_close_paid() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.f360_inbox_open_count() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.f360_inbox_open_count() TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.f360_pay_link_done(uuid, bigint, text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.f360_pay_link_done(uuid, bigint, text, text, text) TO service_role;
