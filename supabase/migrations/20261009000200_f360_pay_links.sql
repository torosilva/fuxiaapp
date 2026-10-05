-- Fuxia 360 — "Link de pago" (Mario 2026-10-04): when the checkout fails (Instagram's browser, a rejected card…), the customer
-- can ask for a payment link. The Edge Function f360-store-reserve creates a PENDING order in WooCommerce with the cart's
-- products (Woo computes every price, coupon and total; nothing comes from the browser) and returns Woo's own payment page.
-- Each request is a case in the Bandeja de clientas (kind 'link_pago', source 'web_checkout') so the team can follow up on WhatsApp,
-- and an e-mail goes to the team (f360.email_outbox; queued until a provider is configured).
-- Limits (anti-abuse): 3 links per phone per day, 60 per hour for the whole store.
-- Rollback: supabase/rollbacks/20261009000200_f360_pay_links.down.sql
ALTER TABLE f360.customer_cases DROP CONSTRAINT customer_cases_kind_check,
  ADD CONSTRAINT customer_cases_kind_check CHECK (kind IN ('escalacion', 'a_la_medida', 'link_pago'));
ALTER TABLE f360.customer_cases DROP CONSTRAINT customer_cases_source_check,
  ADD CONSTRAINT customer_cases_source_check CHECK (source IN ('hilo_web', 'hilo_app', 'hilo_whatsapp', 'hilo_voice', 'web_pdp', 'web_checkout'));

-- Step 1 (before Woo is called): limits + the case. Returns the case id.
CREATE FUNCTION public.f360_pay_link_open(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE c f360.customer_cases; v_phone text := nullif(btrim(p->>'phone'), '');
BEGIN
  IF v_phone IS NULL OR v_phone !~ '^\+[0-9]{10,15}$' THEN RAISE EXCEPTION 'Escribe tu WhatsApp a 10 dígitos.'; END IF;
  IF (SELECT count(*) FROM f360.customer_cases WHERE kind = 'link_pago' AND phone = v_phone AND created_at > now() - interval '1 day') >= 3 THEN
    RAISE EXCEPTION 'Ya te generamos links hoy. Escríbenos por WhatsApp y te ayudamos.';
  END IF;
  IF (SELECT count(*) FROM f360.customer_cases WHERE kind = 'link_pago' AND created_at > now() - interval '1 hour') >= 60 THEN
    RAISE EXCEPTION 'Ahorita no podemos generar el link. Escríbenos por WhatsApp.';
  END IF;
  INSERT INTO f360.customer_cases (kind, source, customer_name, phone, email, country, product_name, summary, page_url)
  VALUES ('link_pago', 'web_checkout', left(nullif(btrim(p->>'name'), ''), 80), v_phone,
          CASE WHEN p->>'email' ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN left(p->>'email', 120) END,
          left(nullif(p->>'country', ''), 8), left(nullif(p->>'products', ''), 200),
          left('Pidió link de pago desde el checkout' || coalesce(' · ' || nullif(p->>'reason', ''), ''), 2000), left(nullif(p->>'page_url', ''), 300))
  RETURNING * INTO c;
  RETURN jsonb_build_object('id', c.id);
END $$;

-- Step 2 (after Woo answered): the order and its payment page, or the failure. E-mails the team when the link exists.
CREATE FUNCTION public.f360_pay_link_done(p_id uuid, p_order bigint, p_total text, p_url text, p_error text DEFAULT NULL) RETURNS void
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

REVOKE ALL ON FUNCTION public.f360_pay_link_open(jsonb), public.f360_pay_link_done(uuid, bigint, text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.f360_pay_link_open(jsonb), public.f360_pay_link_done(uuid, bigint, text, text, text) TO service_role;
