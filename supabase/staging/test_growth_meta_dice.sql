-- 20261102000100 "Meta dice" — rolled-back checks (staging). Run: scripts/s00a/run.sh ../f360/sql_test_one.mjs supabase/staging/test_growth_meta_dice.sql
-- Applied to staging 2026-10-24 (before that, the migration was rehearsed here with an @include line).
BEGIN;
CREATE TEMP TABLE _r (n serial, line text);
SELECT set_config('request.jwt.claims', json_build_object('sub', (SELECT auth_user_id FROM f360.user_roles WHERE role = 'owner'
  ORDER BY display_name = 'Mario' DESC LIMIT 1), 'role', 'authenticated')::text, true) IS NOT NULL AS jwt_set;
CREATE TEMP TABLE before_mig AS SELECT public.f360_growth_campaigns('2026-10-01', '2026-10-23') AS j;
DO $$
DECLARE owner uuid := (SELECT auth_user_id FROM f360.user_roles WHERE role = 'owner' ORDER BY display_name = 'Mario' DESC LIMIT 1);
  b jsonb := (SELECT j FROM before_mig); a jsonb; c jsonb; r jsonb; ok boolean;
  row0 jsonb := jsonb_build_object('date', '2026-10-17', 'market', 'CO', 'account_id', 'zz_acct_meta', 'campaign_id', 'zz_camp_meta', 'campaign_name', 'ZZ prueba',
                                   'currency', 'MXN', 'spend', '100.00', 'impressions', '10', 'clicks', '2');
BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('sub', owner, 'role', 'authenticated')::text, true);
  -- D1 nothing imported with the new fields yet → same spend / sales / verdicts as before; Meta columns are NULL (unknown, not 0)
  a := public.f360_growth_campaigns('2026-10-01', '2026-10-23');
  IF (a->'totals'->>'spend') IS DISTINCT FROM (b->'totals'->>'spend') OR (a->'totals'->>'paid_orders') <> (b->'totals'->>'paid_orders')
     OR (a->'totals'->>'ad_orders') <> (b->'totals'->>'ad_orders') THEN RAISE EXCEPTION 'D1 totals % vs %', a->'totals', b->'totals'; END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(a->'campaigns') x, jsonb_array_elements(b->'campaigns') y
             WHERE x->>'campaign_id' = y->>'campaign_id' AND (x->>'verdict' <> y->>'verdict' OR x->>'paid_orders' <> y->>'paid_orders' OR x->>'spend' IS DISTINCT FROM y->>'spend'))
     OR jsonb_array_length(a->'campaigns') < jsonb_array_length(b->'campaigns') THEN RAISE EXCEPTION 'D1 campaigns changed'; END IF;
  INSERT INTO _r (line) VALUES (format('PASS | D1 sin datos nuevos, Campañas igual que antes (gasto %s, pedidos %s)', a->'totals'->>'spend', a->'totals'->>'paid_orders'));

  -- D2 an import WITH Meta purchases → stored, in the view, and per campaign in Campañas (value in the account currency)
  r := public.f360_marketing_spend_api_import('meta', 'zz_acct_meta', 'MXN', '2026-10-17', '2026-10-17',
         jsonb_build_array(row0 || jsonb_build_object('meta_purchases', '5', 'meta_purchase_value', '15433.35', 'meta_add_to_cart', '9')));
  IF r->>'result' <> 'accepted' THEN RAISE EXCEPTION 'D2 import %', r; END IF;
  IF NOT EXISTS (SELECT 1 FROM f360.marketing_spend_daily WHERE account_id = 'zz_acct_meta' AND meta_purchases = 5 AND meta_purchase_value = 15433.35 AND meta_add_to_cart = 9)
    THEN RAISE EXCEPTION 'D2 view'; END IF;
  a := public.f360_growth_campaigns('2026-10-01', '2026-10-23');
  SELECT x INTO c FROM jsonb_array_elements(a->'campaigns') x WHERE x->>'campaign_id' = 'zz_camp_meta';
  IF (c->>'meta_purchases')::int <> 5 OR (c->>'meta_purchase_value')::numeric <> 15433.35 OR (c->>'meta_add_to_cart')::int <> 9
     OR (c->>'paid_orders')::int <> 0 OR c->>'verdict' <> 'sin_ventas' THEN RAISE EXCEPTION 'D2 campaign %', c; END IF;
  IF (a->'totals'->>'meta_purchases')::int < 5 OR a->'sources'->>'meta_says' IS NULL THEN RAISE EXCEPTION 'D2 totals %', a->'totals'; END IF;
  INSERT INTO _r (line) VALUES (format('PASS | D2 "Meta dice: 5" por campaña; ventas reales y veredicto no cambian (sin_ventas)'));

  -- D3 a newer read of the same day wins (backfill re-pull of a gap)
  r := public.f360_marketing_spend_api_import('meta', 'zz_acct_meta', 'MXN', '2026-10-17', '2026-10-17',
         jsonb_build_array(row0 || jsonb_build_object('meta_purchases', '6', 'meta_purchase_value', '16000', 'meta_add_to_cart', '9')));
  IF (SELECT meta_purchases FROM f360.marketing_spend_daily WHERE account_id = 'zz_acct_meta') <> 6 THEN RAISE EXCEPTION 'D3'; END IF;
  INSERT INTO _r (line) VALUES (format('PASS | D3 una lectura nueva del mismo día reemplaza la anterior'));

  -- D4 invalid Meta numbers reject the whole window; rows WITHOUT the fields stay valid (CSV / older function unaffected)
  ok := false;
  BEGIN PERFORM public.f360_marketing_spend_api_import('meta', 'zz_acct_meta', 'MXN', '2026-10-18', '2026-10-18',
          jsonb_build_array(row0 || jsonb_build_object('date', '2026-10-18', 'meta_purchases', '-1')));
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM LIKE '%compras / carritos de Meta%'; END;
  IF NOT ok THEN RAISE EXCEPTION 'D4 negative accepted'; END IF;
  ok := false;
  BEGIN PERFORM public.f360_marketing_spend_api_import('meta', 'zz_acct_meta', 'MXN', '2026-10-18', '2026-10-18',
          jsonb_build_array(row0 || jsonb_build_object('date', '2026-10-18', 'meta_purchases', '1', 'meta_purchase_value', '12.345')));
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM LIKE '%valor de compras de Meta%'; END;
  IF NOT ok THEN RAISE EXCEPTION 'D4 value accepted'; END IF;
  r := public.f360_marketing_spend_api_import('meta', 'zz_acct_meta', 'MXN', '2026-10-19', '2026-10-19', jsonb_build_array(row0 || jsonb_build_object('date', '2026-10-19')));
  IF r->>'result' <> 'accepted' OR (SELECT meta_purchases FROM f360.marketing_spend_daily WHERE account_id = 'zz_acct_meta' AND date = '2026-10-19') IS NOT NULL
    THEN RAISE EXCEPTION 'D4 plain row %', r; END IF;
  INSERT INTO _r (line) VALUES (format('PASS | D4 valores inválidos rechazan la ventana; filas sin el dato siguen siendo válidas (NULL)'));

  -- D5 a campaign with Meta purchases but 0 spend in the period is listed, not counted as ad spend / ad sales
  r := public.f360_marketing_spend_api_import('meta', 'zz_acct_meta', 'MXN', '2026-10-20', '2026-10-20',
         jsonb_build_array(row0 || jsonb_build_object('date', '2026-10-20', 'campaign_id', 'zz_camp_cero', 'spend', '0', 'impressions', '0', 'meta_purchases', '1', 'meta_purchase_value', '2800')));
  a := public.f360_growth_campaigns('2026-10-20', '2026-10-20');
  SELECT x INTO c FROM jsonb_array_elements(a->'campaigns') x WHERE x->>'campaign_id' = 'zz_camp_cero';
  IF c IS NULL OR c->>'verdict' <> 'sin_gasto' OR (c->>'meta_purchases')::int <> 1 OR c->>'return' IS NOT NULL THEN RAISE EXCEPTION 'D5 %', c; END IF;
  INSERT INTO _r (line) VALUES (format('PASS | D5 campaña con compras de Meta y gasto 0 aparece como "sin gasto"'));

  -- D6 permissions unchanged: anon cannot read Campañas; authenticated cannot call the import
  IF has_function_privilege('anon', 'public.f360_growth_campaigns(date,date)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.f360_marketing_spend_api_import(text,text,text,date,date,jsonb)', 'EXECUTE')
     OR has_table_privilege('authenticated', 'f360.marketing_spend_daily', 'SELECT') THEN RAISE EXCEPTION 'D6 grants'; END IF;
  INSERT INTO _r (line) VALUES (format('PASS | D6 permisos iguales (anon no lee Campañas; nadie más importa)'));
END $$;
SELECT line FROM _r ORDER BY n;
ROLLBACK;
