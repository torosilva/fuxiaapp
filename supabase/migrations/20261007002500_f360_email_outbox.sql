-- Fuxia 360 — e-mail notifications (STAGING). Decision: Mario 2026-10-04: every "a la medida" request enters Fuxia 360
-- AND is e-mailed to info@fuxiaballerinas.com.
--   * f360.email_outbox: written in the SAME transaction as the request (never lost); sent asynchronously by the Edge
--     Function f360-email (pg_net after commit + a cron retry, max 8 attempts). Until an e-mail provider is configured the
--     rows simply stay pending and go out as soon as it is.
--   * Recipient per notification kind in f360.notification_recipients (default custom_request → info@fuxiaballerinas.com).
--   * Staging subjects are prefixed "[STAGING]" so test requests are recognisable.
-- No secret or URL here: Vault 'f360_email_url' / 'f360_email_secret' (absent ⇒ the tick does nothing).
-- Rollback: supabase/rollbacks/20261007002500_f360_email_outbox.down.sql

CREATE TABLE f360.notification_recipients (
  kind     text PRIMARY KEY,
  email    text NOT NULL CHECK (email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  prefix   text NOT NULL DEFAULT ''
);
INSERT INTO f360.notification_recipients (kind, email, prefix) VALUES ('custom_request', 'info@fuxiaballerinas.com', '[STAGING] ');

CREATE TABLE f360.email_outbox (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kind        text NOT NULL,
  ref_id      uuid,
  to_email    text NOT NULL,
  subject     text NOT NULL,
  body_text   text NOT NULL,
  reply_to    text,
  created_at  timestamptz NOT NULL DEFAULT clock_timestamp(),
  attempts    int NOT NULL DEFAULT 0,
  sent_at     timestamptz,
  result      text,
  UNIQUE (kind, ref_id)
);
CREATE INDEX email_outbox_pending_idx ON f360.email_outbox (created_at) WHERE sent_at IS NULL;

CREATE FUNCTION f360.email_tick() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_url text; v_secret text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM f360.email_outbox WHERE sent_at IS NULL AND attempts < 8) THEN RETURN; END IF;
  SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'f360_email_url';
  SELECT decrypted_secret INTO v_secret FROM vault.decrypted_secrets WHERE name = 'f360_email_secret';
  IF v_url IS NULL OR v_secret IS NULL THEN RETURN; END IF;
  PERFORM net.http_post(url := v_url, headers := jsonb_build_object('Authorization', 'Bearer ' || v_secret, 'Content-Type', 'application/json'),
    body := '{"action":"send"}'::jsonb, timeout_milliseconds := 20000);
END $$;

CREATE FUNCTION f360.notify_custom_request() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE rc f360.notification_recipients;
BEGIN
  SELECT * INTO rc FROM f360.notification_recipients WHERE kind = 'custom_request';
  IF rc.kind IS NULL THEN RETURN NEW; END IF;
  INSERT INTO f360.email_outbox (kind, ref_id, to_email, subject, body_text)
  VALUES ('custom_request', NEW.id, rc.email,
    rc.prefix || 'Nueva solicitud a la medida: ' || NEW.product_name || ' · ' || NEW.color_wanted || ' · ' || NEW.customer_name,
    'Una clienta pidió un modelo a la medida desde la tienda en línea.' || E'\n\n' ||
    'Modelo: ' || NEW.product_name || E'\n' ||
    'Color: ' || NEW.color_wanted || E'\n' ||
    'Talla: ' || coalesce(NEW.size_wanted, '—') || coalesce(' (talla tienda ' || NEW.store_size || ')', '') || E'\n' ||
    coalesce('Largo del pie: ' || NEW.foot_cm || ' cm' || E'\n', '') ||
    'Nombre: ' || NEW.customer_name || E'\n' ||
    'WhatsApp: ' || NEW.phone || '  (https://wa.me/' || regexp_replace(NEW.phone, '\D', '', 'g') || ')' || E'\n' ||
    coalesce('Nota: ' || NEW.note || E'\n', '') ||
    'País: ' || coalesce(upper(NEW.country), '—') || E'\n' ||
    'Fecha: ' || to_char(NEW.created_at AT TIME ZONE 'America/Mexico_City', 'DD/MM/YYYY HH24:MI') || E'\n\n' ||
    'Queda registrada en Fuxia 360 → Productos → A la medida.')
  ON CONFLICT (kind, ref_id) DO NOTHING;
  BEGIN PERFORM f360.email_tick(); EXCEPTION WHEN OTHERS THEN NULL; END;
  RETURN NEW;
END $$;
CREATE TRIGGER custom_requests_notify AFTER INSERT ON f360.custom_requests FOR EACH ROW EXECUTE FUNCTION f360.notify_custom_request();

-- Edge Function f360-email (service role): claim what is due; report back.
CREATE FUNCTION public.f360_email_claim(p_limit int DEFAULT 50) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE v_out jsonb;
BEGIN
  WITH due AS (SELECT id FROM f360.email_outbox WHERE sent_at IS NULL AND attempts < 8 ORDER BY created_at
               LIMIT greatest(1, least(p_limit, 200)) FOR UPDATE SKIP LOCKED),
       upd AS (UPDATE f360.email_outbox o SET attempts = o.attempts + 1 FROM due WHERE o.id = due.id RETURNING o.*)
  SELECT coalesce(jsonb_agg(jsonb_build_object('id', id, 'to', to_email, 'subject', subject, 'text', body_text, 'reply_to', reply_to)), '[]') INTO v_out FROM upd;
  RETURN v_out;
END $$;
CREATE FUNCTION public.f360_email_result(p_results jsonb) RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE x jsonb; n int := 0;
BEGIN
  FOR x IN SELECT * FROM jsonb_array_elements(coalesce(p_results, '[]')) LOOP
    UPDATE f360.email_outbox SET result = left(x->>'result', 300),
        sent_at = CASE WHEN (x->>'done')::boolean THEN clock_timestamp() END,
        attempts = CASE WHEN (x->>'retry_free')::boolean THEN greatest(0, attempts - 1) ELSE attempts END   -- no provider yet: don't burn attempts
      WHERE id = (x->>'id')::uuid AND sent_at IS NULL;
    n := n + 1;
  END LOOP;
  RETURN n;
END $$;

SELECT cron.schedule('f360-email-retry', '*/5 * * * *', 'SELECT f360.email_tick()');

REVOKE ALL ON f360.email_outbox, f360.notification_recipients FROM PUBLIC, anon, authenticated;
GRANT ALL ON f360.email_outbox, f360.notification_recipients TO service_role;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA f360 FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.f360_email_claim(int), public.f360_email_result(jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.f360_email_claim(int), public.f360_email_result(jsonb) TO service_role;
