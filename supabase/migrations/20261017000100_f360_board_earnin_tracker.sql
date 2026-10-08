-- Fuxia 360 · Strategy & Board · EQUITY EARN-IN TRACKER (Mario 2026-10-08: "Strategy & Board → Ownership" del acuerdo propuesto).
-- Specs: 07_CAPITAL_OWNERSHIP.md, 08_BOARD_GOVERNANCE.md §2 (D10B), 13_DATA_MODEL.md; proposal: "Propuesta al Consejo de
-- Administración de Fuxia Ballerinas S.A. de C.V." (20% initial + up to 20% by revenue milestones with a gross-margin gate,
-- cap 40% pre-dilution, Carolina ≥ 60%, Colombia excluded).
-- ADDITIVE, inside f360_board (+ public.f360_board_earnin* RPCs). Nothing existing changes. NO data is loaded: the terms
-- enter only through f360_board_earnin_propose (a member, from the UI) and are tracked only after Carolina approves them.
--
-- What it is — and is not (spec 07 §4 stays true):
--   · earnin_terms / earnin_milestones: the PROPOSED terms, append-only, one version per proposal, each tied to a Board
--     decision of kind MARIO_OWNERSHIP. D10B applies unchanged: Mario is the interested party, RECUSED, and can never approve;
--     the terms become "ACCEPTED_FOR_TRACKING" only when another member (Carolina) approves that decision.
--   · ACCEPTED_FOR_TRACKING is NOT a signed agreement. This module never writes a cap table, never records money as
--     committed/funded, never values the technology. Formal ownership stays "not registered" until signed documents exist.
--   · f360_board_earnin() reads revenue LIVE from f360.measurement_sales (S-G0, the single revenue source): paid sales,
--     production channels, markets not excluded (CO by default), net product revenue, consolidated to MXN with APPROVED FX
--     only (a currency without an approved rate → consolidated value NULL + DATA_INCOMPLETE, never guessed). Per milestone
--     year it shows target, management target (Board plan), published forecast, actual, attainment and an INDICATIVE
--     equity figure (pro-rata between partial_from and target). The gross-margin gate shows PENDING_DEFINITION while the
--     minimum is not set and DATA_INCOMPLETE while gross margin is not measurable (metric_catalog). Formally earned = never
--     computed here: it needs the year's closed months, the close approved by Carolina and signed documents.
-- Rollback: supabase/rollbacks/20261017000100_f360_board_earnin_tracker.down.sql

-- ══ 1 · Terms (append-only) ══════════════════════════════════════════════════
CREATE TABLE f360_board.earnin_terms (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version             int  NOT NULL UNIQUE CHECK (version > 0),
  entity_label        text NOT NULL CHECK (length(btrim(entity_label)) BETWEEN 3 AND 120),
  party_person_key    text NOT NULL CHECK (party_person_key = 'MARIO'),
  initial_pct         numeric(5,2) NOT NULL CHECK (initial_pct > 0 AND initial_pct < 100),
  cap_pct             numeric(5,2) NOT NULL CHECK (cap_pct > 0 AND cap_pct < 100),
  founder_min_pct     numeric(5,2) NOT NULL CHECK (founder_min_pct > 0 AND founder_min_pct < 100),
  cash_commitment     numeric(14,2) CHECK (cash_commitment IS NULL OR cash_commitment >= 0),
  cash_currency       text NOT NULL DEFAULT 'MXN' REFERENCES f360.currencies(code),
  revenue_definition  text NOT NULL CHECK (length(btrim(revenue_definition)) >= 10),
  excluded_markets    text[] NOT NULL DEFAULT ARRAY['CO']::text[] CHECK (excluded_markets <@ ARRAY['MX', 'CO', 'ROW']::text[]),
  proposal_ref        text CHECK (proposal_ref IS NULL OR proposal_ref ~ '^https://'),
  decision_id         uuid NOT NULL UNIQUE REFERENCES f360_board.decisions(id),
  created_by          uuid NOT NULL,
  created_by_name     text NOT NULL,
  created_at          timestamptz NOT NULL DEFAULT now(),
  idempotency_key     uuid NOT NULL UNIQUE,
  content_hash        text NOT NULL,
  CHECK (initial_pct <= cap_pct),
  CHECK (cap_pct + founder_min_pct <= 100)
);
CREATE TABLE f360_board.earnin_milestones (
  terms_id          uuid NOT NULL REFERENCES f360_board.earnin_terms(id),
  year              int  NOT NULL CHECK (year BETWEEN 2026 AND 2100),
  revenue_target    numeric(14,2) NOT NULL CHECK (revenue_target > 0),
  currency          text NOT NULL DEFAULT 'MXN' CHECK (currency = 'MXN'),
  equity_pct        numeric(5,2) NOT NULL CHECK (equity_pct > 0 AND equity_pct < 100),
  partial_from      numeric(14,2) NOT NULL CHECK (partial_from >= 0),
  gross_margin_min  numeric(5,4) CHECK (gross_margin_min IS NULL OR (gross_margin_min > 0 AND gross_margin_min < 1)),
  PRIMARY KEY (terms_id, year),
  CHECK (partial_from < revenue_target)
);
ALTER TABLE f360_board.earnin_terms ENABLE ROW LEVEL SECURITY;
ALTER TABLE f360_board.earnin_milestones ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER earnin_terms_append_only BEFORE UPDATE OR DELETE ON f360_board.earnin_terms FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();
CREATE TRIGGER earnin_milestones_append_only BEFORE UPDATE OR DELETE ON f360_board.earnin_milestones FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();
-- Milestones are written only in the transaction that created their terms (no later additions to a recorded proposal).
CREATE FUNCTION f360_board.earnin_milestone_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM f360_board.earnin_terms t WHERE t.id = NEW.terms_id AND t.created_at = now()) THEN   -- now() = this transaction's start
    RAISE EXCEPTION 'Las metas de una propuesta registrada no se modifican: registra una propuesta nueva.';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER earnin_milestones_same_tx BEFORE INSERT ON f360_board.earnin_milestones FOR EACH ROW EXECUTE FUNCTION f360_board.earnin_milestone_guard();

-- ══ 2 · Helpers ═══════════════════════════════════════════════════════════════
-- Indicative equity for one milestone: 0 at or below partial_from, full at or above the target, linear in between.
CREATE FUNCTION f360_board.earnin_indicative(p_value numeric, p_from numeric, p_target numeric, p_pct numeric) RETURNS numeric
LANGUAGE sql IMMUTABLE SET search_path = pg_catalog, pg_temp AS $$
  SELECT CASE WHEN p_value IS NULL THEN NULL
              WHEN p_value <= p_from THEN 0
              WHEN p_value >= p_target THEN p_pct
              ELSE round(p_pct * (p_value - p_from) / (p_target - p_from), 2) END
$$;

-- Revenue of one calendar year for the earn-in (S-G0 measurement_sales; same production/test rule as the Medición tab).
CREATE FUNCTION f360_board.earnin_revenue(p_year int, p_excluded text[]) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE by_cur jsonb; missing text[]; mxn numeric; cons numeric; tests boolean := f360.sg0_include_tests();
BEGIN
  WITH s AS (
    SELECT m.currency, m.business_date, coalesce(m.net_product_revenue, 0) AS net
    FROM f360.measurement_sales m
    WHERE m.is_paid_sale AND (NOT m.is_test_channel OR tests)
      AND m.business_date >= make_date(p_year, 1, 1) AND m.business_date < make_date(p_year + 1, 1, 1)
      AND NOT (coalesce(m.market, '') = ANY (coalesce(p_excluded, '{}'))))
  SELECT coalesce((SELECT jsonb_object_agg(currency, total) FROM (SELECT currency, sum(net) AS total FROM s GROUP BY currency) x), '{}'),
         ARRAY(SELECT DISTINCT currency FROM s WHERE f360.fx_rate_for(currency, business_date) IS NULL ORDER BY 1),
         (SELECT coalesce(sum(net), 0) FROM s WHERE currency = 'MXN'),
         (SELECT sum(net * f360.fx_rate_for(currency, business_date)) FROM s)
    INTO by_cur, missing, mxn, cons;
  RETURN jsonb_build_object('by_currency', by_cur, 'mxn_only', mxn,
    'consolidated_mxn', CASE WHEN cardinality(missing) = 0 THEN coalesce(cons, 0) END,
    'fx_missing', to_jsonb(missing),
    'status', CASE WHEN cardinality(missing) = 0 THEN 'AVAILABLE' ELSE 'DATA_INCOMPLETE' END);
END $$;

-- Management target for a year (Board plan; linked rows read f360.growth_plans live — same rule as f360_board_plans).
CREATE FUNCTION f360_board.earnin_mgmt_target(p_year int) RETURNS numeric
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT CASE WHEN y.linked_source = 'f360.growth_plans' THEN (SELECT g.north_star FROM f360.growth_plans g WHERE g.plan_year::text = y.linked_key)
              ELSE y.revenue_target END
  FROM f360_board.plan_years y JOIN f360_board.plan_versions v ON v.id = y.version_id
  WHERE y.year = p_year AND y.currency = 'MXN' AND v.status <> 'SUPERSEDED'
  ORDER BY (v.status = 'APPROVED') DESC, v.created_at DESC LIMIT 1
$$;

-- Latest PUBLISHED forecast of net product revenue (MXN totals) for a year; NULL when none.
CREATE FUNCTION f360_board.earnin_forecast(p_year int) RETURNS numeric
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT sum(l.amount) FROM f360_board.forecast_lines l
  WHERE l.version_id = (SELECT v.id FROM f360_board.forecast_versions v WHERE v.status = 'PUBLISHED' ORDER BY v.published_at DESC NULLS LAST LIMIT 1)
    AND l.metric_key = 'revenue_net_product' AND l.role = 'total' AND l.currency = 'MXN'
    AND l.period_month >= make_date(p_year, 1, 1) AND l.period_month < make_date(p_year + 1, 1, 1)
  HAVING count(*) > 0
$$;

CREATE FUNCTION f360_board.earnin_terms_json(t f360_board.earnin_terms, p_uid uuid) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT jsonb_build_object('id', t.id, 'version', t.version, 'entity_label', t.entity_label, 'initial_pct', t.initial_pct, 'cap_pct', t.cap_pct,
    'founder_min_pct', t.founder_min_pct, 'cash_commitment', t.cash_commitment, 'cash_currency', t.cash_currency,
    'revenue_definition', t.revenue_definition, 'excluded_markets', to_jsonb(t.excluded_markets), 'proposal_ref', t.proposal_ref,
    'created_by', t.created_by_name, 'created_at', t.created_at, 'content_hash', t.content_hash,
    'milestones', (SELECT coalesce(jsonb_agg(jsonb_build_object('year', m.year, 'revenue_target', m.revenue_target, 'currency', m.currency,
        'equity_pct', m.equity_pct, 'partial_from', m.partial_from, 'gross_margin_min', m.gross_margin_min) ORDER BY m.year), '[]')
      FROM f360_board.earnin_milestones m WHERE m.terms_id = t.id),
    'decision', (SELECT f360_board.decision_json(d, p_uid) FROM f360_board.decisions d WHERE d.id = t.decision_id),
    'tracking_status', (SELECT CASE d.status WHEN 'APPROVED' THEN 'ACCEPTED_FOR_TRACKING' WHEN 'PROPOSED' THEN 'PROPOSED' WHEN 'DEFERRED' THEN 'PROPOSED'
                                            ELSE d.status END FROM f360_board.decisions d WHERE d.id = t.decision_id))
$$;

-- ══ 3 · Public RPCs ═══════════════════════════════════════════════════════════
-- Record a proposal of terms (sensitive write, scope CAP_TABLE). Creates the MARIO_OWNERSHIP decision through the existing
-- decision RPC (so recusal, events and logging are exactly D10B) and the append-only terms + milestones.
CREATE FUNCTION public.f360_board_earnin_propose(p_idempotency_key uuid, p_terms jsonb) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360_board.require_board_member('CAP_TABLE', 'f360_board_earnin_propose', NULL, jsonb_build_object('k', p_idempotency_key));
  t f360_board.earnin_terms; active f360_board.earnin_terms; ms jsonb; m jsonb; dr jsonb; dec_id uuid;
  v_initial numeric; v_cap numeric; v_min numeric; v_cash numeric; v_entity text; v_def text; v_ref text; v_excl text[];
  total numeric := 0; years int[] := '{}'; y int; summary text;
BEGIN
  IF uid IS NULL THEN RETURN f360_board.denied(); END IF;
  IF p_idempotency_key IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'Falta la llave de idempotencia.'); END IF;
  SELECT * INTO t FROM f360_board.earnin_terms WHERE idempotency_key = p_idempotency_key;
  IF t.id IS NOT NULL THEN RETURN jsonb_build_object('ok', true, 'replayed', true, 'terms', f360_board.earnin_terms_json(t, uid)); END IF;
  IF jsonb_typeof(p_terms) IS DISTINCT FROM 'object' THEN RETURN jsonb_build_object('ok', false, 'error', 'Términos no válidos.'); END IF;
  IF EXISTS (SELECT 1 FROM f360_board.earnin_terms x JOIN f360_board.decisions d ON d.id = x.decision_id WHERE d.status IN ('PROPOSED', 'DEFERRED')) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Ya hay una propuesta pendiente: que se apruebe, se rechace o se retire primero.');
  END IF;
  BEGIN
    v_entity := btrim(p_terms->>'entity_label'); v_def := btrim(p_terms->>'revenue_definition'); v_ref := nullif(btrim(p_terms->>'proposal_ref'), '');
    v_initial := (p_terms->>'initial_pct')::numeric; v_cap := (p_terms->>'cap_pct')::numeric; v_min := (p_terms->>'founder_min_pct')::numeric;
    v_cash := nullif(p_terms->>'cash_commitment', '')::numeric;
    v_excl := CASE WHEN p_terms ? 'excluded_markets' THEN ARRAY(SELECT jsonb_array_elements_text(p_terms->'excluded_markets')) ELSE ARRAY['CO'] END;
    ms := p_terms->'milestones';
  EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('ok', false, 'error', 'Términos no válidos: revisa los números.');
  END;
  IF coalesce(length(v_entity), 0) NOT BETWEEN 3 AND 120 THEN RETURN jsonb_build_object('ok', false, 'error', 'Indica la sociedad.'); END IF;
  IF coalesce(length(v_def), 0) < 10 THEN RETURN jsonb_build_object('ok', false, 'error', 'Indica cómo se miden las ventas.'); END IF;
  IF v_ref IS NOT NULL AND v_ref !~ '^https://' THEN RETURN jsonb_build_object('ok', false, 'error', 'La liga a la propuesta debe empezar con https://'); END IF;
  IF NOT (v_excl <@ ARRAY['MX', 'CO', 'ROW']) THEN RETURN jsonb_build_object('ok', false, 'error', 'Mercado excluido no válido (MX, CO o ROW).'); END IF;
  IF v_cash IS NOT NULL AND v_cash < 0 THEN RETURN jsonb_build_object('ok', false, 'error', 'La aportación en efectivo no puede ser negativa.'); END IF;
  IF jsonb_typeof(ms) IS DISTINCT FROM 'array' OR jsonb_array_length(ms) NOT BETWEEN 1 AND 10 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Indica entre 1 y 10 metas anuales.');
  END IF;
  FOR m IN SELECT * FROM jsonb_array_elements(ms) LOOP
    BEGIN
      y := (m->>'year')::int; total := total + (m->>'equity_pct')::numeric;
      IF y NOT BETWEEN 2026 AND 2100 OR (m->>'revenue_target')::numeric <= 0 OR (m->>'equity_pct')::numeric <= 0
         OR coalesce((m->>'partial_from')::numeric, 0) < 0 OR coalesce((m->>'partial_from')::numeric, 0) >= (m->>'revenue_target')::numeric
         OR (nullif(m->>'gross_margin_min', '')::numeric IS NOT NULL AND nullif(m->>'gross_margin_min', '')::numeric NOT BETWEEN 0.0001 AND 0.9999) THEN
        RETURN jsonb_build_object('ok', false, 'error', format('Meta %s no válida: meta > 0, porcentaje > 0, "desde" menor que la meta, margen entre 0 y 1.', y));
      END IF;
    EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('ok', false, 'error', 'Meta no válida: revisa año, meta, porcentaje y margen.');
    END;
    IF y = ANY (years) THEN RETURN jsonb_build_object('ok', false, 'error', 'Hay dos metas para el mismo año.'); END IF;
    years := years || y;
  END LOOP;
  IF v_initial IS NULL OR v_cap IS NULL OR v_min IS NULL OR v_initial + total > v_cap THEN
    RETURN jsonb_build_object('ok', false, 'error', format('El porcentaje inicial más las metas (%s%%) no puede pasar del tope (%s%%).', coalesce(v_initial, 0) + total, v_cap));
  END IF;
  IF v_cap + v_min > 100 THEN RETURN jsonb_build_object('ok', false, 'error', 'El tope de Mario más el mínimo de la fundadora no puede pasar de 100%.'); END IF;

  SELECT x.* INTO active FROM f360_board.earnin_terms x JOIN f360_board.decisions d ON d.id = x.decision_id WHERE d.status = 'APPROVED' ORDER BY x.version DESC LIMIT 1;
  summary := format('Registrar PARA SEGUIMIENTO (no es contrato firmado) los términos propuestos de participación de Mario en %s: %s%% inicial, hasta %s%% por metas de ventas, tope %s%% antes de futuras rondas; la fundadora conserva al menos %s%%. Metas: %s.',
    v_entity, v_initial, total, v_cap, v_min,
    (SELECT string_agg(format('%s → MXN %s (+%s%%)', e->>'year', to_char((e->>'revenue_target')::numeric, 'FM999,999,999,999'), e->>'equity_pct'), '; ' ORDER BY (e->>'year')::int)
       FROM jsonb_array_elements(ms) e));
  dr := public.f360_board_decision_propose(gen_random_uuid(), format('Participación de Mario (earn-in) · propuesta v%s', coalesce((SELECT max(version) FROM f360_board.earnin_terms), 0) + 1),
          summary, coalesce(v_ref, ''), 'MARIO_OWNERSHIP', '{}', NULL, '[]', active.decision_id, jsonb_build_object('kind', 'earnin_terms', 'idempotency_key', p_idempotency_key));
  IF NOT coalesce((dr->>'ok')::boolean, false) THEN RETURN jsonb_build_object('ok', false, 'error', coalesce(dr->>'error', 'No se pudo registrar la decisión.')); END IF;
  dec_id := (dr->'decision'->>'id')::uuid;
  BEGIN
    INSERT INTO f360_board.earnin_terms (version, entity_label, party_person_key, initial_pct, cap_pct, founder_min_pct, cash_commitment, cash_currency,
                                         revenue_definition, excluded_markets, proposal_ref, decision_id, created_by, created_by_name, idempotency_key, content_hash)
      VALUES (coalesce((SELECT max(version) FROM f360_board.earnin_terms), 0) + 1, v_entity, 'MARIO', v_initial, v_cap, v_min, v_cash,
              coalesce(nullif(p_terms->>'cash_currency', ''), 'MXN'), v_def, v_excl, v_ref, dec_id, uid, f360_board.member_name(uid), p_idempotency_key,
              encode(extensions.digest(p_terms::text, 'sha256'), 'hex'))
      RETURNING * INTO t;
    INSERT INTO f360_board.earnin_milestones (terms_id, year, revenue_target, equity_pct, partial_from, gross_margin_min)
      SELECT t.id, (e->>'year')::int, (e->>'revenue_target')::numeric, (e->>'equity_pct')::numeric, coalesce((e->>'partial_from')::numeric, 0),
             nullif(e->>'gross_margin_min', '')::numeric
      FROM jsonb_array_elements(ms) e;
  EXCEPTION WHEN check_violation OR not_null_violation OR foreign_key_violation OR invalid_text_representation OR numeric_value_out_of_range THEN
    RAISE EXCEPTION 'Términos no válidos: revisa entidad, definición de ventas, metas (año, meta > desde, margen entre 0 y 1) y porcentajes.';
  END;
  PERFORM f360_board.log_write(uid, 'CAP_TABLE', 'f360_board_earnin_propose', t.id::text, jsonb_build_object('version', t.version));
  RETURN jsonb_build_object('ok', true, 'terms', f360_board.earnin_terms_json(t, uid));
END $$;

-- The tracker (scope CAP_TABLE). Indicative only; see header.
CREATE FUNCTION public.f360_board_earnin() RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360_board.require_board_member('CAP_TABLE', 'f360_board_earnin');
  cur f360_board.earnin_terms; pend f360_board.earnin_terms; m f360_board.earnin_milestones; rev jsonb; years jsonb := '[]';
  this_year int := extract(year FROM (now() AT TIME ZONE 'America/Mexico_City'))::int; actual numeric; fc numeric; months_closed int;
  margin_avail text; ind_actual numeric; ind_sum numeric := 0; mario uuid;
BEGIN
  IF uid IS NULL THEN RETURN f360_board.denied(); END IF;
  SELECT auth_user_id INTO mario FROM f360_board.board_members WHERE person_key = 'MARIO';
  SELECT x.* INTO cur FROM f360_board.earnin_terms x JOIN f360_board.decisions d ON d.id = x.decision_id WHERE d.status = 'APPROVED' ORDER BY x.version DESC LIMIT 1;
  SELECT x.* INTO pend FROM f360_board.earnin_terms x JOIN f360_board.decisions d ON d.id = x.decision_id WHERE d.status IN ('PROPOSED', 'DEFERRED') ORDER BY x.version DESC LIMIT 1;
  IF cur.id IS NULL THEN cur := pend; END IF;   -- nothing accepted yet: show the pending proposal, labelled PROPOSED
  SELECT availability INTO margin_avail FROM f360_board.metric_catalog WHERE metric_key = 'gross_margin';

  IF cur.id IS NOT NULL THEN
    FOR m IN SELECT * FROM f360_board.earnin_milestones WHERE terms_id = cur.id ORDER BY year LOOP
      rev := f360_board.earnin_revenue(m.year, cur.excluded_markets);
      actual := coalesce((rev->>'consolidated_mxn')::numeric, (rev->>'mxn_only')::numeric);
      fc := f360_board.earnin_forecast(m.year);
      SELECT count(*) FILTER (WHERE status = 'CLOSED') INTO months_closed FROM f360_board.fiscal_periods
        WHERE entity_key = 'fuxia' AND kind = 'MONTH' AND fiscal_year = m.year;
      ind_actual := CASE WHEN m.year <= this_year THEN f360_board.earnin_indicative(actual, m.partial_from, m.revenue_target, m.equity_pct) ELSE 0 END;
      ind_sum := ind_sum + coalesce(ind_actual, 0);
      years := years || jsonb_build_object(
        'year', m.year, 'revenue_target', m.revenue_target, 'equity_pct', m.equity_pct, 'partial_from', m.partial_from,
        'gross_margin_min', m.gross_margin_min,
        'period_state', CASE WHEN m.year > this_year THEN 'FUTURE' WHEN m.year = this_year THEN 'IN_PROGRESS' ELSE 'ENDED' END,
        'months_closed', months_closed,
        'management_target', f360_board.earnin_mgmt_target(m.year),
        'forecast', fc,
        'actual', actual, 'actual_basis', CASE WHEN rev->>'consolidated_mxn' IS NOT NULL THEN 'CONSOLIDATED_MXN' ELSE 'MXN_ONLY' END,
        'revenue', rev,
        'attainment', CASE WHEN m.year <= this_year THEN round(actual / m.revenue_target, 4) END,
        'indicative_equity_actual', ind_actual,
        'indicative_equity_forecast', f360_board.earnin_indicative(fc, m.partial_from, m.revenue_target, m.equity_pct),
        'margin_gate', CASE WHEN m.gross_margin_min IS NULL THEN 'PENDING_DEFINITION'
                            WHEN margin_avail = 'AVAILABLE' THEN 'MEASURABLE_NOT_EVALUATED' ELSE 'DATA_INCOMPLETE' END,
        'formally_earned', NULL);
    END LOOP;
  END IF;

  RETURN jsonb_build_object('ok', true,
    'label', 'INDICATIVO — propuesta no firmada. Nada aquí es un contrato, un cap table ni una valuación.',
    'terms', CASE WHEN cur.id IS NOT NULL THEN f360_board.earnin_terms_json(cur, uid) END,
    'pending', CASE WHEN pend.id IS NOT NULL AND pend.id <> cur.id THEN f360_board.earnin_terms_json(pend, uid) END,
    'years', years,
    'totals', CASE WHEN cur.id IS NOT NULL THEN jsonb_build_object('initial_pct', cur.initial_pct, 'cap_pct', cur.cap_pct, 'founder_min_pct', cur.founder_min_pct,
      'milestones_pct', (SELECT sum(equity_pct) FROM f360_board.earnin_milestones WHERE terms_id = cur.id),
      'indicative_earned_pct', ind_sum, 'indicative_total_pct', cur.initial_pct + ind_sum) END,
    'statuses', jsonb_build_object(
      'initial_equity', CASE WHEN cur.id IS NULL THEN 'NOT_RECORDED' WHEN cur.id = pend.id THEN 'PROPOSED' ELSE 'ACCEPTED_FOR_TRACKING' END,
      'legal', 'NOT_SIGNED',
      'cash', 'NOT_FUNDED',
      'technology', 'PENDING_LEGAL_ASSIGNMENT',
      'margin_metric', coalesce(margin_avail, 'MISSING')),
    'related_party', jsonb_build_object('member', f360_board.member_name(mario), 'i_am_interested', uid = mario,
      'rule', 'Mario es parte relacionada: no aprueba términos ni cierres que determinen su participación. Aprueba Carolina.'),
    'history', (SELECT coalesce(jsonb_agg(jsonb_build_object('version', x.version, 'created_at', x.created_at, 'created_by', x.created_by_name,
        'initial_pct', x.initial_pct, 'cap_pct', x.cap_pct, 'decision_number', d.number, 'decision_status', d.status) ORDER BY x.version DESC), '[]')
      FROM f360_board.earnin_terms x JOIN f360_board.decisions d ON d.id = x.decision_id),
    'this_year', this_year);
END $$;

REVOKE ALL ON ALL TABLES IN SCHEMA f360_board FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA f360_board FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.f360_board_earnin_propose(uuid, jsonb), public.f360_board_earnin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_board_earnin_propose(uuid, jsonb), public.f360_board_earnin() TO authenticated;
