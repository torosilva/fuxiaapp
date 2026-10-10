-- S-G1 Growth Cockpit — rolled-back checks (staging). Run: psql "$STAGING_DB_URL" -f supabase/staging/test_sg1_cockpit.sql
BEGIN;
DO $$
DECLARE mario uuid := (SELECT auth_user_id FROM f360_board.board_members WHERE person_key = 'MARIO');
  seller uuid := (SELECT auth_user_id FROM f360.user_roles WHERE role = 'seller' LIMIT 1);
  viewer uuid := (SELECT auth_user_id FROM f360.user_roles WHERE role = 'viewer' LIMIT 1);
  d jsonb; d2 jsonb; m jsonb; s jsonb; n int; tgt uuid := (SELECT id FROM f360.sales_targets WHERE key = 'woo_staging4');
BEGIN
  -- C1 permissions: anon / seller / viewer refused
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  BEGIN PERFORM public.f360_growth_cockpit(NULL, NULL); RAISE EXCEPTION 'C1 anon'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  IF seller IS NOT NULL THEN
    PERFORM set_config('request.jwt.claims', json_build_object('sub', seller, 'role', 'authenticated')::text, true);
    BEGIN PERFORM public.f360_growth_cockpit(NULL, NULL); RAISE EXCEPTION 'C1 seller'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  END IF;
  IF viewer IS NOT NULL THEN
    PERFORM set_config('request.jwt.claims', json_build_object('sub', viewer, 'role', 'authenticated')::text, true);
    BEGIN PERFORM public.f360_growth_cockpit(NULL, NULL); RAISE EXCEPTION 'C1 viewer'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', mario, 'role', 'authenticated')::text, true);
  d := public.f360_growth_cockpit('2026-06-01', '2026-10-10');
  -- C2 markets separated, each in its own currency; no consolidated total without FX
  IF jsonb_array_length(d->'markets') <> 3 OR d->'markets'->0->>'currency' <> 'MXN' OR d->'markets'->1->>'currency' <> 'COP' OR d->'markets'->2->>'currency' <> 'USD' THEN RAISE EXCEPTION 'C2 %', d->'markets'; END IF;
  IF d->'consolidated'->>'status' = 'OK' THEN RAISE EXCEPTION 'C2 consolidated without FX'; END IF;
  -- C3 revenue / paid orders = Commerce Facts (paid only; cancelled, never-paid, reversed excluded)
  FOR m IN SELECT * FROM jsonb_array_elements(d->'markets') LOOP
    IF (m->'kpis'->'paid_orders'->>'value')::int <> (SELECT count(*) FROM f360.commerce_orders WHERE source_system = 'woo' AND market = m->>'market' AND status_class = 'countable'
          AND occurred_at >= '2026-06-01'::timestamp AT TIME ZONE 'America/Mexico_City' AND occurred_at < '2026-10-11'::timestamp AT TIME ZONE 'America/Mexico_City')
       OR (m->'kpis'->'revenue'->>'value')::numeric <> (SELECT coalesce(sum(net_product), 0) FROM f360.commerce_orders WHERE source_system = 'woo' AND market = m->>'market' AND status_class = 'countable'
          AND occurred_at >= '2026-06-01'::timestamp AT TIME ZONE 'America/Mexico_City' AND occurred_at < '2026-10-11'::timestamp AT TIME ZONE 'America/Mexico_City')
    THEN RAISE EXCEPTION 'C3 %', m->>'market'; END IF;
    -- C4 missing inputs never shown as 0: spend-derived KPIs and session CVR are NOT_CONFIGURED with value null
    FOR s IN SELECT value FROM jsonb_each(m->'kpis') WHERE key IN ('spend', 'cpc', 'cpm', 'cpa', 'roas', 'mer', 'cvr_session') LOOP
      IF s->>'status' NOT IN ('NOT_CONFIGURED', 'DATA_INCOMPLETE') OR (s->'value' IS NOT NULL AND s->'value' <> 'null'::jsonb) THEN RAISE EXCEPTION 'C4 % %', m->>'market', s; END IF;
    END LOOP;
    -- C5 channel breakdown adds up to the total (no double count)
    IF (SELECT coalesce(sum((c->>'paid_orders')::int), 0) FROM jsonb_array_elements(m->'by_channel') c) <> (m->'kpis'->'paid_orders'->>'value')::int THEN RAISE EXCEPTION 'C5 %', m->>'market'; END IF;
  END LOOP;
  -- C6 idempotent read: same answer twice
  d2 := public.f360_growth_cockpit('2026-06-01', '2026-10-10');
  IF (d - 'generated_at') <> (d2 - 'generated_at') THEN RAISE EXCEPTION 'C6'; END IF;
  -- C7 a period with no orders: AOV DATA_INCOMPLETE (no division by zero), revenue 0 with status OK
  d := public.f360_growth_cockpit('2020-01-01', '2020-01-31');
  IF d->'markets'->0->'kpis'->'aov'->>'status' <> 'DATA_INCOMPLETE' OR (d->'markets'->0->'kpis'->'revenue'->>'value')::numeric <> 0 THEN RAISE EXCEPTION 'C7 %', d->'markets'->0->'kpis'; END IF;
  -- C8 spend in the market currency → CPC/CTR/CPM/CPA/MER computed; spend in another currency → DATA_INCOMPLETE (never converted)
  INSERT INTO f360.marketing_spend_imports (id, platform, source, content_sha256, row_count, status, uploaded_by, uploaded_by_name)
    VALUES ('00000000-0000-4000-8000-0000000c0c08', 'meta', 'csv', encode(extensions.digest('c8', 'sha256'), 'hex'), 2, 'accepted', mario, 'test');
  INSERT INTO f360.marketing_spend_rows (import_id, row_no, date, market, platform, account_id, campaign_id, currency, spend, impressions, clicks) VALUES
    ('00000000-0000-4000-8000-0000000c0c08', 1, '2026-09-10', 'MX', 'meta', 'act_t', 'cmp_t', 'MXN', 1000, 50000, 500),
    ('00000000-0000-4000-8000-0000000c0c08', 2, '2026-09-10', 'CO', 'meta', 'act_t2', 'cmp_t2', 'MXN', 300, 1000, 10);
  d := public.f360_growth_cockpit('2026-09-01', '2026-09-30');
  m := d->'markets'->0;
  IF m->'kpis'->'spend'->>'status' <> 'OK' OR (m->'kpis'->'cpc'->>'value')::numeric <> 2 OR (m->'kpis'->'ctr'->>'value')::numeric <> 1
     OR (m->'kpis'->'cpm'->>'value')::numeric <> 20 OR m->'kpis'->'cpa'->>'status' NOT IN ('OK', 'DATA_INCOMPLETE') THEN RAISE EXCEPTION 'C8 MX %', m->'kpis'; END IF;
  IF d->'markets'->1->'kpis'->'spend'->>'status' <> 'DATA_INCOMPLETE' OR d->'markets'->1->'kpis'->'cpm'->'value' <> 'null'::jsonb THEN RAISE EXCEPTION 'C8 CO %', d->'markets'->1->'kpis'->'spend'; END IF;
  -- C9 period validation
  BEGIN PERFORM public.f360_growth_cockpit('2026-10-10', '2026-10-01'); RAISE EXCEPTION 'C9'; EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'C9%' THEN RAISE; END IF; END;
  -- C10 channel rules
  IF f360.classify_channel_v1('utm', 'ig', 'paid', NULL) <> 'Meta pagado' OR f360.classify_channel_v1('utm', 'ig', 'social', NULL) <> 'Meta (UTM no pagado)'
     OR f360.classify_channel_v1('typein', NULL, NULL, NULL) <> 'Directo' OR f360.classify_channel_v1('organic', 'google', NULL, NULL) <> 'Búsqueda orgánica'
     OR f360.classify_channel_v1('referral', NULL, NULL, 'l.instagram.com') <> 'Instagram / Facebook orgánico' OR f360.classify_channel_v1(NULL, NULL, NULL, NULL) <> 'Sin atribución' THEN
    RAISE EXCEPTION 'C10';
  END IF;
  RAISE NOTICE 'ENSAYO OK';
END $$;
ROLLBACK;
