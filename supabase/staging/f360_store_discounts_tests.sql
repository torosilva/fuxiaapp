-- Descuentos en la venta de tienda (20261025000100). STAGING. One transaction, ROLLED BACK; the migration is rehearsed inline.
-- Run: scripts/s00a/run.sh ../f360/sql_test_one.mjs supabase/staging/f360_store_discounts_tests.sql
-- Fixtures are synthetic ("ZZ D …") and live only inside this transaction. Carolina = the staging user named Carolina (approver),
-- Mario = the staging user named Mario (owner, NOT an approver), A = lab seller 15550100011.
BEGIN;
-- (20261025000100 is applied in staging; its body is rehearsed by the production dry-run)

CREATE TEMP TABLE t_results (n serial, status text, name text, detail text) ON COMMIT DROP;
GRANT ALL ON t_results TO authenticated, anon;
GRANT USAGE, SELECT ON SEQUENCE t_results_n_seq TO authenticated, anon;
CREATE TEMP TABLE t_ids (k text PRIMARY KEY, v uuid, t text) ON COMMIT DROP;
GRANT ALL ON t_ids TO authenticated, anon;
CREATE FUNCTION pg_temp.ok(p_cond boolean, p_name text, p_detail text) RETURNS void LANGUAGE sql AS
$$ INSERT INTO t_results(status,name,detail) VALUES (CASE WHEN coalesce(p_cond, false) THEN 'PASS' ELSE 'FAIL' END, p_name, p_detail) $$;
GRANT EXECUTE ON FUNCTION pg_temp.ok(boolean, text, text) TO authenticated, anon;
CREATE FUNCTION pg_temp.id(p_k text) RETURNS uuid LANGUAGE sql AS $$ SELECT v FROM t_ids WHERE k = p_k $$;
CREATE FUNCTION pg_temp.tx(p_k text) RETURNS text LANGUAGE sql AS $$ SELECT t FROM t_ids WHERE k = p_k $$;
CREATE FUNCTION pg_temp.as(p_uid uuid, p_sql text, p_role text DEFAULT 'authenticated') RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r jsonb;
BEGIN
  BEGIN
    PERFORM set_config('request.jwt.claims', CASE WHEN p_uid IS NULL THEN json_build_object('role', p_role)::text
      ELSE json_build_object('sub', p_uid, 'role', p_role)::text END, true);
    EXECUTE format('SET LOCAL ROLE %I', p_role);
    EXECUTE p_sql INTO r;
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN RESET ROLE; r := jsonb_build_object('error', SQLERRM); END;
  RETURN r;
END $$;
-- sale with an optional discount (pct, auth json)
CREATE FUNCTION pg_temp.sell(p_uid uuid, p_tok text, p_lines jsonb, p_pct numeric DEFAULT 0, p_auth jsonb DEFAULT NULL, p_key uuid DEFAULT gen_random_uuid()) RETURNS jsonb LANGUAGE sql AS
$$ SELECT pg_temp.as(p_uid, format('SELECT public.f360_record_store_sale(%L, %L, %L, %L, NULL, NULL, %s, %L)', p_tok, p_key, p_lines, 'cash', p_pct, p_auth)) $$;
CREATE FUNCTION pg_temp.lines(p_spec text) RETURNS jsonb LANGUAGE sql AS   -- '35:1,36:2'
$$ SELECT jsonb_agg(jsonb_build_object('variant_id', pg_temp.id('v' || split_part(x, ':', 1)), 'quantity', split_part(x, ':', 2)::int)) FROM unnest(string_to_array(p_spec, ',')) x $$;
CREATE FUNCTION pg_temp.ledger_mismatches() RETURNS int LANGUAGE sql AS $$
  WITH mv AS (SELECT variant_id, to_location_id AS loc, quantity AS q FROM f360.inventory_movements WHERE to_location_id IS NOT NULL
    UNION ALL SELECT variant_id, from_location_id, -quantity FROM f360.inventory_movements WHERE from_location_id IS NOT NULL),
  led AS (SELECT variant_id, loc, sum(q)::int AS q FROM mv GROUP BY 1, 2)
  SELECT count(*)::int FROM led FULL JOIN f360.inventory_balances b ON b.variant_id = led.variant_id AND b.location_id = led.loc
  WHERE coalesce(led.q, 0) <> coalesce(b.on_hand, 0) $$;

SELECT auth_user_id AS caro FROM f360.user_roles WHERE display_name = 'Carolina' ORDER BY auth_user_id LIMIT 1 \gset
SELECT auth_user_id AS mario FROM f360.user_roles WHERE display_name = 'Mario' ORDER BY auth_user_id LIMIT 1 \gset
SELECT id AS a FROM auth.users WHERE email = '15550190001@fuxia.app' \gset
INSERT INTO t_ids (k, v) VALUES ('caro', :'caro'), ('mario', :'mario'), ('A', :'a');

-- ── Fixtures ────────────────────────────────────────────────────────────────
DO $$
DECLARE o uuid := pg_temp.id('caro'); r jsonb; pid uuid;
BEGIN
  r := pg_temp.as(o, $q$SELECT public.f360_create_product('ZZ D Paula', ARRAY['35','36','37','38'], '[{"name":"Camel"}]'::jsonb)$q$);
  SELECT p.id INTO pid FROM f360.products p WHERE p.name = 'ZZ D Paula';
  INSERT INTO t_ids (k, v) VALUES ('P', pid);
  PERFORM pg_temp.as(o, format($q$SELECT public.f360_update_product(%L, '{"regular_price": 1999}'::jsonb)$q$, pid));
  INSERT INTO t_ids (k, v) SELECT 'v' || v.size_label, v.id FROM f360.product_variants v WHERE v.product_id = pid;
  INSERT INTO t_ids (k, v) SELECT 'L', (pg_temp.as(o, $q$SELECT public.f360_create_location('ZZ D Tienda', 'store')$q$)->>'id')::uuid;
  PERFORM pg_temp.as(o, format($q$SELECT public.f360_receive_inventory(gen_random_uuid(), %L, %L)$q$, pg_temp.id('L'),
    (SELECT jsonb_agg(jsonb_build_object('variant_id', pg_temp.id('v' || s), 'quantity', 30)) FROM unnest(ARRAY['35','36','37','38']) s)));
  PERFORM pg_temp.as(o, format($q$SELECT public.f360_set_user_role(%L, 'seller', 'ZZ Vendedora A')$q$, pg_temp.id('A')));
  PERFORM pg_temp.as(o, format($q$SELECT public.f360_set_location_assignment(%L, %L, true)$q$, pg_temp.id('A'), pg_temp.id('L')));
  PERFORM pg_temp.as(o, format($q$SELECT public.f360_set_seller_pin(%L, '2468')$q$, pg_temp.id('A')));
  PERFORM pg_temp.as(o, format($q$SELECT public.f360_set_seller_pin(%L, '9753')$q$, pg_temp.id('caro')));
  PERFORM pg_temp.as(o, format($q$SELECT public.f360_set_seller_pin(%L, '1111')$q$, pg_temp.id('mario')));
  INSERT INTO f360.approval_scopes (scope, auth_user_id, display_name, added_by_name, note) VALUES ('store_discount', o, 'Carolina', 'prueba', 'test') ON CONFLICT DO NOTHING;
  INSERT INTO t_ids (k, t) VALUES ('tokA', pg_temp.as(pg_temp.id('A'), format($q$SELECT public.f360_start_seller_shift(%L, '2468')$q$, pg_temp.id('L')))->>'token');
  INSERT INTO t_ids (k, t) VALUES ('tokC', pg_temp.as(o, format($q$SELECT public.f360_start_seller_shift(%L, '9753')$q$, pg_temp.id('L')))->>'token');
  INSERT INTO t_ids (k, t) VALUES ('tokM', pg_temp.as(pg_temp.id('mario'), format($q$SELECT public.f360_start_seller_shift(%L, '1111')$q$, pg_temp.id('L')))->>'token');
  PERFORM pg_temp.ok(pg_temp.tx('tokA') IS NOT NULL AND pg_temp.tx('tokC') IS NOT NULL AND pg_temp.tx('tokM') IS NOT NULL
    AND (SELECT ledger_authority FROM f360.locations WHERE id = pg_temp.id('L')) = 'f360',
    'fixture: F360 store with stock, seller A, Carolina (approver) and Mario (owner, not approver) on shift', coalesce(pg_temp.tx('tokA'), 'no A') || ' ' || coalesce(pg_temp.tx('tokM'), 'no M'));
END $$;

-- ═════ D1–D5 · seller limits ═════
DO $$
DECLARE r jsonb; s public.offline_sales; sumlines numeric;
BEGIN
  r := pg_temp.sell(pg_temp.id('A'), pg_temp.tx('tokA'), pg_temp.lines('35:1'));
  PERFORM pg_temp.ok((r->>'total')::numeric = 1999 AND (r->>'discount_pct')::numeric = 0 AND NOT (r->>'no_exchange')::boolean,
    'D1 no discount: total = list price, exchange allowed', r::text);
  r := pg_temp.sell(pg_temp.id('A'), pg_temp.tx('tokA'), pg_temp.lines('35:1,36:2'), 10);
  SELECT * INTO s FROM public.offline_sales WHERE id = (r->>'sale_id')::uuid;
  SELECT sum(line_total) INTO sumlines FROM public.offline_sale_items WHERE sale_id = s.id;
  PERFORM pg_temp.ok(s.gross_total = 5997 AND s.discount_amount = 599.70 AND s.total = 5397.30 AND sumlines = s.total AND s.no_exchange
      AND s.discount_authorization = 'within_seller_limit' AND s.discount_approved_by IS NULL
      AND (SELECT bool_and(unit_price = 1999) FROM public.offline_sale_items WHERE sale_id = s.id),
    'D2 seller 10%: gross 5997 → 5397.30, Σ lines = total, list unit price kept, no exchange', coalesce(r->>'error', s.total::text || ' / ' || sumlines::text));
  r := pg_temp.sell(pg_temp.id('A'), pg_temp.tx('tokA'), pg_temp.lines('35:1'), 15);
  PERFORM pg_temp.ok(r->>'error' LIKE 'Un descuento de más de 10% necesita la aprobación de Carolina%', 'D3 seller 15% alone: refused, names Carolina', r->>'error');
  r := pg_temp.sell(pg_temp.id('A'), pg_temp.tx('tokA'), pg_temp.lines('35:1'), 10.01);
  PERFORM pg_temp.ok(r->>'error' LIKE '%necesita la aprobación%', 'D4 10.01% is above the limit', r->>'error');
  PERFORM pg_temp.ok(pg_temp.sell(pg_temp.id('A'), pg_temp.tx('tokA'), pg_temp.lines('35:1'), -5)->>'error' LIKE '%porcentaje entre 0 y 100%'
    AND pg_temp.sell(pg_temp.id('A'), pg_temp.tx('tokA'), pg_temp.lines('35:1'), 101)->>'error' LIKE '%porcentaje entre 0 y 100%'
    AND pg_temp.sell(pg_temp.id('A'), pg_temp.tx('tokA'), pg_temp.lines('35:1'), 5.555)->>'error' LIKE '%porcentaje entre 0 y 100%',
    'D5 invalid percentages (-5, 101, 3 decimals) refused', '');
  r := pg_temp.as(pg_temp.id('A'), format($q$SELECT public.f360_record_store_sale(%L, %L, %L, 'cash', NULL, NULL, 0, '{"price": 1}')$q$,
    pg_temp.tx('tokA'), gen_random_uuid(), jsonb_build_array(jsonb_build_object('variant_id', pg_temp.id('v35'), 'quantity', 1, 'unit_price', 1))));
  PERFORM pg_temp.ok(r->>'error' LIKE 'Solo se aceptan producto y cantidad%', 'D5b a price in the lines is still refused', r->>'error');
END $$;

-- ═════ D6–D9 · Carolina's PIN on the seller's phone ═════
DO $$
DECLARE r jsonb; p jsonb; s public.offline_sales; q f360.store_discount_requests;
BEGIN
  p := pg_temp.as(pg_temp.id('A'), format($q$SELECT public.f360_store_discount_pin(%L, %L, 20, 'clienta frecuente', '0000')$q$, pg_temp.tx('tokA'), pg_temp.lines('37:1')));
  PERFORM pg_temp.ok(NOT (p->>'ok')::boolean AND p->>'error' = 'PIN incorrecto.'
      AND (SELECT count(*) FROM f360.seller_auth_events WHERE auth_user_id = pg_temp.id('A') AND event = 'discount_bad_pin') = 1,
    'D6 wrong PIN: refused without raising (attempt recorded)', p::text);
  p := pg_temp.as(pg_temp.id('A'), format($q$SELECT public.f360_store_discount_pin(%L, %L, 20, 'clienta frecuente', '1111')$q$, pg_temp.tx('tokA'), pg_temp.lines('37:1')));
  PERFORM pg_temp.ok(NOT (p->>'ok')::boolean, 'D6b Mario''s PIN (owner, not approver) does not approve', p::text);
  p := pg_temp.as(pg_temp.id('A'), format($q$SELECT public.f360_store_discount_pin(%L, %L, 20, 'clienta frecuente', '9753')$q$, pg_temp.tx('tokA'), pg_temp.lines('37:1')));
  PERFORM pg_temp.ok((p->>'ok')::boolean AND p->>'approved_by' = 'Carolina', 'D7a Carolina''s PIN approves', p::text);
  r := pg_temp.sell(pg_temp.id('A'), pg_temp.tx('tokA'), pg_temp.lines('37:1'), 20, jsonb_build_object('request_id', p->>'request_id'));
  SELECT * INTO s FROM public.offline_sales WHERE id = (r->>'sale_id')::uuid;
  SELECT * INTO q FROM f360.store_discount_requests WHERE id = (p->>'request_id')::uuid;
  PERFORM pg_temp.ok(s.total = 1599.20 AND s.discount_authorization = 'approver_pin' AND s.discount_approved_by = pg_temp.id('caro')
      AND s.discount_reason = 'clienta frecuente' AND q.status = 'used' AND q.used_sale_id = s.id,
    'D7 sale with the PIN approval: 20% → 1599.20, approved by Carolina, reason kept, approval consumed', coalesce(r->>'error', s.total::text));
  r := pg_temp.sell(pg_temp.id('A'), pg_temp.tx('tokA'), pg_temp.lines('37:1'), 20, jsonb_build_object('request_id', p->>'request_id'));
  PERFORM pg_temp.ok(r->>'error' LIKE '%ya se usó%', 'D8 an approval is used once', r->>'error');
  p := pg_temp.as(pg_temp.id('A'), format($q$SELECT public.f360_store_discount_pin(%L, %L, 20, NULL, '9753')$q$, pg_temp.tx('tokA'), pg_temp.lines('37:1')));
  r := pg_temp.sell(pg_temp.id('A'), pg_temp.tx('tokA'), pg_temp.lines('37:1'), 25, jsonb_build_object('request_id', p->>'request_id'));
  PERFORM pg_temp.ok(r->>'error' LIKE '%cambió%', 'D9a approved 20% cannot be used for 25%', r->>'error');
  r := pg_temp.sell(pg_temp.id('A'), pg_temp.tx('tokA'), pg_temp.lines('37:2'), 20, jsonb_build_object('request_id', p->>'request_id'));
  PERFORM pg_temp.ok(r->>'error' LIKE '%cambió%', 'D9b nor for other products / quantities', r->>'error');
  PERFORM pg_temp.as(pg_temp.id('caro'), format($q$SELECT public.f360_update_product(%L, '{"regular_price": 2500}'::jsonb)$q$, pg_temp.id('P')));
  r := pg_temp.sell(pg_temp.id('A'), pg_temp.tx('tokA'), pg_temp.lines('37:1'), 20, jsonb_build_object('request_id', p->>'request_id'));
  PERFORM pg_temp.ok(r->>'error' LIKE '%cambió%', 'D9c nor after the price changed', r->>'error');
  PERFORM pg_temp.as(pg_temp.id('caro'), format($q$SELECT public.f360_update_product(%L, '{"regular_price": 1999}'::jsonb)$q$, pg_temp.id('P')));
END $$;

-- ═════ D10–D11 · remote request ═════
DO $$
DECLARE r jsonb; q jsonb; s public.offline_sales; inbox jsonb;
BEGIN
  q := pg_temp.as(pg_temp.id('A'), format($q$SELECT public.f360_store_discount_request(%L, %L, 30, 'par con detalle')$q$, pg_temp.tx('tokA'), pg_temp.lines('38:1')));
  PERFORM pg_temp.ok((q->>'ok')::boolean AND (q->>'net_total')::numeric = 1399.30
      AND EXISTS (SELECT 1 FROM f360.push_outbox WHERE auth_user_id = pg_temp.id('caro') AND data->>'request_id' = q->>'request_id'),
    'D10a request 30%: pending, net computed by the server, push queued for Carolina', q::text);
  r := pg_temp.sell(pg_temp.id('A'), pg_temp.tx('tokA'), pg_temp.lines('38:1'), 30, jsonb_build_object('request_id', q->>'request_id'));
  PERFORM pg_temp.ok(r->>'error' LIKE '%todavía no está aprobado%', 'D10b cannot sell while pending', r->>'error');
  r := pg_temp.as(pg_temp.id('mario'), format($q$SELECT public.f360_store_discount_decide(%L, true)$q$, q->>'request_id'));
  PERFORM pg_temp.ok(r->>'error' LIKE '%No tienes permiso%', 'D10c Mario (owner) cannot approve', r->>'error');
  r := pg_temp.as(pg_temp.id('A'), format($q$SELECT public.f360_store_discount_decide(%L, true)$q$, q->>'request_id'));
  PERFORM pg_temp.ok(r->>'error' LIKE '%No tienes permiso%', 'D10d the seller cannot approve her own request', r->>'error');
  PERFORM pg_temp.ok((pg_temp.as(pg_temp.id('mario'), 'SELECT public.f360_store_discount_inbox()')->>'can_approve')::boolean = false,
    'D10e Mario''s inbox: not an approver, sees nothing', '');
  inbox := pg_temp.as(pg_temp.id('caro'), 'SELECT public.f360_store_discount_inbox()');
  PERFORM pg_temp.ok((inbox->>'can_approve')::boolean AND inbox->'pending' @> jsonb_build_array(jsonb_build_object('id', q->>'request_id', 'seller', 'ZZ Vendedora A')),
    'D10f Carolina''s inbox shows it (seller, store, products, amounts)', left(inbox::text, 200));
  r := pg_temp.as(pg_temp.id('caro'), format($q$SELECT public.f360_store_discount_decide(%L, true, 'ok')$q$, q->>'request_id'));
  PERFORM pg_temp.ok(r->>'status' = 'approved'
      AND pg_temp.as(pg_temp.id('A'), format($q$SELECT public.f360_store_discount_status(%L, %L)$q$, pg_temp.tx('tokA'), q->>'request_id'))->>'status' = 'approved'
      AND EXISTS (SELECT 1 FROM f360.push_outbox WHERE auth_user_id = pg_temp.id('A') AND data->>'type' = 'f360_discount_decision'),
    'D10g Carolina approves → the seller sees it (status + push)', r::text);
  r := pg_temp.sell(pg_temp.id('A'), pg_temp.tx('tokA'), pg_temp.lines('38:1'), 30, jsonb_build_object('request_id', q->>'request_id'));
  SELECT * INTO s FROM public.offline_sales WHERE id = (r->>'sale_id')::uuid;
  PERFORM pg_temp.ok(s.total = 1399.30 AND s.discount_authorization = 'approver_remote' AND s.discount_approved_by_name = 'Carolina' AND s.no_exchange,
    'D10 remote approval → sale 30%: 1399.30, approved remotely by Carolina, no exchange', coalesce(r->>'error', s.total::text));
  r := pg_temp.as(pg_temp.id('caro'), format($q$SELECT public.f360_store_discount_decide(%L, false)$q$, q->>'request_id'));
  PERFORM pg_temp.ok(r->>'error' LIKE '%ya no está pendiente%', 'D10h a decided request cannot be decided again', r->>'error');

  q := pg_temp.as(pg_temp.id('A'), format($q$SELECT public.f360_store_discount_request(%L, %L, 40, NULL)$q$, pg_temp.tx('tokA'), pg_temp.lines('38:1')));
  PERFORM pg_temp.as(pg_temp.id('caro'), format($q$SELECT public.f360_store_discount_decide(%L, false, 'demasiado')$q$, q->>'request_id'));
  r := pg_temp.sell(pg_temp.id('A'), pg_temp.tx('tokA'), pg_temp.lines('38:1'), 40, jsonb_build_object('request_id', q->>'request_id'));
  PERFORM pg_temp.ok(r->>'error' LIKE '%todavía no está aprobado%'
      AND pg_temp.as(pg_temp.id('A'), format($q$SELECT public.f360_store_discount_status(%L, %L)$q$, pg_temp.tx('tokA'), q->>'request_id'))->>'status' = 'rejected',
    'D11 rejected request: no sale, seller sees "rejected"', r->>'error');
  q := pg_temp.as(pg_temp.id('A'), format($q$SELECT public.f360_store_discount_request(%L, %L, 15, NULL)$q$, pg_temp.tx('tokA'), pg_temp.lines('38:1')));
  UPDATE f360.store_discount_requests SET expires_at = now() - interval '1 minute' WHERE id = (q->>'request_id')::uuid;
  r := pg_temp.as(pg_temp.id('caro'), format($q$SELECT public.f360_store_discount_decide(%L, true)$q$, q->>'request_id'));
  PERFORM pg_temp.ok(r->>'error' LIKE '%venció%'
      AND pg_temp.as(pg_temp.id('A'), format($q$SELECT public.f360_store_discount_status(%L, %L)$q$, pg_temp.tx('tokA'), q->>'request_id'))->>'status' = 'expired',
    'D11b an expired request cannot be approved; the seller sees "expired"', r->>'error');
  PERFORM pg_temp.ok(pg_temp.as(pg_temp.id('A'), format($q$SELECT public.f360_store_discount_request(%L, %L, 8, NULL)$q$, pg_temp.tx('tokA'), pg_temp.lines('38:1')))->>'error' LIKE 'Hasta 10% no necesita%',
    'D11c up to 10% needs no request', '');
END $$;

-- ═════ D12–D13 · own shifts ═════
DO $$
DECLARE r jsonb; s public.offline_sales;
BEGIN
  r := pg_temp.sell(pg_temp.id('caro'), pg_temp.tx('tokC'), pg_temp.lines('36:1'), 50);
  SELECT * INTO s FROM public.offline_sales WHERE id = (r->>'sale_id')::uuid;
  PERFORM pg_temp.ok(s.total = 999.50 AND s.discount_authorization = 'approver_self' AND s.discount_approved_by = pg_temp.id('caro'),
    'D12 Carolina on her own shift: 50% with no approval step', coalesce(r->>'error', s.total::text));
  r := pg_temp.sell(pg_temp.id('mario'), pg_temp.tx('tokM'), pg_temp.lines('36:1'), 15);
  PERFORM pg_temp.ok(r->>'error' LIKE '%necesita la aprobación de Carolina%', 'D13a Mario (owner) on his shift: 15% still needs Carolina', r->>'error');
  r := pg_temp.sell(pg_temp.id('mario'), pg_temp.tx('tokM'), pg_temp.lines('36:1'), 10);
  PERFORM pg_temp.ok((r->>'total')::numeric = 1799.10, 'D13b Mario: 10% like any seller', coalesce(r->>'error', r->>'total'));
  r := pg_temp.as(pg_temp.id('A'), format($q$SELECT public.f360_shift_discount_policy(%L)$q$, pg_temp.tx('tokA')));
  PERFORM pg_temp.ok((r->>'seller_max_pct')::numeric = 10 AND NOT (r->>'can_any')::boolean AND r->>'approvers' = 'Carolina'
      AND (pg_temp.as(pg_temp.id('caro'), format($q$SELECT public.f360_shift_discount_policy(%L)$q$, pg_temp.tx('tokC')))->>'can_any')::boolean,
    'D13c policy: seller max 10, approver Carolina; Carolina can_any', r::text);
END $$;

-- ═════ D14 · PIN lockout ═════
DO $$
DECLARE p jsonb; i int;
BEGIN
  FOR i IN 1..4 LOOP   -- D6 already recorded one failure
    PERFORM pg_temp.as(pg_temp.id('A'), format($q$SELECT public.f360_store_discount_pin(%L, %L, 20, NULL, '0000')$q$, pg_temp.tx('tokA'), pg_temp.lines('35:1')));
  END LOOP;
  p := pg_temp.as(pg_temp.id('A'), format($q$SELECT public.f360_store_discount_pin(%L, %L, 20, NULL, '9753')$q$, pg_temp.tx('tokA'), pg_temp.lines('35:1')));
  PERFORM pg_temp.ok(NOT (p->>'ok')::boolean AND p->>'error' LIKE 'Demasiados intentos%', 'D14 after 5 wrong PINs even the right one is refused for 15 min', p::text);
END $$;

-- ═════ D15–D20 · access, replay, compatibility, reporting, ledger ═════
DO $$
DECLARE r jsonb; k uuid := gen_random_uuid(); s public.offline_sales;
BEGIN
  PERFORM pg_temp.ok(pg_temp.as(NULL, 'SELECT public.f360_store_discount_inbox()', 'anon')->>'error' LIKE '%permission denied%'
    AND pg_temp.as(NULL, format($q$SELECT public.f360_store_discount_decide(%L, true)$q$, gen_random_uuid()), 'anon')->>'error' LIKE '%permission denied%'
    AND pg_temp.as(NULL, $q$SELECT public.f360_store_discount_pin('x', '[]', 20, NULL, '9753')$q$, 'anon')->>'error' LIKE '%permission denied%',
    'D15 anonymous: inbox / decide / PIN refused', '');
  PERFORM pg_temp.ok(pg_temp.as(pg_temp.id('A'), 'SELECT to_jsonb(count(*)) FROM f360.store_discount_requests')->>'error' LIKE '%permission denied%',
    'D15b the requests table is not readable by app users', '');
  r := pg_temp.sell(pg_temp.id('A'), pg_temp.tx('tokA'), pg_temp.lines('35:1'), 10, NULL, k);
  r := pg_temp.sell(pg_temp.id('A'), pg_temp.tx('tokA'), pg_temp.lines('35:1'), 10, NULL, k);
  PERFORM pg_temp.ok((r->>'replayed')::boolean AND (r->>'total')::numeric = 1799.10 AND (r->>'discount_pct')::numeric = 10 AND (r->>'no_exchange')::boolean,
    'D16 replay (same key) returns the same discounted sale', r::text);
  r := pg_temp.as(pg_temp.id('A'), format($q$SELECT public.f360_record_store_sale(p_token := %L, p_idempotency_key := %L, p_lines := %L, p_payment_method := 'card')$q$,
    pg_temp.tx('tokA'), gen_random_uuid(), pg_temp.lines('35:1')));
  PERFORM pg_temp.ok((r->>'total')::numeric = 1999, 'D17 the published app''s call (no discount parameters) still works', coalesce(r->>'error', r->>'total'));
  r := pg_temp.as(pg_temp.id('A'), format($q$SELECT public.f360_record_store_sale_for(p_token := %L, p_idempotency_key := %L, p_lines := %L, p_payment_method := 'card', p_discount_pct := 5)$q$,
    pg_temp.tx('tokA'), gen_random_uuid(), pg_temp.lines('35:1')));
  PERFORM pg_temp.ok((r->>'total')::numeric = 1899.05, 'D18 f360_record_store_sale_for passes the discount through', coalesce(r->>'error', r->>'total'));
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM f360.commerce_orders c JOIN public.offline_sales os ON os.id = c.store_sale_id
      WHERE os.location_id = pg_temp.id('L') AND (c.data_quality = 'UNVERIFIED' OR c.net_order_total <> os.total)),
    'D19 commerce facts: discounted store sales stay VERIFIED and count the NET total', '');
  PERFORM pg_temp.ok(pg_temp.ledger_mismatches() = 0, 'D20 balances = ledger after every discounted sale', 'mismatches=' || pg_temp.ledger_mismatches());
END $$;

SELECT status || ' | ' || name || ' | ' || left(coalesce(detail,''), 140) FROM t_results ORDER BY n;
ROLLBACK;
