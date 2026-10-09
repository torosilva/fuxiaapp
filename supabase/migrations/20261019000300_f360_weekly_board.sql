-- Fuxia 360 · Pendientes de la semana (Mario 2026-10-08: "lo de los pendientes sí, y que existan tarjetas… cada quien llena sus
-- tarjetas pero no deben de tener acceso a nada de todo lo demás"). Brings the "Tablero semanal Q4" (claude.ai artifact, 19 Sep)
-- into Fuxia 360. ADDITIVE.
--   · f360.weekly_people: AGENCIA, CAROLINA, MARIO — identified by their WhatsApp (normalized), like the sellers' sign-in.
--     A person here gets NO Fuxia 360 role: the agency can open /pendientes and nothing else (every other RPC refuses).
--   · f360.weekly_plan: the Q4 plan (15 weeks, goal 200 pairs ONLINE oct–dec), same weeks/targets/focus as the artifact.
--   · f360.weekly_cards: one card per person per week (commitment, what was really done, numbers, met yes/partial/no).
--     Each person edits ONLY their own card. Every change is kept in f360.weekly_changes (append-only).
--   · f360.weekly_metrics: the 5 numbers of the week + the decision — Carolina / Mario only.
--   · Online pairs are COUNTED, not typed: from f360.sales_facts channel 'online' (online-store orders = agency's
--     "sitio cierra solo"; remote WhatsApp sales = Carolina's "DM / manual").
-- Rollback: supabase/rollbacks/20261019000300_f360_weekly_board.down.sql

CREATE TABLE f360.weekly_people (
  person_key  text PRIMARY KEY CHECK (person_key IN ('AGENCIA', 'CAROLINA', 'MARIO')),
  name        text NOT NULL,
  role_line   text NOT NULL,
  phone       text UNIQUE,                         -- f360.normalize_phone; NULL = not set yet
  active      boolean NOT NULL DEFAULT true,
  updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE f360.weekly_plan (
  week_id       text PRIMARY KEY,
  starts_on     date NOT NULL UNIQUE,
  ends_on       date NOT NULL,
  label         text NOT NULL,
  title         text NOT NULL,
  focus         text NOT NULL,
  target_pairs  int NOT NULL CHECK (target_pairs >= 0),
  in_goal       boolean NOT NULL DEFAULT true
);
CREATE TABLE f360.weekly_cards (
  week_id     text NOT NULL REFERENCES f360.weekly_plan(week_id) ON DELETE RESTRICT,
  person_key  text NOT NULL REFERENCES f360.weekly_people(person_key) ON DELETE RESTRICT,
  commitment  text,
  done        text,
  numbers     jsonb NOT NULL DEFAULT '{}',
  status      text CHECK (status IN ('si', 'parcial', 'no')),
  updated_by  text NOT NULL,
  updated_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (week_id, person_key)
);
CREATE TABLE f360.weekly_metrics (
  week_id     text PRIMARY KEY REFERENCES f360.weekly_plan(week_id) ON DELETE RESTRICT,
  metric_values jsonb NOT NULL DEFAULT '{}',
  decision    text,
  updated_by  text NOT NULL,
  updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE f360.weekly_changes (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  week_id    text NOT NULL,
  what       text NOT NULL,                        -- person_key of the card, or 'METRICS'
  before     jsonb,
  after      jsonb NOT NULL,
  by_name    text NOT NULL,
  at         timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER weekly_changes_append_only BEFORE UPDATE OR DELETE ON f360.weekly_changes FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();
ALTER TABLE f360.weekly_people ENABLE ROW LEVEL SECURITY;
ALTER TABLE f360.weekly_plan ENABLE ROW LEVEL SECURITY;
ALTER TABLE f360.weekly_cards ENABLE ROW LEVEL SECURITY;
ALTER TABLE f360.weekly_metrics ENABLE ROW LEVEL SECURITY;
ALTER TABLE f360.weekly_changes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON f360.weekly_people, f360.weekly_plan, f360.weekly_cards, f360.weekly_metrics, f360.weekly_changes FROM PUBLIC, anon, authenticated;
GRANT ALL ON f360.weekly_people, f360.weekly_plan, f360.weekly_cards, f360.weekly_metrics, f360.weekly_changes TO service_role;

INSERT INTO f360.weekly_people (person_key, name, role_line) VALUES
  ('AGENCIA', 'Agencia', 'Habilita. Su número: que el sitio pueda cobrar y medir.'),
  ('CAROLINA', 'Carolina', 'Cierra. Su número: pares que se cobran por su gestión.'),
  ('MARIO', 'Mario', 'Destraba. Su número: bloqueadores cerrados a tiempo.');

INSERT INTO f360.weekly_plan (week_id, starts_on, ends_on, label, title, focus, target_pairs, in_goal) VALUES
 ('s00','2026-09-22','2026-09-28','22–28 sep','Rescate de septiembre (fuera de los 200)','Arreglo ePayco + prueba de compra en /co/. WhatsApp a los 6 cancelados (COP$2,328,000) y a los 63 borradores. Reactivar Instagram Ads.',0,false),
 ('s01','2026-09-29','2026-10-05','29 sep–5 oct','Cerrar la fuga de región','Todos los anuncios a /mx/tienda/ y /co/tienda/. Default de moneda por geolocalización. Conseguir acceso a la cuenta publicitaria real.',8,true),
 ('s02','2026-10-06','2026-10-12','6–12 oct','Instrumentar el checkout','add_shipping_info, add_payment_info y purchase con currency. Disparar purchase al retorno de ePayco — Colombia es el 52% del tráfico y el 0% de la medición.',10,true),
 ('s03','2026-10-13','2026-10-19','13–19 oct','Encender retargeting','Campaña a los ~2,000 carritos, $150–200 MXN/día. Auto-reply inmediato en IG. Pauta solo a Ballerinas y botas.',14,true),
 ('s04','2026-10-20','2026-10-26','20–26 oct','Stock y oferta de noviembre','Orden de inventario de Ballerinas y botas para Buen Fin. Definir el piso de descuento (hoy 46% de pedidos ya lleva cupón).',18,true),
 ('s05','2026-10-27','2026-11-02','27 oct–2 nov','Preparar el mes grande','Creatividades de Buen Fin y Black Friday. MSI en Mercado Pago (MX) y PSE/efectivo verificado (CO). Lista propia caliente.',12,true),
 ('s06','2026-11-03','2026-11-09','3–9 nov','Calentamiento','Preventa a lista propia. Reseñas y UGC de compradoras de agosto-octubre. Prueba de carga del checkout.',16,true),
 ('s07','2026-11-10','2026-11-16','10–16 nov','BUEN FIN (MX)','La semana que decide el trimestre en México. Todo el presupuesto y toda la atención aquí.',24,true),
 ('s08','2026-11-17','2026-11-23','17–23 nov','Rescate post Buen Fin','Carritos del Buen Fin a las 1h/24h/72h. Reposición de tallas agotadas.',12,true),
 ('s09','2026-11-24','2026-11-30','24–30 nov','BLACK FRIDAY (CO)','27 nov. Colombia con la pasarela ya probada. Cyber Monday de cierre.',16,true),
 ('s10','2026-12-01','2026-12-07','1–7 dic','Modo regalo','Campaña de regalo: cambio de talla garantizado hasta el 15 de enero. Comunicar corte de envío.',18,true),
 ('s11','2026-12-08','2026-12-14','8–14 dic','Pico navideño','Retargeting a todo diciembre. Recompra a las compradoras de Buen Fin.',20,true),
 ('s12','2026-12-15','2026-12-21','15–21 dic','Última llamada','Corte de envío ~18–20 dic. Urgencia real, no inventada.',22,true),
 ('s13','2026-12-22','2026-12-28','22–28 dic','Post-navidad','Tarjeta digital y venta a lista propia. Cambios de talla.',8,true),
 ('s14','2026-12-29','2026-12-31','29–31 dic','Cierre','Cerrar números. Qué funcionó de verdad para el plan de Q1.',2,true);

-- Who is calling: the weekly person whose WhatsApp is the caller's (customers row linked to the auth user).
CREATE FUNCTION f360.weekly_actor() RETURNS f360.weekly_people LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT p.* FROM f360.weekly_people p
  WHERE p.active AND p.phone IS NOT NULL AND auth.uid() IS NOT NULL
    AND EXISTS (SELECT 1 FROM public.customers c WHERE c.auth_user_id = auth.uid() AND f360.normalize_phone(c.phone) = p.phone)
  LIMIT 1
$$;
REVOKE ALL ON FUNCTION f360.weekly_actor() FROM PUBLIC, anon, authenticated;

-- Online pairs per week, counted from sales: online-store orders (agency) and remote/DM sales (Carolina).
CREATE FUNCTION f360.weekly_online_pairs(p_from date, p_to date) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT jsonb_build_object(
    'site', coalesce(sum(units) FILTER (WHERE source = 'woo'), 0),
    'dm',   coalesce(sum(units) FILTER (WHERE source <> 'woo'), 0),
    'total', coalesce(sum(units), 0))
  FROM f360.sales_facts
  WHERE channel = 'online'
    AND (occurred_at AT TIME ZONE 'America/Mexico_City')::date BETWEEN p_from AND p_to
$$;
REVOKE ALL ON FUNCTION f360.weekly_online_pairs(date, date) FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.f360_weekly_me() RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE p f360.weekly_people := f360.weekly_actor(); team boolean := EXISTS (SELECT 1 FROM f360.user_roles WHERE auth_user_id = auth.uid() AND role IN ('owner', 'operator'));
BEGIN
  IF p.person_key IS NULL AND NOT team THEN RETURN jsonb_build_object('ok', false); END IF;
  RETURN jsonb_build_object('ok', true, 'person_key', p.person_key, 'name', p.name, 'team', team,
    'can_edit_metrics', p.person_key IN ('CAROLINA', 'MARIO'));
END $$;

CREATE FUNCTION public.f360_weekly_board(p_week text DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE p f360.weekly_people := f360.weekly_actor(); team boolean := EXISTS (SELECT 1 FROM f360.user_roles WHERE auth_user_id = auth.uid() AND role IN ('owner', 'operator'));
  today date := (now() AT TIME ZONE 'America/Mexico_City')::date; w f360.weekly_plan; total int := 0; plan_to_date int := 0; r record;
BEGIN
  IF p.person_key IS NULL AND NOT team THEN RAISE EXCEPTION 'No disponible.' USING ERRCODE = 'insufficient_privilege'; END IF;
  SELECT * INTO w FROM f360.weekly_plan WHERE week_id = p_week;
  IF w.week_id IS NULL THEN
    SELECT * INTO w FROM f360.weekly_plan WHERE starts_on <= today ORDER BY starts_on DESC LIMIT 1;
    IF w.week_id IS NULL THEN SELECT * INTO w FROM f360.weekly_plan ORDER BY starts_on LIMIT 1; END IF;
  END IF;
  FOR r IN SELECT * FROM f360.weekly_plan WHERE in_goal LOOP
    total := total + (f360.weekly_online_pairs(r.starts_on, r.ends_on)->>'total')::int;
    IF r.starts_on <= today THEN plan_to_date := plan_to_date + r.target_pairs; END IF;
  END LOOP;
  RETURN jsonb_build_object(
    'me', jsonb_build_object('person_key', p.person_key, 'team', team, 'can_edit_metrics', p.person_key IN ('CAROLINA', 'MARIO')),
    'goal', jsonb_build_object('target', 200, 'online_pairs', total, 'plan_to_date', plan_to_date,
                               'weeks_left', (SELECT count(*) FROM f360.weekly_plan WHERE in_goal AND starts_on > today)),
    'weeks', (SELECT jsonb_agg(jsonb_build_object('id', x.week_id, 'label', x.label, 'current', x.starts_on <= today AND x.ends_on >= today,
                 'filled', EXISTS (SELECT 1 FROM f360.weekly_cards c WHERE c.week_id = x.week_id)) ORDER BY x.starts_on) FROM f360.weekly_plan x),
    'week', jsonb_build_object('id', w.week_id, 'label', w.label, 'title', w.title, 'focus', w.focus, 'target_pairs', w.target_pairs,
                               'in_goal', w.in_goal, 'online', f360.weekly_online_pairs(w.starts_on, w.ends_on)),
    'cards', (SELECT jsonb_agg(jsonb_build_object('person_key', pp.person_key, 'name', pp.name, 'role_line', pp.role_line,
                 'mine', pp.person_key = p.person_key, 'commitment', c.commitment, 'done', c.done, 'numbers', coalesce(c.numbers, '{}'),
                 'status', c.status, 'updated_by', c.updated_by, 'updated_at', c.updated_at)
               ORDER BY array_position(ARRAY['AGENCIA', 'CAROLINA', 'MARIO'], pp.person_key))
              FROM f360.weekly_people pp LEFT JOIN f360.weekly_cards c ON c.week_id = w.week_id AND c.person_key = pp.person_key
              WHERE pp.active),
    'metrics', (SELECT jsonb_build_object('values', m.metric_values, 'decision', m.decision, 'updated_by', m.updated_by, 'updated_at', m.updated_at)
                FROM f360.weekly_metrics m WHERE m.week_id = w.week_id));
END $$;

CREATE FUNCTION public.f360_weekly_card_save(p_week text, p_commitment text, p_done text, p_numbers jsonb, p_status text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE p f360.weekly_people := f360.weekly_actor(); allowed text[]; k text; prev f360.weekly_cards; nums jsonb := coalesce(p_numbers, '{}');
BEGIN
  IF p.person_key IS NULL THEN RAISE EXCEPTION 'Solo puedes llenar tu propia tarjeta.' USING ERRCODE = 'insufficient_privilege'; END IF;
  IF NOT EXISTS (SELECT 1 FROM f360.weekly_plan WHERE week_id = p_week) THEN RAISE EXCEPTION 'Semana no válida.'; END IF;
  IF p_status IS NOT NULL AND p_status NOT IN ('si', 'parcial', 'no') THEN RAISE EXCEPTION 'Estado no válido.'; END IF;
  IF length(coalesce(p_commitment, '')) > 2000 OR length(coalesce(p_done, '')) > 2000 THEN RAISE EXCEPTION 'Texto demasiado largo.'; END IF;
  allowed := CASE p.person_key WHEN 'CAROLINA' THEN ARRAY['rescued', 'pieces'] WHEN 'MARIO' THEN ARRAY['blockers'] ELSE ARRAY[]::text[] END;
  IF jsonb_typeof(nums) <> 'object' THEN RAISE EXCEPTION 'Números no válidos.'; END IF;
  FOR k IN SELECT jsonb_object_keys(nums) LOOP
    IF NOT k = ANY (allowed) THEN RAISE EXCEPTION 'Ese número no es de tu tarjeta (%).', k; END IF;
    IF jsonb_typeof(nums->k) NOT IN ('number', 'null') OR coalesce((nums->>k)::numeric, 0) < 0 OR coalesce((nums->>k)::numeric, 0) > 10000 THEN
      RAISE EXCEPTION 'Número no válido (%).', k;
    END IF;
  END LOOP;
  SELECT * INTO prev FROM f360.weekly_cards WHERE week_id = p_week AND person_key = p.person_key FOR UPDATE;
  INSERT INTO f360.weekly_cards (week_id, person_key, commitment, done, numbers, status, updated_by, updated_at)
    VALUES (p_week, p.person_key, nullif(btrim(p_commitment), ''), nullif(btrim(p_done), ''), nums, p_status, p.name, now())
  ON CONFLICT (week_id, person_key) DO UPDATE SET commitment = EXCLUDED.commitment, done = EXCLUDED.done, numbers = EXCLUDED.numbers,
    status = EXCLUDED.status, updated_by = EXCLUDED.updated_by, updated_at = now();
  INSERT INTO f360.weekly_changes (week_id, what, before, after, by_name)
    VALUES (p_week, p.person_key, CASE WHEN prev.week_id IS NULL THEN NULL ELSE to_jsonb(prev) END,
            (SELECT to_jsonb(c) FROM f360.weekly_cards c WHERE c.week_id = p_week AND c.person_key = p.person_key), p.name);
  RETURN jsonb_build_object('ok', true);
END $$;

CREATE FUNCTION public.f360_weekly_metrics_save(p_week text, p_values jsonb, p_decision text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE p f360.weekly_people := f360.weekly_actor(); k text; prev f360.weekly_metrics; v jsonb := coalesce(p_values, '{}');
BEGIN
  IF p.person_key IS NULL OR p.person_key NOT IN ('CAROLINA', 'MARIO') THEN RAISE EXCEPTION 'Solo Carolina o Mario.' USING ERRCODE = 'insufficient_privilege'; END IF;
  IF NOT EXISTS (SELECT 1 FROM f360.weekly_plan WHERE week_id = p_week) THEN RAISE EXCEPTION 'Semana no válida.'; END IF;
  IF jsonb_typeof(v) <> 'object' THEN RAISE EXCEPTION 'Números no válidos.'; END IF;
  FOR k IN SELECT jsonb_object_keys(v) LOOP
    IF NOT k = ANY (ARRAY['conv', 'cop_pct', 'prefix_pct', 'roas', 'first_response_min', 'dms_per_day']) THEN RAISE EXCEPTION 'Número desconocido (%).', k; END IF;
    IF jsonb_typeof(v->k) NOT IN ('number', 'null') THEN RAISE EXCEPTION 'Número no válido (%).', k; END IF;
  END LOOP;
  IF length(coalesce(p_decision, '')) > 2000 THEN RAISE EXCEPTION 'Texto demasiado largo.'; END IF;
  SELECT * INTO prev FROM f360.weekly_metrics WHERE week_id = p_week FOR UPDATE;
  INSERT INTO f360.weekly_metrics (week_id, metric_values, decision, updated_by, updated_at) VALUES (p_week, v, nullif(btrim(p_decision), ''), p.name, now())
  ON CONFLICT (week_id) DO UPDATE SET metric_values = EXCLUDED.metric_values, decision = EXCLUDED.decision, updated_by = EXCLUDED.updated_by, updated_at = now();
  INSERT INTO f360.weekly_changes (week_id, what, before, after, by_name)
    VALUES (p_week, 'METRICS', CASE WHEN prev.week_id IS NULL THEN NULL ELSE to_jsonb(prev) END,
            (SELECT to_jsonb(m) FROM f360.weekly_metrics m WHERE m.week_id = p_week), p.name);
  RETURN jsonb_build_object('ok', true);
END $$;

-- Owners set the WhatsApp of each person (the agency's included). Never by name.
CREATE FUNCTION public.f360_weekly_person_set(p_person_key text, p_phone text, p_name text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('owner'); ph text := f360.normalize_phone(p_phone, 'MX');
BEGIN
  IF ph IS NULL THEN RAISE EXCEPTION 'Escribe un WhatsApp válido (10 dígitos).'; END IF;
  UPDATE f360.weekly_people SET phone = ph, name = coalesce(nullif(btrim(p_name), ''), name), updated_at = now() WHERE person_key = p_person_key;
  IF NOT FOUND THEN RAISE EXCEPTION 'Persona no válida.'; END IF;
  INSERT INTO f360.weekly_changes (week_id, what, before, after, by_name)
    VALUES ('-', 'PERSON:' || p_person_key, NULL, jsonb_build_object('phone_last4', right(ph, 4), 'name', p_name), r.display_name);
  RETURN jsonb_build_object('ok', true);
END $$;

REVOKE ALL ON FUNCTION public.f360_weekly_me(), public.f360_weekly_board(text), public.f360_weekly_card_save(text, text, text, jsonb, text),
  public.f360_weekly_metrics_save(text, jsonb, text), public.f360_weekly_person_set(text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_weekly_me(), public.f360_weekly_board(text), public.f360_weekly_card_save(text, text, text, jsonb, text),
  public.f360_weekly_metrics_save(text, jsonb, text), public.f360_weekly_person_set(text, text, text) TO authenticated, service_role;
