-- Fuxia 360 · Growth P0-B Registro de experimentos (Mario 2026-10-27, solo staging). Implements docs/fuxia360/growth/06_EXPERIMENTS.md
-- as designed (table §2, states §3, security §4, measurement §5). ADDITIVE: 2 tables + RPCs; no change to existing objects.
-- Points the design left open, closed here (flagged in the delivery doc):
--   · "fijados antes de comenzar" (Mario): hypothesis, responsible, budget, KPI, thresholds, market, campaigns and dates are
--     frozen from APPROVED (the design froze thresholds from RUNNING); any change after approval is refused → new experiment;
--   · proposed_by / responsible: who recommended it and who executes it (mario, carolina, goyo, agencia, ia, otro), so every
--     party is judged with the same rules; the track record per party is part of the list;
--   · KPIs measurable today only from PAID Woo orders and Meta spend: paid_orders, net_revenue, cost_per_paid_order. Others in
--     §5 (favorites, ATC, …) are refused until their data exists — never a number the server cannot compute;
--   · verdict is not free: WINNER only if the success threshold was met with the minimum sample, LOSER only if the kill
--     threshold was met; anything else is INCONCLUSIVE. The result is computed by the server at closing and stored as a snapshot;
--   · evidence is labelled: attribution OBSERVED (last click of the order) or market before/after; never "causal" (no control group).
-- Rollback: supabase/rollbacks/20261104000200_f360_growth_experiments.down.sql

CREATE SEQUENCE f360.growth_experiment_seq;

CREATE TABLE f360.growth_experiments (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code              text NOT NULL UNIQUE,
  name              text NOT NULL CHECK (length(btrim(name)) BETWEEN 3 AND 140),
  hypothesis        text NOT NULL CHECK (length(btrim(hypothesis)) BETWEEN 20 AND 2000),
  market            text NOT NULL CHECK (market IN ('MX', 'CO', 'ROW', 'ALL')),
  channel           text CHECK (channel IS NULL OR length(channel) <= 60),
  audience          text CHECK (audience IS NULL OR length(audience) <= 300),
  product_key       text CHECK (product_key IS NULL OR product_key ~ '^F360-[A-Z0-9-]{1,40}$'),
  product_id        uuid REFERENCES f360.products(id) ON DELETE RESTRICT,
  creative_ref      text CHECK (creative_ref IS NULL OR length(creative_ref) <= 200),
  primary_variable  text NOT NULL CHECK (length(btrim(primary_variable)) BETWEEN 3 AND 200),
  proposed_by       text NOT NULL CHECK (proposed_by IN ('mario', 'carolina', 'goyo', 'agencia', 'ia', 'otro')),
  responsible       text NOT NULL CHECK (responsible IN ('mario', 'carolina', 'goyo', 'agencia', 'ia', 'otro')),
  responsible_note  text CHECK (responsible_note IS NULL OR length(responsible_note) <= 140),
  start_date        date,
  end_date          date,                                                 -- planned end = review date
  budget            numeric(14,2) CHECK (budget IS NULL OR budget >= 0),
  budget_currency   text CHECK (budget_currency IS NULL OR budget_currency IN ('MXN', 'COP', 'USD')),
  primary_kpi       text NOT NULL CHECK (primary_kpi IN ('paid_orders', 'net_revenue', 'cost_per_paid_order')),
  secondary_kpis    text[] NOT NULL DEFAULT '{}',
  success_threshold jsonb,
  kill_threshold    jsonb,
  campaign_ids      text[] NOT NULL DEFAULT '{}' CHECK (array_length(campaign_ids, 1) IS NULL OR array_length(campaign_ids, 1) <= 30),
  utm_campaign      text CHECK (utm_campaign IS NULL OR length(utm_campaign) <= 200),
  status            text NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT', 'APPROVED', 'RUNNING', 'WINNER', 'LOSER', 'INCONCLUSIVE', 'STOPPED', 'ARCHIVED')),
  verdict           text CHECK (verdict IS NULL OR verdict IN ('WINNER', 'LOSER', 'INCONCLUSIVE', 'STOPPED')),   -- kept after ARCHIVED
  result            jsonb,
  learning          text CHECK (learning IS NULL OR length(learning) <= 2000),
  decision          text CHECK (decision IS NULL OR decision IN ('SCALE', 'ITERATE', 'KILL', 'NONE')),
  stop_reason       text CHECK (stop_reason IS NULL OR length(stop_reason) <= 500),
  created_by        uuid NOT NULL,
  created_by_name   text NOT NULL,
  approved_by       uuid,
  approved_by_name  text,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  approved_at       timestamptz,
  started_at        timestamptz,
  ended_at          timestamptz,
  CHECK (end_date IS NULL OR start_date IS NULL OR end_date >= start_date),
  CHECK ((budget IS NULL) = (budget_currency IS NULL))
);
COMMENT ON TABLE f360.growth_experiments IS 'Growth P0-B (06_EXPERIMENTS.md): hypothesis → approval → run → verdict from PAID Woo orders. Nothing is deleted.';

CREATE TABLE f360.growth_experiment_changes (
  id            bigserial PRIMARY KEY,
  experiment_id uuid NOT NULL REFERENCES f360.growth_experiments(id) ON DELETE RESTRICT,
  from_status   text,
  to_status     text,
  field         text,
  old           jsonb,
  new           jsonb,
  actor         uuid,
  actor_name    text NOT NULL,
  reason        text CHECK (reason IS NULL OR length(reason) <= 500),
  at            timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX growth_experiment_changes_exp_idx ON f360.growth_experiment_changes (experiment_id, id);

CREATE FUNCTION f360.growth_experiment_changes_append_only() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'La bitácora de experimentos no se edita ni se borra.'; END $$;
CREATE TRIGGER growth_experiment_changes_no_update BEFORE UPDATE OR DELETE ON f360.growth_experiment_changes
  FOR EACH ROW EXECUTE FUNCTION f360.growth_experiment_changes_append_only();
CREATE TRIGGER growth_experiments_no_delete BEFORE DELETE ON f360.growth_experiments
  FOR EACH ROW EXECUTE FUNCTION f360.growth_experiment_changes_append_only();

-- Threshold = {"op": ">=" | "<=", "value": number ≥ 0, "min_sample": integer ≥ 1} (the KPI is the experiment's primary KPI).
CREATE FUNCTION f360.growth_threshold_error(p jsonb) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN p IS NULL OR jsonb_typeof(p) <> 'object' THEN 'falta el umbral'
    WHEN p->>'op' NOT IN ('>=', '<=') THEN 'el operador debe ser >= o <='
    WHEN jsonb_typeof(p->'value') <> 'number' OR (p->>'value')::numeric < 0 THEN 'el valor debe ser un número ≥ 0'
    WHEN jsonb_typeof(p->'min_sample') <> 'number' OR (p->>'min_sample')::numeric < 1 OR (p->>'min_sample')::numeric <> trunc((p->>'min_sample')::numeric) THEN 'la muestra mínima debe ser un entero ≥ 1'
    WHEN EXISTS (SELECT 1 FROM jsonb_object_keys(p) k WHERE k NOT IN ('op', 'value', 'min_sample')) THEN 'el umbral solo lleva op, value y min_sample'
  END
$$;

-- Server-side measurement (never from the client). Window = start_date .. the earliest of planned end, closing day and today.
CREATE FUNCTION f360.growth_experiment_measure(e f360.growth_experiments) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE today date := (now() AT TIME ZONE 'America/Mexico_City')::date;
  d_from date := e.start_date; d_to date; len int; f timestamptz; t timestamptz; bf timestamptz;
  scoped boolean := cardinality(e.campaign_ids) > 0 OR e.utm_campaign IS NOT NULL;
  m_orders int; m_rev jsonb; b_orders int; s_orders int; s_rev jsonb; s_rev_n numeric; spend numeric; spend_cur_ok boolean; kpi numeric; sample int;
  succ boolean; kill boolean; cur text := CASE e.market WHEN 'CO' THEN 'COP' WHEN 'ROW' THEN 'USD' WHEN 'MX' THEN 'MXN' END;
BEGIN
  IF d_from IS NULL THEN RETURN jsonb_build_object('status', 'SIN_FECHA'); END IF;
  d_to := least(coalesce(e.end_date, today), coalesce((e.ended_at AT TIME ZONE 'America/Mexico_City')::date, today), today);   -- the review date fixed at approval; earlier if stopped
  IF d_to < d_from THEN RETURN jsonb_build_object('status', 'NO_EMPEZADO', 'from', d_from); END IF;
  len := d_to - d_from + 1;
  f := d_from::timestamp AT TIME ZONE 'America/Mexico_City'; t := (d_to + 1)::timestamp AT TIME ZONE 'America/Mexico_City';
  bf := (d_from - len)::timestamp AT TIME ZONE 'America/Mexico_City';

  WITH o AS (
    SELECT o.market, o.net_product, o.occurred_at, nullif(coalesce(a.utm_id, a.utm_campaign), '') AS campaign_key, a.utm_campaign
    FROM f360.commerce_orders o LEFT JOIN f360.commerce_woo_attribution a ON a.target_id = o.target_id AND a.woo_order_id = o.woo_order_id
    WHERE o.source_system = 'woo' AND o.status_class = 'countable' AND o.occurred_at >= bf AND o.occurred_at < t
      AND (e.market = 'ALL' OR o.market = e.market)
  )
  SELECT count(*) FILTER (WHERE occurred_at >= f),
         (SELECT coalesce(jsonb_object_agg(c, v), '{}') FROM (SELECT CASE o2.market WHEN 'CO' THEN 'COP' WHEN 'ROW' THEN 'USD' ELSE 'MXN' END c, sum(o2.net_product) v
            FROM o o2 WHERE o2.occurred_at >= f GROUP BY 1) q),
         count(*) FILTER (WHERE occurred_at < f),
         count(*) FILTER (WHERE occurred_at >= f AND scoped AND (campaign_key = ANY (e.campaign_ids) OR (e.utm_campaign IS NOT NULL AND utm_campaign = e.utm_campaign))),
         (SELECT coalesce(jsonb_object_agg(c, v), '{}') FROM (SELECT CASE o2.market WHEN 'CO' THEN 'COP' WHEN 'ROW' THEN 'USD' ELSE 'MXN' END c, sum(o2.net_product) v
            FROM o o2 WHERE o2.occurred_at >= f AND scoped AND (o2.campaign_key = ANY (e.campaign_ids) OR (e.utm_campaign IS NOT NULL AND o2.utm_campaign = e.utm_campaign)) GROUP BY 1) q)
    INTO m_orders, m_rev, b_orders, s_orders, s_rev FROM o;

  IF cardinality(e.campaign_ids) > 0 THEN
    SELECT sum(sd.spend), bool_and(sd.currency = 'MXN') INTO spend, spend_cur_ok FROM f360.marketing_spend_daily sd
      WHERE sd.platform = 'meta' AND sd.campaign_id = ANY (e.campaign_ids) AND sd.date >= d_from AND sd.date <= d_to AND (e.market = 'ALL' OR sd.market = e.market);
  END IF;

  sample := CASE WHEN scoped THEN s_orders ELSE m_orders END;
  s_rev_n := CASE WHEN cur IS NULL THEN NULL ELSE ((CASE WHEN scoped THEN s_rev ELSE m_rev END)->>cur)::numeric END;
  kpi := CASE e.primary_kpi
    WHEN 'paid_orders' THEN sample
    WHEN 'net_revenue' THEN coalesce(s_rev_n, CASE WHEN cur IS NOT NULL THEN 0 END)                    -- ALL markets: not summed across currencies
    WHEN 'cost_per_paid_order' THEN CASE WHEN spend_cur_ok AND s_orders > 0 THEN round(spend / s_orders, 2) END END;
  succ := kpi IS NOT NULL AND sample >= (e.success_threshold->>'min_sample')::int
          AND CASE e.success_threshold->>'op' WHEN '>=' THEN kpi >= (e.success_threshold->>'value')::numeric ELSE kpi <= (e.success_threshold->>'value')::numeric END;
  kill := kpi IS NOT NULL AND sample >= (e.kill_threshold->>'min_sample')::int
          AND CASE e.kill_threshold->>'op' WHEN '>=' THEN kpi >= (e.kill_threshold->>'value')::numeric ELSE kpi <= (e.kill_threshold->>'value')::numeric END;
  -- cost per sale with spend and zero attributed sales: the kill side of a "<=" cost goal is met once spend exceeds the kill value
  IF e.primary_kpi = 'cost_per_paid_order' AND kpi IS NULL AND spend_cur_ok AND coalesce(s_orders, 0) = 0 AND e.kill_threshold->>'op' = '>=' AND spend >= (e.kill_threshold->>'value')::numeric THEN
    kill := true;
  END IF;

  RETURN jsonb_build_object(
    'status', 'OK', 'from', d_from, 'to', d_to, 'days', len, 'measured_at', now(),
    'kpi', e.primary_kpi, 'kpi_value', kpi, 'kpi_currency', CASE WHEN e.primary_kpi = 'net_revenue' THEN cur WHEN e.primary_kpi = 'cost_per_paid_order' THEN 'MXN' END,
    'sample', sample, 'success_met', coalesce(succ, false), 'kill_met', coalesce(kill, false),
    'market_paid_orders', m_orders, 'market_revenue', m_rev, 'baseline_paid_orders', b_orders,
    'baseline_period', jsonb_build_array(d_from - len, d_from - 1),
    'attributed_paid_orders', CASE WHEN scoped THEN s_orders END, 'attributed_revenue', CASE WHEN scoped THEN s_rev END,
    'spend_mxn', spend, 'spend_status', CASE WHEN cardinality(e.campaign_ids) = 0 THEN 'SIN_CAMPAÑAS' WHEN spend IS NULL THEN 'SIN_DATOS' WHEN NOT spend_cur_ok THEN 'OTRA_MONEDA' ELSE 'OK' END,
    'evidence', CASE WHEN scoped THEN 'atribucion_observada' ELSE 'antes_despues_mercado' END,
    'evidence_note', CASE WHEN scoped
      THEN 'Ventas pagadas cuyo último clic fue la campaña del experimento (atribución observada). No demuestra causalidad: no hay grupo de control.'
      ELSE 'Ventas pagadas del mercado durante el experimento contra el mismo número de días justo antes. Es una comparación antes/después: no demuestra causalidad.' END,
    'source', 'Pedidos pagados de WooCommerce (f360.commerce_orders) · gasto de Meta (f360.marketing_spend_daily)');
END $$;

-- Writable fields while DRAFT (create when p_id IS NULL). Identity from the session, never the payload.
CREATE FUNCTION public.f360_experiment_save(p_id uuid, p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('operator'); e f360.growth_experiments; n f360.growth_experiments; k text; v_id uuid;
  allowed text[] := ARRAY['name', 'hypothesis', 'market', 'channel', 'audience', 'product_key', 'creative_ref', 'primary_variable', 'proposed_by', 'responsible',
    'responsible_note', 'start_date', 'end_date', 'budget', 'budget_currency', 'primary_kpi', 'success_threshold', 'kill_threshold', 'campaign_ids', 'utm_campaign'];
BEGIN
  IF jsonb_typeof(p) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'Datos no válidos.'; END IF;
  FOR k IN SELECT jsonb_object_keys(p) LOOP
    IF NOT k = ANY (allowed) THEN RAISE EXCEPTION 'Campo no permitido: %', k; END IF;
  END LOOP;
  IF p ? 'success_threshold' AND p->'success_threshold' <> 'null'::jsonb AND f360.growth_threshold_error(p->'success_threshold') IS NOT NULL THEN
    RAISE EXCEPTION 'Meta de éxito: %', f360.growth_threshold_error(p->'success_threshold'); END IF;
  IF p ? 'kill_threshold' AND p->'kill_threshold' <> 'null'::jsonb AND f360.growth_threshold_error(p->'kill_threshold') IS NOT NULL THEN
    RAISE EXCEPTION 'Criterio para cancelar: %', f360.growth_threshold_error(p->'kill_threshold'); END IF;
  IF p ? 'campaign_ids' AND (jsonb_typeof(p->'campaign_ids') <> 'array' OR EXISTS (SELECT 1 FROM jsonb_array_elements_text(p->'campaign_ids') c WHERE c !~ '^\d{5,25}$')) THEN
    RAISE EXCEPTION 'Las campañas son IDs numéricos de Meta.'; END IF;

  IF p_id IS NULL THEN
    INSERT INTO f360.growth_experiments (code, name, hypothesis, market, primary_variable, proposed_by, responsible, primary_kpi, created_by, created_by_name)
    VALUES ('EXP-' || to_char(now() AT TIME ZONE 'America/Mexico_City', 'YYYY') || '-' || lpad(nextval('f360.growth_experiment_seq')::text, 3, '0'),
            p->>'name', p->>'hypothesis', p->>'market', p->>'primary_variable', p->>'proposed_by', p->>'responsible', p->>'primary_kpi', r.auth_user_id, r.display_name)
    RETURNING id INTO v_id;
    INSERT INTO f360.growth_experiment_changes (experiment_id, to_status, actor, actor_name, reason) VALUES (v_id, 'DRAFT', r.auth_user_id, r.display_name, 'creado');
  ELSE
    v_id := p_id;
  END IF;
  SELECT * INTO e FROM f360.growth_experiments WHERE id = v_id FOR UPDATE;
  IF e.id IS NULL THEN RAISE EXCEPTION 'Experimento no encontrado.'; END IF;
  IF e.status <> 'DRAFT' THEN RAISE EXCEPTION 'Solo se edita en borrador. Después de aprobado no cambia nada: crea un experimento nuevo.'; END IF;

  n := jsonb_populate_record(e, p - 'campaign_ids');
  IF p ? 'campaign_ids' THEN n.campaign_ids := ARRAY(SELECT jsonb_array_elements_text(p->'campaign_ids')); END IF;
  FOR k IN SELECT jsonb_object_keys(p) LOOP
    IF to_jsonb(e)->k IS DISTINCT FROM to_jsonb(n)->k AND p_id IS NOT NULL THEN
      INSERT INTO f360.growth_experiment_changes (experiment_id, from_status, to_status, field, old, new, actor, actor_name)
        VALUES (e.id, 'DRAFT', 'DRAFT', k, to_jsonb(e)->k, to_jsonb(n)->k, r.auth_user_id, r.display_name);
    END IF;
  END LOOP;
  UPDATE f360.growth_experiments SET name = n.name, hypothesis = n.hypothesis, market = n.market, channel = n.channel, audience = n.audience,
      product_key = n.product_key, product_id = (SELECT id FROM f360.products WHERE code = n.product_key), creative_ref = n.creative_ref,
      primary_variable = n.primary_variable, proposed_by = n.proposed_by, responsible = n.responsible, responsible_note = n.responsible_note,
      start_date = n.start_date, end_date = n.end_date, budget = n.budget, budget_currency = n.budget_currency, primary_kpi = n.primary_kpi,
      success_threshold = n.success_threshold, kill_threshold = n.kill_threshold, campaign_ids = n.campaign_ids, utm_campaign = n.utm_campaign, updated_at = now()
    WHERE id = e.id;
  RETURN jsonb_build_object('ok', true, 'id', e.id, 'code', e.code);
END $$;

CREATE FUNCTION public.f360_experiment_transition(p_id uuid, p_to text, p_learning text DEFAULT NULL, p_decision text DEFAULT NULL, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('operator'); e f360.growth_experiments; res jsonb; today date := (now() AT TIME ZONE 'America/Mexico_City')::date;
  owner_only boolean := p_to IN ('APPROVED', 'WINNER', 'LOSER', 'INCONCLUSIVE', 'ARCHIVED');
BEGIN
  IF owner_only THEN PERFORM f360.require_role('owner'); END IF;
  SELECT * INTO e FROM f360.growth_experiments WHERE id = p_id FOR UPDATE;
  IF e.id IS NULL THEN RAISE EXCEPTION 'Experimento no encontrado.'; END IF;
  IF NOT ((e.status = 'DRAFT' AND p_to = 'APPROVED') OR (e.status = 'APPROVED' AND p_to IN ('RUNNING', 'STOPPED'))
       OR (e.status = 'RUNNING' AND p_to IN ('WINNER', 'LOSER', 'INCONCLUSIVE', 'STOPPED'))
       OR (e.status IN ('WINNER', 'LOSER', 'INCONCLUSIVE', 'STOPPED') AND p_to = 'ARCHIVED')) THEN
    RAISE EXCEPTION 'No se puede pasar de % a %.', e.status, p_to;
  END IF;

  IF p_to = 'APPROVED' THEN   -- everything that judges the experiment is fixed here, before it starts
    IF e.start_date IS NULL OR e.end_date IS NULL THEN RAISE EXCEPTION 'Falta la fecha de inicio o la de revisión.'; END IF;
    IF e.budget IS NULL THEN RAISE EXCEPTION 'Falta el presupuesto (puede ser 0).'; END IF;
    IF f360.growth_threshold_error(e.success_threshold) IS NOT NULL THEN RAISE EXCEPTION 'Meta de éxito: %', f360.growth_threshold_error(e.success_threshold); END IF;
    IF f360.growth_threshold_error(e.kill_threshold) IS NOT NULL THEN RAISE EXCEPTION 'Criterio para cancelar: %', f360.growth_threshold_error(e.kill_threshold); END IF;
    IF e.primary_kpi = 'cost_per_paid_order' AND cardinality(e.campaign_ids) = 0 THEN RAISE EXCEPTION 'El costo por venta necesita las campañas de Meta del experimento.'; END IF;
    IF e.primary_kpi = 'net_revenue' AND e.market = 'ALL' THEN RAISE EXCEPTION 'La venta en dinero se mide por mercado (no se suman monedas).'; END IF;
    UPDATE f360.growth_experiments SET status = 'APPROVED', approved_by = r.auth_user_id, approved_by_name = r.display_name, approved_at = now(), updated_at = now() WHERE id = e.id;
  ELSIF p_to = 'RUNNING' THEN
    IF e.start_date > today THEN RAISE EXCEPTION 'Empieza el %: todavía no corre.', e.start_date; END IF;
    UPDATE f360.growth_experiments SET status = 'RUNNING', started_at = now(), updated_at = now() WHERE id = e.id;
  ELSIF p_to IN ('WINNER', 'LOSER', 'INCONCLUSIVE') THEN
    IF length(btrim(coalesce(p_learning, ''))) < 10 THEN RAISE EXCEPTION 'Escribe qué aprendimos.'; END IF;
    e.ended_at := now();
    res := f360.growth_experiment_measure(e);
    IF p_to = 'WINNER' AND NOT (res->>'success_met')::boolean THEN RAISE EXCEPTION 'No cumplió la meta de éxito con la muestra mínima: el resultado es INCONCLUSIVE o LOSER.'; END IF;
    IF p_to = 'LOSER' AND NOT (res->>'kill_met')::boolean THEN RAISE EXCEPTION 'No llegó al criterio para cancelar: el resultado es INCONCLUSIVE.'; END IF;
    IF p_to = 'INCONCLUSIVE' AND (res->>'success_met')::boolean AND NOT (res->>'kill_met')::boolean THEN RAISE EXCEPTION 'Cumplió la meta de éxito: ciérralo como WINNER.'; END IF;
    UPDATE f360.growth_experiments SET status = p_to, verdict = p_to, result = res, learning = btrim(p_learning), ended_at = e.ended_at, updated_at = now() WHERE id = e.id;
  ELSIF p_to = 'STOPPED' THEN
    IF length(btrim(coalesce(p_reason, ''))) < 5 THEN RAISE EXCEPTION 'Escribe por qué se detiene.'; END IF;
    e.ended_at := now();
    UPDATE f360.growth_experiments SET status = 'STOPPED', verdict = 'STOPPED', stop_reason = btrim(p_reason), ended_at = e.ended_at,
        result = CASE WHEN e.status = 'RUNNING' THEN f360.growth_experiment_measure(e) END, learning = nullif(btrim(coalesce(p_learning, '')), ''), updated_at = now()
      WHERE id = e.id;
  ELSIF p_to = 'ARCHIVED' THEN
    IF p_decision IS NULL OR p_decision NOT IN ('SCALE', 'ITERATE', 'KILL', 'NONE') THEN RAISE EXCEPTION 'Falta la decisión: escalar, ajustar, matar o ninguna.'; END IF;
    UPDATE f360.growth_experiments SET status = 'ARCHIVED', decision = p_decision, updated_at = now() WHERE id = e.id;
  END IF;
  INSERT INTO f360.growth_experiment_changes (experiment_id, from_status, to_status, actor, actor_name, reason, new)
    VALUES (e.id, e.status, p_to, r.auth_user_id, r.display_name, nullif(btrim(coalesce(p_reason, '')), ''),
            CASE WHEN p_decision IS NOT NULL THEN jsonb_build_object('decision', p_decision) END);
  RETURN jsonb_build_object('ok', true, 'id', e.id, 'status', p_to);
END $$;

-- List (operator+): closed results and the track record per party first, then open experiments with a live measurement.
CREATE FUNCTION public.f360_experiments_list() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('operator');
BEGIN
  RETURN jsonb_build_object(
    'generated_at', now(), 'can_approve', r.role = 'owner',
    'track_record', (SELECT coalesce(jsonb_agg(x ORDER BY x->>'party'), '[]') FROM (
       SELECT jsonb_build_object('party', p.party, 'proposed', count(*) FILTER (WHERE e.proposed_by = p.party), 'responsible', count(*) FILTER (WHERE e.responsible = p.party),
         'winner', count(*) FILTER (WHERE e.proposed_by = p.party AND e.verdict = 'WINNER'),
         'loser', count(*) FILTER (WHERE e.proposed_by = p.party AND e.verdict = 'LOSER'),
         'inconclusive', count(*) FILTER (WHERE e.proposed_by = p.party AND e.verdict = 'INCONCLUSIVE'),
         'stopped', count(*) FILTER (WHERE e.proposed_by = p.party AND e.verdict = 'STOPPED'),
         'open', count(*) FILTER (WHERE e.proposed_by = p.party AND e.status IN ('DRAFT', 'APPROVED', 'RUNNING')),
         'budget_mxn', sum(e.budget) FILTER (WHERE e.proposed_by = p.party AND e.budget_currency = 'MXN' AND e.status <> 'DRAFT')) AS x
       FROM (VALUES ('mario'), ('carolina'), ('goyo'), ('agencia'), ('ia'), ('otro')) p(party)
       LEFT JOIN f360.growth_experiments e ON e.proposed_by = p.party OR e.responsible = p.party
       GROUP BY p.party HAVING count(e.id) > 0) q),
    'experiments', (SELECT coalesce(jsonb_agg(to_jsonb(e) || jsonb_build_object(
         'live', CASE WHEN e.status = 'RUNNING' THEN f360.growth_experiment_measure(e) END,
         'history', (SELECT coalesce(jsonb_agg(jsonb_build_object('at', c.at, 'from', c.from_status, 'to', c.to_status, 'field', c.field, 'old', c.old, 'new', c.new,
                       'by', c.actor_name, 'reason', c.reason) ORDER BY c.id), '[]') FROM f360.growth_experiment_changes c WHERE c.experiment_id = e.id))
       ORDER BY CASE WHEN e.status IN ('WINNER', 'LOSER', 'INCONCLUSIVE', 'STOPPED', 'ARCHIVED') THEN 0 ELSE 1 END, coalesce(e.ended_at, e.created_at) DESC), '[]')
       FROM f360.growth_experiments e));
END $$;

ALTER TABLE f360.growth_experiments ENABLE ROW LEVEL SECURITY;
ALTER TABLE f360.growth_experiment_changes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON f360.growth_experiments, f360.growth_experiment_changes FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON f360.growth_experiments, f360.growth_experiment_changes TO service_role;
REVOKE ALL ON SEQUENCE f360.growth_experiment_seq FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION f360.growth_threshold_error(jsonb), f360.growth_experiment_measure(f360.growth_experiments), f360.growth_experiment_changes_append_only(),
  public.f360_experiment_save(uuid, jsonb), public.f360_experiment_transition(uuid, text, text, text, text), public.f360_experiments_list() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION f360.growth_threshold_error(jsonb), f360.growth_experiment_measure(f360.growth_experiments) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.f360_experiment_save(uuid, jsonb), public.f360_experiment_transition(uuid, text, text, text, text), public.f360_experiments_list()
  TO authenticated, service_role;
