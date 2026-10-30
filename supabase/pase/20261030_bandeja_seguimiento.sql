-- Fuxia 360 · PRODUCCIÓN · 20261105000300_f360_bandeja_seguimiento VERBATIM + datos de la Bandeja
-- (Mario 2026-10-30: "se quedaron muchas cosas y Carolina ni yo nunca supimos" → "si dale"). Probada en staging (7/7).
--   · prod tenía el destinatario con prefijo "[STAGING] " (copiado de la migración de staging): se quita;
--   · los 9 avisos que nunca salieron: se les quita el prefijo; se omiten los ya viejos/atendidos (link #5776 pagado,
--     a la medida de Mariana marcada PAGADO por Carolina, prueba interna del 10 oct) y salen los 6 de casos abiertos;
--   · la prueba interna del 10 oct ("Prueba interna, quiero hablar con una persona") pasa a 'descartada'.
-- Reversión: supabase/rollbacks/20261105000300_f360_bandeja_seguimiento.down.sql
BEGIN;
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version = '20261105000300') THEN RAISE EXCEPTION 'PRE: ya está'; END IF;
  IF NOT EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version = '20261104000200') THEN RAISE EXCEPTION 'PRE: falta 20261104000200'; END IF;
  IF (SELECT count(*) FROM f360.email_outbox WHERE sent_at IS NULL) <> 9 THEN RAISE EXCEPTION 'PRE: se esperaban 9 avisos pendientes'; END IF;
END $$;
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
INSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ('20261105000300', 'f360_bandeja_seguimiento', '{}');

-- Datos de producción
UPDATE f360.notification_recipients SET prefix = '' WHERE prefix = '[STAGING] ';
UPDATE f360.customer_cases SET status = 'descartada', updated_at = clock_timestamp(), updated_by = 'Mario: prueba interna'
 WHERE external_ref = '49cce8f4-d9ae-4269-b8c2-f006a7f3dafd' AND status = 'nueva';
UPDATE f360.email_outbox SET subject = regexp_replace(subject, '^\[STAGING\] ', '') WHERE sent_at IS NULL;
UPDATE f360.email_outbox o SET attempts = 8, result = 'omitido 2026-10-30: aviso viejo, el caso ya está atendido'
 WHERE o.sent_at IS NULL AND (
       o.kind = 'custom_request'
    OR (o.kind LIKE 'customer_case%' AND EXISTS (SELECT 1 FROM f360.customer_cases c WHERE c.id = o.ref_id AND c.status IN ('resuelta', 'descartada'))));
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM f360.notification_recipients WHERE prefix <> '') THEN RAISE EXCEPTION 'POST: prefijo'; END IF;
  IF (SELECT status FROM f360.customer_cases WHERE woo_order_id = 5776) <> 'resuelta' THEN RAISE EXCEPTION 'POST: #5776 no se resolvió'; END IF;
  IF (SELECT count(*) FROM f360.email_outbox WHERE sent_at IS NULL AND attempts < 8) <> 6 THEN RAISE EXCEPTION 'POST: se esperaban 6 avisos por enviar'; END IF;
  IF EXISTS (SELECT 1 FROM f360.email_outbox WHERE subject LIKE '[STAGING]%' AND sent_at IS NULL) THEN RAISE EXCEPTION 'POST: asunto staging'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'commerce_woo_orders_case_paid') THEN RAISE EXCEPTION 'POST: trigger'; END IF;
  IF has_function_privilege('anon', 'public.f360_inbox_open_count()', 'EXECUTE') THEN RAISE EXCEPTION 'POST: anon'; END IF;
END $$;
COMMIT;
