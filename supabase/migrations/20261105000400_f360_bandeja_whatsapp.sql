-- Fuxia 360 — Bandeja de clientas por WhatsApp (Mario 2026-11-03: "¿no sería mejor un WhatsApp?" → a Carolina; el correo se queda
-- de respaldo). Same outbox and sender as the thank-you WhatsApp (f360.whatsapp_outbox → f360-whatsapp → Twilio), new kind
-- 'aviso_equipo' with its own Meta-approved template (TWILIO_STAFF_CONTENT_SID). Until Meta approves it nothing is sent; messages
-- wait (3 days) like the thank-you ones did.
--   * f360.staff_whatsapp: who receives the notices (data, set per environment; empty ⇒ nothing is queued).
--   * One message per case event: new escalation / "a la medida", payment link created or failed, the customer left her WhatsApp,
--     a closed case she reopened. Template variables: {{1}} what happened, {{2}} customer, {{3}} detail + her wa.me link.
--   * Daily summary 9:00 CDMX (cron 'f360-bandeja-resumen', 15:00 UTC) while anything is still 'nueva'/'en_atencion'.
-- WhatsApp variables cannot carry line breaks: everything is flattened to one line.
-- Rollback: supabase/rollbacks/20261105000400_f360_bandeja_whatsapp.down.sql

CREATE TABLE f360.staff_whatsapp (
  phone   text PRIMARY KEY CHECK (phone ~ '^\+[0-9]{10,15}$'),
  name    text NOT NULL,
  active  boolean NOT NULL DEFAULT true
);
ALTER TABLE f360.staff_whatsapp ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON f360.staff_whatsapp FROM PUBLIC, anon, authenticated;
GRANT ALL ON f360.staff_whatsapp TO service_role;

ALTER TABLE f360.whatsapp_outbox DROP CONSTRAINT whatsapp_outbox_kind_check,
  ADD CONSTRAINT whatsapp_outbox_kind_check CHECK (kind IN ('thanks', 'thanks_member', 'aviso_equipo'));

CREATE FUNCTION f360.wa_line(p text, p_max int) RETURNS text LANGUAGE sql IMMUTABLE SET search_path = pg_catalog, pg_temp AS $$
  SELECT left(btrim(regexp_replace(coalesce(p, ''), '\s+', ' ', 'g')), p_max)
$$;

-- p_ref makes each notice unique (one per case event, one summary per day).
CREATE FUNCTION f360.staff_whatsapp_enqueue(p_ref_type text, p_ref text, p_what text, p_who text, p_detail text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE s f360.staff_whatsapp;
BEGIN
  FOR s IN SELECT * FROM f360.staff_whatsapp WHERE active LOOP
    INSERT INTO f360.whatsapp_outbox (kind, phone, variables, ref_type, ref_id)
    VALUES ('aviso_equipo', s.phone, jsonb_build_object('1', coalesce(nullif(f360.wa_line(p_what, 80), ''), 'clienta por atender'),
              '2', coalesce(nullif(f360.wa_line(p_who, 120), ''), 'sin nombre'), '3', coalesce(nullif(f360.wa_line(p_detail, 600), ''), '—')),
            p_ref_type, p_ref || ':' || s.phone)
    ON CONFLICT (kind, ref_type, ref_id) DO NOTHING;
  END LOOP;
  BEGIN PERFORM f360.whatsapp_tick(); EXCEPTION WHEN OTHERS THEN NULL; END;
END $$;

CREATE FUNCTION f360.case_whatsapp() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE ev text; what text; detail text; wa text;
BEGIN
  IF NEW.kind = 'link_pago' THEN
    IF TG_OP = 'UPDATE' AND NEW.woo_order_id IS NOT NULL AND OLD.woo_order_id IS NULL THEN ev := 'nuevo'; what := 'pidió link de pago';
    ELSIF TG_OP = 'UPDATE' AND NEW.summary LIKE '%No se pudo crear el pedido%' AND OLD.summary NOT LIKE '%No se pudo crear el pedido%' THEN
      ev := 'nuevo'; what := 'no pudo pagar y el link falló';
    END IF;
  ELSIF TG_OP = 'INSERT' THEN
    ev := 'nuevo';
    what := CASE WHEN NEW.kind = 'a_la_medida' THEN 'pedido a la medida' ELSE CASE NEW.reason
      WHEN 'requested' THEN 'pidió hablar con alguien' WHEN 'complaint' THEN 'tiene una queja' WHEN 'high_intent' THEN 'quiere comprar'
      WHEN 'technical_issue' THEN 'tiene un problema para pagar o con la página' WHEN 'out_of_scope' THEN 'Hilo no supo responder'
      WHEN 'low_confidence' THEN 'Hilo no estaba seguro' ELSE 'Hilo pide ayuda' END END;
  ELSIF NEW.phone IS NOT NULL AND OLD.phone IS NULL THEN ev := 'contacto'; what := 'dejó su WhatsApp';
  ELSIF NEW.status = 'nueva' AND OLD.status IN ('resuelta', 'descartada') THEN
    ev := 'reabierto-' || to_char(clock_timestamp(), 'YYYYMMDDHH24'); what := 'volvió a escribir';
  END IF;
  IF ev IS NULL THEN RETURN NULL; END IF;
  wa := CASE WHEN NEW.phone IS NOT NULL THEN 'WhatsApp: wa.me/' || regexp_replace(NEW.phone, '\D', '', 'g') ELSE 'todavía sin WhatsApp' END;
  detail := concat_ws(' · ',
    nullif(concat_ws(' ', NEW.product_name, NEW.color, CASE WHEN NEW.size IS NOT NULL THEN 'talla ' || NEW.size END), ''),
    upper(NEW.country),
    CASE WHEN NEW.kind = 'link_pago' THEN coalesce('pedido #' || NEW.woo_order_id, NULL) END,
    CASE WHEN NEW.kind <> 'link_pago' THEN '"' || left(f360.wa_line(NEW.summary, 400), 220) || '"' END,
    wa);
  BEGIN
    PERFORM f360.staff_whatsapp_enqueue('customer_case', NEW.id || ':' || ev, what, NEW.customer_name, detail);
  EXCEPTION WHEN OTHERS THEN NULL;   -- a notice never blocks the case
  END;
  RETURN NULL;
END $$;
CREATE TRIGGER customer_cases_whatsapp AFTER INSERT OR UPDATE ON f360.customer_cases FOR EACH ROW EXECUTE FUNCTION f360.case_whatsapp();

CREATE FUNCTION f360.bandeja_resumen() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE n int; oldest int; names text;
BEGIN
  SELECT count(*), max(extract(day FROM now() - created_at))::int,
         string_agg(coalesce(nullif(split_part(btrim(customer_name), ' ', 1), ''), 'sin nombre'), ', ' ORDER BY created_at)
    INTO n, oldest, names
    FROM f360.customer_cases WHERE status IN ('nueva', 'en_atencion');
  IF n = 0 THEN RETURN; END IF;
  PERFORM f360.staff_whatsapp_enqueue('resumen_diario', to_char(now() AT TIME ZONE 'America/Mexico_City', 'YYYY-MM-DD'),
    'resumen: ' || n || CASE WHEN n = 1 THEN ' clienta sin atender' ELSE ' clientas sin atender' END,
    left(names, 120),
    'La más antigua lleva ' || oldest || CASE WHEN oldest = 1 THEN ' día' ELSE ' días' END || '. Márcalas como resueltas al terminar.');
END $$;
SELECT cron.schedule('f360-bandeja-resumen', '0 15 * * *', 'SELECT f360.bandeja_resumen()');

REVOKE ALL ON FUNCTION f360.wa_line(text, int), f360.staff_whatsapp_enqueue(text, text, text, text, text), f360.case_whatsapp(), f360.bandeja_resumen()
  FROM PUBLIC, anon, authenticated;
