-- Fuxia 360 — "Bandeja de clientas" (STAGING). Decision: Mario 2026-10-04: "todo debe de quedar ya en Fuxia 360 tal cual".
-- One inbox for everything a customer asks the team for, whatever the channel:
--   * Hilo (HiloLabs) escalations — the agent's backend posts them here (Edge f360-hilo-intake, shared secret), keyed by
--     Hilo's conversation id, with reason, summary and the last messages;
--   * the contact the customer leaves in the web chat after an escalation (same case, by conversation id);
--   * "a la medida" requests (f360.custom_requests) — each one also appears here (linked, not copied twice).
-- Every new case is e-mailed to info@fuxiaballerinas.com (f360.email_outbox; custom requests keep their own e-mail).
-- Customer data kept to what the team needs to answer: first name, phone, optional e-mail, the conversation excerpt.
-- Rollback: supabase/rollbacks/20261007002600_f360_customer_cases.down.sql

CREATE TABLE f360.customer_cases (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kind               text NOT NULL CHECK (kind IN ('escalacion', 'a_la_medida')),
  source             text NOT NULL CHECK (source IN ('hilo_web', 'hilo_app', 'hilo_whatsapp', 'hilo_voice', 'web_pdp')),
  status             text NOT NULL DEFAULT 'nueva' CHECK (status IN ('nueva', 'en_atencion', 'resuelta', 'descartada')),
  external_ref       text UNIQUE CHECK (length(external_ref) <= 100),        -- Hilo conversation id
  custom_request_id  uuid UNIQUE REFERENCES f360.custom_requests(id) ON DELETE SET NULL,
  reason             text CHECK (length(reason) <= 40),
  summary            text CHECK (length(summary) <= 2000),
  transcript         jsonb NOT NULL DEFAULT '[]',
  customer_name      text CHECK (length(customer_name) <= 80),
  phone              text CHECK (phone IS NULL OR phone ~ '^\+[0-9]{10,15}$'),
  email              text CHECK (email IS NULL OR (length(email) <= 120 AND email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$')),
  country            text CHECK (length(country) <= 8),
  product_name       text CHECK (length(product_name) <= 200),
  color              text CHECK (length(color) <= 80),
  size               text CHECK (length(size) <= 20),
  page_url           text CHECK (length(page_url) <= 300),
  created_at         timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at         timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_by         text
);
CREATE INDEX customer_cases_open_idx ON f360.customer_cases (status, created_at DESC);
INSERT INTO f360.notification_recipients (kind, email, prefix) VALUES ('customer_case', 'info@fuxiaballerinas.com', '[STAGING] ');

CREATE FUNCTION f360.case_email(c f360.customer_cases, p_event text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE rc f360.notification_recipients; x jsonb; v_t text := '';
BEGIN
  SELECT * INTO rc FROM f360.notification_recipients WHERE kind = 'customer_case';
  IF rc.kind IS NULL THEN RETURN; END IF;
  FOR x IN SELECT * FROM jsonb_array_elements(c.transcript) LOOP
    v_t := v_t || CASE x->>'role' WHEN 'user' THEN 'Clienta: ' ELSE 'Hilo: ' END || left(x->>'content', 400) || E'\n';
  END LOOP;
  INSERT INTO f360.email_outbox (kind, ref_id, to_email, subject, body_text)
  VALUES ('customer_case_' || p_event, c.id, rc.email,
    rc.prefix || CASE p_event WHEN 'contacto' THEN 'La clienta dejó su WhatsApp' ELSE 'Hilo pide ayuda del equipo' END
      || coalesce(' · ' || c.product_name, '') || coalesce(' · ' || c.customer_name, ''),
    CASE p_event WHEN 'contacto' THEN 'La clienta dejó sus datos para que el equipo le escriba.' ELSE 'Hilo escaló una conversación al equipo.' END || E'\n\n' ||
    'Canal: ' || c.source || coalesce(E'\nMotivo: ' || c.reason, '') ||
    coalesce(E'\nProducto: ' || c.product_name || coalesce(' · ' || c.color, '') || coalesce(' · talla ' || c.size, ''), '') ||
    coalesce(E'\nNombre: ' || c.customer_name, '') ||
    coalesce(E'\nWhatsApp: ' || c.phone || '  (https://wa.me/' || regexp_replace(c.phone, '\D', '', 'g') || ')', '') ||
    coalesce(E'\nCorreo: ' || c.email, '') || coalesce(E'\nPágina: ' || c.page_url, '') ||
    coalesce(E'\n\nResumen de Hilo:\n' || c.summary, '') ||
    CASE WHEN v_t <> '' THEN E'\n\nConversación:\n' || v_t ELSE '' END ||
    E'\nEn Fuxia 360 → Bandeja de clientas.')
  ON CONFLICT (kind, ref_id) DO NOTHING;
  BEGIN PERFORM f360.email_tick(); EXCEPTION WHEN OTHERS THEN NULL; END;
END $$;

-- Service (f360-hilo-intake / f360-store-reserve): create or complete a case by Hilo's conversation id. Never erases data
-- already there (null fields are ignored). New case → e-mail; first time a phone arrives → e-mail "dejó su WhatsApp".
CREATE FUNCTION public.f360_case_upsert(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE c f360.customer_cases; prev f360.customer_cases; v_ref text := nullif(btrim(p->>'conversation_id'), '');
  v_phone text := nullif(btrim(p->>'phone'), ''); v_new boolean;
  v_tr jsonb := CASE WHEN jsonb_typeof(p->'transcript') = 'array' THEN (SELECT coalesce(jsonb_agg(jsonb_build_object('role', x->>'role', 'content', left(x->>'content', 1000))), '[]')
                    FROM (SELECT x FROM jsonb_array_elements(p->'transcript') x LIMIT 12) t) END;
BEGIN
  IF v_ref IS NULL THEN RAISE EXCEPTION 'Falta la conversación.'; END IF;
  IF v_phone IS NOT NULL AND (SELECT count(*) FROM f360.customer_cases WHERE phone = v_phone AND updated_at > now() - interval '1 day') >= 5 THEN
    RAISE EXCEPTION 'Ya recibimos tus datos; te escribimos pronto.';
  END IF;
  SELECT * INTO prev FROM f360.customer_cases WHERE external_ref = v_ref FOR UPDATE;
  v_new := prev.id IS NULL;
  INSERT INTO f360.customer_cases AS cc (kind, source, external_ref, reason, summary, transcript, customer_name, phone, email, country, product_name, color, size, page_url)
  VALUES ('escalacion', coalesce(nullif(p->>'source', ''), 'hilo_web'), v_ref, left(p->>'reason', 40), left(p->>'summary', 2000), coalesce(v_tr, '[]'),
          left(nullif(btrim(p->>'name'), ''), 80), v_phone, nullif(btrim(p->>'email'), ''), left(nullif(p->>'country', ''), 8),
          left(nullif(p->>'product', ''), 200), left(nullif(p->>'color', ''), 80), left(nullif(p->>'size', ''), 20), left(nullif(p->>'page_url', ''), 300))
  ON CONFLICT (external_ref) DO UPDATE SET
    reason = coalesce(EXCLUDED.reason, cc.reason), summary = coalesce(EXCLUDED.summary, cc.summary),
    transcript = CASE WHEN v_tr IS NOT NULL THEN EXCLUDED.transcript ELSE cc.transcript END,
    customer_name = coalesce(EXCLUDED.customer_name, cc.customer_name), phone = coalesce(EXCLUDED.phone, cc.phone),
    email = coalesce(EXCLUDED.email, cc.email), country = coalesce(EXCLUDED.country, cc.country),
    product_name = coalesce(EXCLUDED.product_name, cc.product_name), color = coalesce(EXCLUDED.color, cc.color),
    size = coalesce(EXCLUDED.size, cc.size), page_url = coalesce(EXCLUDED.page_url, cc.page_url),
    status = CASE WHEN cc.status IN ('resuelta', 'descartada') THEN 'nueva' ELSE cc.status END,   -- she wrote again
    updated_at = clock_timestamp()
  RETURNING * INTO c;
  IF v_new THEN PERFORM f360.case_email(c, 'nuevo');
  ELSIF prev.phone IS NULL AND c.phone IS NOT NULL THEN PERFORM f360.case_email(c, 'contacto'); END IF;
  RETURN jsonb_build_object('id', c.id, 'new', v_new);
END $$;

-- "A la medida" requests also live in the inbox (linked).
CREATE FUNCTION f360.case_from_custom_request() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  INSERT INTO f360.customer_cases (kind, source, custom_request_id, customer_name, phone, country, product_name, color, size, summary)
  VALUES ('a_la_medida', 'web_pdp', NEW.id, NEW.customer_name, NEW.phone, NEW.country, NEW.product_name, NEW.color_wanted,
          coalesce(NEW.size_wanted, CASE WHEN NEW.foot_cm IS NOT NULL THEN NEW.foot_cm || ' cm' END), NEW.note)
  ON CONFLICT (custom_request_id) DO NOTHING;
  RETURN NEW;
END $$;
CREATE TRIGGER custom_requests_case AFTER INSERT ON f360.custom_requests FOR EACH ROW EXECUTE FUNCTION f360.case_from_custom_request();

CREATE FUNCTION public.f360_inbox_list(p_days int DEFAULT 60) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles;
BEGIN
  r := f360.require_role('viewer');
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'kind', c.kind, 'source', c.source, 'status', c.status, 'reason', c.reason,
      'summary', c.summary, 'transcript', c.transcript, 'name', c.customer_name,
      'phone', CASE WHEN r.role IN ('owner', 'operator', 'seller') THEN c.phone ELSE '···' || right(c.phone, 4) END,
      'email', CASE WHEN r.role IN ('owner', 'operator') THEN c.email END, 'country', c.country,
      'product', c.product_name, 'color', c.color, 'size', c.size, 'page_url', c.page_url,
      'created_at', c.created_at, 'updated_at', c.updated_at, 'updated_by', c.updated_by)
      ORDER BY (c.status IN ('nueva', 'en_atencion')) DESC, c.updated_at DESC), '[]')
    FROM f360.customer_cases c WHERE c.created_at > now() - make_interval(days => greatest(1, least(p_days, 365))));
END $$;

CREATE FUNCTION public.f360_case_set(p_id uuid, p_status text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; c f360.customer_cases;
BEGIN
  r := f360.require_role('operator');
  IF p_status NOT IN ('nueva', 'en_atencion', 'resuelta', 'descartada') THEN RAISE EXCEPTION 'Estado no válido.'; END IF;
  UPDATE f360.customer_cases SET status = p_status, updated_at = clock_timestamp(), updated_by = r.display_name WHERE id = p_id RETURNING * INTO c;
  IF c.id IS NULL THEN RAISE EXCEPTION 'No encontrado.'; END IF;
  RETURN jsonb_build_object('id', c.id, 'status', c.status);
END $$;

REVOKE ALL ON f360.customer_cases FROM PUBLIC, anon, authenticated;
GRANT ALL ON f360.customer_cases TO service_role;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA f360 FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.f360_case_upsert(jsonb), public.f360_inbox_list(int), public.f360_case_set(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.f360_case_upsert(jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.f360_inbox_list(int), public.f360_case_set(uuid, text) TO authenticated, service_role;
