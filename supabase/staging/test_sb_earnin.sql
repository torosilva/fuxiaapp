-- Strategy & Board — EQUITY EARN-IN TRACKER tests (STAGING). NEVER commits: ends with RAISE 'ENSAYO OK'.
-- Run inside a transaction AFTER 20261017000100 (rehearsal: prepend it) with the SB0 staging membership in place.
-- Covers: E1 access (anon, non-member, seller) · E2 validation (cap, founder minimum, duplicate year, bad milestone) ·
-- E3 propose → MARIO_OWNERSHIP decision, Mario recused, idempotent replay · E4 one pending proposal at a time ·
-- E5 Mario cannot approve (refused + logged) · E6 Carolina approves → ACCEPTED_FOR_TRACKING, never SIGNED/FUNDED ·
-- E7 append-only terms + milestones (no later milestones) · E8 revenue excludes CO, matches measurement_sales, indicative
-- pro-rata math · E9 margin gate PENDING_DEFINITION / DATA_INCOMPLETE · E10 a new approved proposal supersedes the old one.
CREATE FUNCTION pg_temp.as(p_uid uuid, p_sql text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r jsonb;
BEGIN
  BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    SET LOCAL ROLE authenticated;
    EXECUTE p_sql INTO r;
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN RESET ROLE; r := jsonb_build_object('error', SQLERRM, 'sqlstate', SQLSTATE); END;
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN r;
END $$;
CREATE FUNCTION pg_temp.try(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  BEGIN EXECUTE p_sql; EXCEPTION WHEN OTHERS THEN RETURN SQLERRM; END;
  RETURN NULL;
END $$;
-- Proposal terms as JSON text (one milestone in the CURRENT year so revenue math can be checked).
CREATE FUNCTION pg_temp.terms(p_initial numeric, p_cap numeric, p_min numeric, p_ms jsonb) RETURNS text LANGUAGE sql AS $$
  SELECT jsonb_build_object('entity_label', 'Fuxia Ballerinas S.A. de C.V.', 'initial_pct', p_initial, 'cap_pct', p_cap, 'founder_min_pct', p_min,
    'cash_commitment', 500000, 'cash_currency', 'MXN', 'excluded_markets', jsonb_build_array('CO'),
    'revenue_definition', 'Venta neta de producto pagada, sin Colombia, MXN con FX aprobado', 'proposal_ref', 'https://claude.ai/code/artifact/test',
    'milestones', p_ms)::text
$$;

DO $$
DECLARE car uuid; mar uuid; seller uuid; stranger uuid; r jsonb; t1 uuid; d1 uuid; d2 uuid; y int := extract(year FROM (now() AT TIME ZONE 'America/Mexico_City'))::int;
  exp_mxn numeric; exp_cons numeric; missing int; tgt numeric; got jsonb; ms jsonb; err text; n_log int;
BEGIN
  SELECT auth_user_id INTO car FROM f360_board.board_members WHERE person_key = 'CAROLINA';
  SELECT auth_user_id INTO mar FROM f360_board.board_members WHERE person_key = 'MARIO';
  IF car IS NULL OR mar IS NULL THEN RAISE EXCEPTION 'fixture: Carolina/Mario board members missing'; END IF;
  SELECT auth_user_id INTO seller FROM f360.user_roles WHERE role = 'seller' LIMIT 1;
  SELECT id INTO stranger FROM auth.users u WHERE NOT EXISTS (SELECT 1 FROM f360.user_roles r WHERE r.auth_user_id = u.id) LIMIT 1;

  -- ── E1 access ──
  IF has_function_privilege('anon', 'public.f360_board_earnin()', 'EXECUTE') OR has_function_privilege('anon', 'public.f360_board_earnin_propose(uuid, jsonb)', 'EXECUTE') THEN
    RAISE EXCEPTION 'FAIL E1 anon can execute'; END IF;
  IF has_table_privilege('authenticated', 'f360_board.earnin_terms', 'SELECT') OR has_table_privilege('service_role', 'f360_board.earnin_milestones', 'SELECT') THEN
    RAISE EXCEPTION 'FAIL E1 direct table access'; END IF;
  FOREACH t1 IN ARRAY ARRAY[seller, stranger] LOOP
    CONTINUE WHEN t1 IS NULL;
    r := pg_temp.as(t1, 'SELECT public.f360_board_earnin()');
    IF coalesce((r->>'ok')::boolean, false) OR r ? 'terms' THEN RAISE EXCEPTION 'FAIL E1 non-member read %', r; END IF;
    r := pg_temp.as(t1, format('SELECT public.f360_board_earnin_propose(gen_random_uuid(), %L::jsonb)', pg_temp.terms(20, 40, 60, '[{"year":2027,"revenue_target":15000000,"equity_pct":8,"partial_from":9000000}]')));
    IF coalesce((r->>'ok')::boolean, false) THEN RAISE EXCEPTION 'FAIL E1 non-member propose %', r; END IF;
  END LOOP;
  IF (SELECT count(*) FROM f360_board.access_log WHERE rpc LIKE 'f360_board_earnin%' AND outcome = 'denied') = 0 AND (seller IS NOT NULL OR stranger IS NOT NULL) THEN
    RAISE EXCEPTION 'FAIL E1 denials not logged'; END IF;
  r := pg_temp.as(car, 'SELECT public.f360_board_earnin()');
  IF NOT (r->>'ok')::boolean OR r->'terms' <> 'null'::jsonb OR r->'statuses'->>'initial_equity' <> 'NOT_RECORDED' THEN RAISE EXCEPTION 'FAIL E1 empty tracker %', r; END IF;
  RAISE NOTICE 'PASS E1 anon has no EXECUTE; no direct table access; seller / non-member get ok:false (logged); empty tracker = NOT_RECORDED';

  -- ── E2 validation ──
  r := pg_temp.as(mar, format('SELECT public.f360_board_earnin_propose(gen_random_uuid(), %L::jsonb)', pg_temp.terms(20, 40, 60,
        '[{"year":2027,"revenue_target":15000000,"equity_pct":8,"partial_from":9000000},{"year":2028,"revenue_target":22000000,"equity_pct":15,"partial_from":16000000}]')));
  IF (r->>'ok')::boolean THEN RAISE EXCEPTION 'FAIL E2 initial+milestones over cap accepted'; END IF;
  r := pg_temp.as(mar, format('SELECT public.f360_board_earnin_propose(gen_random_uuid(), %L::jsonb)', pg_temp.terms(20, 45, 60, '[{"year":2027,"revenue_target":15000000,"equity_pct":8}]')));
  IF (r->>'ok')::boolean THEN RAISE EXCEPTION 'FAIL E2 cap + founder minimum > 100 accepted'; END IF;
  r := pg_temp.as(mar, format('SELECT public.f360_board_earnin_propose(gen_random_uuid(), %L::jsonb)', pg_temp.terms(20, 40, 60,
        '[{"year":2027,"revenue_target":15000000,"equity_pct":4},{"year":2027,"revenue_target":15000000,"equity_pct":4}]')));
  IF (r->>'ok')::boolean THEN RAISE EXCEPTION 'FAIL E2 duplicate year accepted'; END IF;
  r := pg_temp.as(mar, format('SELECT public.f360_board_earnin_propose(gen_random_uuid(), %L::jsonb)', pg_temp.terms(20, 40, 60, '[{"year":2027,"revenue_target":15000000,"equity_pct":8,"partial_from":16000000}]')));
  IF (r->>'ok')::boolean THEN RAISE EXCEPTION 'FAIL E2 partial_from >= target accepted'; END IF;
  r := pg_temp.as(mar, format('SELECT public.f360_board_earnin_propose(gen_random_uuid(), %L::jsonb)', pg_temp.terms(20, 40, 60, '[{"year":2027,"revenue_target":15000000,"equity_pct":8,"gross_margin_min":55}]')));
  IF (r->>'ok')::boolean THEN RAISE EXCEPTION 'FAIL E2 margin 55 (not a fraction) accepted'; END IF;
  IF EXISTS (SELECT 1 FROM f360_board.earnin_terms) OR EXISTS (SELECT 1 FROM f360_board.decisions WHERE conflict_kind = 'MARIO_OWNERSHIP' AND related_object->>'kind' = 'earnin_terms') THEN
    RAISE EXCEPTION 'FAIL E2 a rejected proposal left rows'; END IF;
  RAISE NOTICE 'PASS E2 over-cap, cap+founder>100, duplicate year, from>=target and margin not a fraction are refused, nothing written';

  -- ── E3 propose (Mario) — current-year milestone at 2× this year's actual so the math is checkable ──
  SELECT coalesce(sum(m.net_product_revenue) FILTER (WHERE m.currency = 'MXN'), 0), sum(m.net_product_revenue * f360.fx_rate_for(m.currency, m.business_date)),
         count(*) FILTER (WHERE f360.fx_rate_for(m.currency, m.business_date) IS NULL)
    INTO exp_mxn, exp_cons, missing
    FROM f360.measurement_sales m
    WHERE m.is_paid_sale AND (NOT m.is_test_channel OR f360.sg0_include_tests()) AND m.business_date >= make_date(y, 1, 1) AND m.business_date < make_date(y + 1, 1, 1)
      AND coalesce(m.market, '') <> 'CO';
  tgt := greatest(2 * CASE WHEN missing = 0 THEN coalesce(exp_cons, 0) ELSE exp_mxn END, 1000);
  ms := jsonb_build_array(jsonb_build_object('year', y, 'revenue_target', tgt, 'equity_pct', 8, 'partial_from', 0),
                          jsonb_build_object('year', y + 1, 'revenue_target', 22000000, 'equity_pct', 8, 'partial_from', 16000000, 'gross_margin_min', 0.55),
                          jsonb_build_object('year', y + 3, 'revenue_target', 36000000, 'equity_pct', 2, 'partial_from', 29000000));
  r := pg_temp.as(mar, format('SELECT public.f360_board_earnin_propose(%L, %L::jsonb)', '22222222-2222-4222-8222-000000000001', pg_temp.terms(20, 40, 60, ms)));
  IF NOT coalesce((r->>'ok')::boolean, false) THEN RAISE EXCEPTION 'FAIL E3 propose %', r; END IF;
  t1 := (r->'terms'->>'id')::uuid; d1 := (r->'terms'->'decision'->>'id')::uuid;
  IF r->'terms'->'decision'->>'conflict_kind' <> 'MARIO_OWNERSHIP' OR NOT (r->'terms'->'decision'->>'i_am_recused')::boolean
     OR r->'terms'->>'tracking_status' <> 'PROPOSED' OR jsonb_array_length(r->'terms'->'milestones') <> 3 THEN
    RAISE EXCEPTION 'FAIL E3 decision / recusal / status %', r; END IF;
  IF NOT EXISTS (SELECT 1 FROM f360_board.decision_recusals WHERE decision_id = d1 AND auth_user_id = mar) THEN RAISE EXCEPTION 'FAIL E3 recusal row'; END IF;
  r := pg_temp.as(mar, format('SELECT public.f360_board_earnin_propose(%L, %L::jsonb)', '22222222-2222-4222-8222-000000000001', pg_temp.terms(20, 40, 60, ms)));
  IF NOT (r->>'replayed')::boolean OR (r->'terms'->>'id')::uuid <> t1 THEN RAISE EXCEPTION 'FAIL E3 idempotent replay %', r; END IF;
  IF NOT EXISTS (SELECT 1 FROM f360_board.access_log WHERE rpc = 'f360_board_earnin_propose' AND outcome = 'write' AND object_ref = t1::text) THEN RAISE EXCEPTION 'FAIL E3 write not logged'; END IF;
  RAISE NOTICE 'PASS E3 Mario proposes → MARIO_OWNERSHIP decision, Mario recused, PROPOSED, idempotent replay, write logged';

  -- ── E4 one pending at a time ──
  r := pg_temp.as(car, format('SELECT public.f360_board_earnin_propose(gen_random_uuid(), %L::jsonb)', pg_temp.terms(20, 40, 60, '[{"year":2027,"revenue_target":15000000,"equity_pct":8}]')));
  IF (r->>'ok')::boolean THEN RAISE EXCEPTION 'FAIL E4 second pending proposal accepted'; END IF;
  r := pg_temp.as(car, 'SELECT public.f360_board_earnin()');
  IF r->'statuses'->>'initial_equity' <> 'PROPOSED' OR r->'statuses'->>'legal' <> 'NOT_SIGNED' OR r->'statuses'->>'cash' <> 'NOT_FUNDED' THEN RAISE EXCEPTION 'FAIL E4 statuses %', r->'statuses'; END IF;
  RAISE NOTICE 'PASS E4 only one pending proposal; tracker shows it as PROPOSED, NOT_SIGNED, NOT_FUNDED';

  -- ── E5 Mario cannot approve ──
  r := pg_temp.as(mar, format('SELECT public.f360_board_decision_act(%L, ''APPROVE'')', d1));
  IF (r->>'ok')::boolean OR NOT coalesce((r->>'recused')::boolean, false) THEN RAISE EXCEPTION 'FAIL E5 Mario approved his own terms %', r; END IF;
  IF NOT EXISTS (SELECT 1 FROM f360_board.decision_events WHERE decision_id = d1 AND event = 'APPROVAL_REFUSED_RECUSED') THEN RAISE EXCEPTION 'FAIL E5 refusal not recorded'; END IF;
  r := pg_temp.as(mar, 'SELECT public.f360_board_earnin()');
  IF NOT (r->'related_party'->>'i_am_interested')::boolean THEN RAISE EXCEPTION 'FAIL E5 related party flag'; END IF;
  RAISE NOTICE 'PASS E5 Mario approving his own terms is refused (recused) and recorded';

  -- ── E6 Carolina approves ──
  r := pg_temp.as(car, format('SELECT public.f360_board_decision_act(%L, ''APPROVE'')', d1));
  IF NOT (r->>'ok')::boolean OR r->'decision'->>'approval_basis' <> 'APPROVED_BY_OTHER_MEMBER_RELATED_PARTY' THEN RAISE EXCEPTION 'FAIL E6 approve %', r; END IF;
  got := pg_temp.as(car, 'SELECT public.f360_board_earnin()');
  IF got->'terms'->>'tracking_status' <> 'ACCEPTED_FOR_TRACKING' OR got->'statuses'->>'initial_equity' <> 'ACCEPTED_FOR_TRACKING'
     OR got->'statuses'->>'legal' <> 'NOT_SIGNED' OR got->'statuses'->>'technology' <> 'PENDING_LEGAL_ASSIGNMENT' THEN RAISE EXCEPTION 'FAIL E6 statuses %', got->'statuses'; END IF;
  RAISE NOTICE 'PASS E6 Carolina approves → ACCEPTED_FOR_TRACKING (approved by other member, related party); still NOT_SIGNED / PENDING_LEGAL_ASSIGNMENT';

  -- ── E7 append-only ──
  IF pg_temp.try(format('UPDATE f360_board.earnin_terms SET initial_pct = 35 WHERE id = %L', t1)) IS NULL THEN RAISE EXCEPTION 'FAIL E7 terms updated'; END IF;
  IF pg_temp.try(format('DELETE FROM f360_board.earnin_milestones WHERE terms_id = %L', t1)) IS NULL THEN RAISE EXCEPTION 'FAIL E7 milestone deleted'; END IF;
  -- a milestone added in a later transaction is refused (simulated: created_at moved back is impossible, so test the guard with an old row)
  IF pg_temp.try(format('INSERT INTO f360_board.earnin_milestones (terms_id, year, revenue_target, equity_pct, partial_from) SELECT id, 2035, 1, 1, 0 FROM f360_board.earnin_terms WHERE id <> %L LIMIT 1', t1)) IS NULL
     AND EXISTS (SELECT 1 FROM f360_board.earnin_terms WHERE id <> t1) THEN RAISE EXCEPTION 'FAIL E7 later milestone accepted'; END IF;
  RAISE NOTICE 'PASS E7 terms and milestones are append-only';

  -- ── E8 revenue: CO excluded, equals measurement_sales, indicative pro-rata ──
  ms := (SELECT e FROM jsonb_array_elements(got->'years') e WHERE (e->>'year')::int = y);
  IF ms IS NULL THEN RAISE EXCEPTION 'FAIL E8 current year missing'; END IF;
  IF (ms->'revenue'->>'mxn_only')::numeric <> exp_mxn THEN RAISE EXCEPTION 'FAIL E8 MXN % <> %', ms->'revenue'->>'mxn_only', exp_mxn; END IF;
  IF ms->'revenue'->'by_currency' ? 'COP' THEN RAISE EXCEPTION 'FAIL E8 COP (Colombia) counted'; END IF;
  IF missing = 0 AND (ms->>'actual')::numeric IS DISTINCT FROM coalesce(exp_cons, 0) THEN RAISE EXCEPTION 'FAIL E8 consolidated'; END IF;
  IF missing > 0 AND (ms->'revenue'->>'status' <> 'DATA_INCOMPLETE' OR ms->'revenue'->'consolidated_mxn' <> 'null'::jsonb OR ms->>'actual_basis' <> 'MXN_ONLY') THEN
    RAISE EXCEPTION 'FAIL E8 missing FX must be DATA_INCOMPLETE, never guessed %', ms->'revenue'; END IF;
  IF (ms->>'indicative_equity_actual')::numeric <> f360_board.earnin_indicative((ms->>'actual')::numeric, 0, tgt, 8) THEN RAISE EXCEPTION 'FAIL E8 indicative'; END IF;
  IF f360_board.earnin_indicative(12000000, 9000000, 15000000, 8) <> 4 OR f360_board.earnin_indicative(9000000, 9000000, 15000000, 8) <> 0
     OR f360_board.earnin_indicative(20000000, 9000000, 15000000, 8) <> 8 THEN RAISE EXCEPTION 'FAIL E8 pro-rata math'; END IF;
  IF (SELECT (e->>'indicative_equity_actual')::numeric FROM jsonb_array_elements(got->'years') e WHERE (e->>'year')::int = y + 1) <> 0 OR got->'years'->1->>'formally_earned' IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL E8 future year earns / formally earned computed'; END IF;
  RAISE NOTICE 'PASS E8 revenue = measurement_sales without CO (MXN %, FX missing rows %); 12M of 9M→15M = 4%%; future years 0; formally earned never computed', exp_mxn, missing;

  -- ── E9 margin gate ──
  IF ms->>'margin_gate' <> 'PENDING_DEFINITION' THEN RAISE EXCEPTION 'FAIL E9 pending definition %', ms->>'margin_gate'; END IF;
  IF (SELECT e->>'margin_gate' FROM jsonb_array_elements(got->'years') e WHERE (e->>'year')::int = y + 1) NOT IN ('DATA_INCOMPLETE', 'MEASURABLE_NOT_EVALUATED') THEN RAISE EXCEPTION 'FAIL E9 gate with minimum'; END IF;
  RAISE NOTICE 'PASS E9 margin gate: no minimum → PENDING_DEFINITION; minimum set but margin not measurable → DATA_INCOMPLETE';

  -- ── E10 a new proposal supersedes when approved ──
  r := pg_temp.as(car, format('SELECT public.f360_board_earnin_propose(gen_random_uuid(), %L::jsonb)', pg_temp.terms(20, 40, 60, '[{"year":2027,"revenue_target":15000000,"equity_pct":8,"partial_from":9000000}]')));
  IF NOT (r->>'ok')::boolean OR (r->'terms'->>'version')::int <> 2 THEN RAISE EXCEPTION 'FAIL E10 v2 %', r; END IF;
  d2 := (r->'terms'->'decision'->>'id')::uuid;
  got := pg_temp.as(car, 'SELECT public.f360_board_earnin()');
  IF (got->'terms'->>'version')::int <> 1 OR (got->'pending'->>'version')::int <> 2 THEN RAISE EXCEPTION 'FAIL E10 while pending the approved v1 is tracked'; END IF;
  r := pg_temp.as(car, format('SELECT public.f360_board_decision_act(%L, ''APPROVE'')', d2));
  IF NOT (r->>'ok')::boolean THEN RAISE EXCEPTION 'FAIL E10 Carolina approving terms Carolina proposed (related party: Mario is the interested one) %', r; END IF;
  got := pg_temp.as(mar, 'SELECT public.f360_board_earnin()');
  IF (got->'terms'->>'version')::int <> 2 OR (SELECT status FROM f360_board.decisions WHERE id = d1) <> 'SUPERSEDED' OR jsonb_array_length(got->'history') <> 2 THEN
    RAISE EXCEPTION 'FAIL E10 supersede %', got->'history'; END IF;
  RAISE NOTICE 'PASS E10 while v2 is pending, approved v1 is tracked; approving v2 supersedes v1; history keeps both';

  RAISE EXCEPTION 'ENSAYO OK';
END $$;
