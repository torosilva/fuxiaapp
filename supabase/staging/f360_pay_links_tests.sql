-- Link de pago (checkout rescue) — database tests (STAGING). One transaction, ROLLED BACK.
BEGIN;
CREATE TEMP TABLE t_results (n serial, status text, name text, detail text) ON COMMIT DROP;
CREATE FUNCTION pg_temp.ok(p_cond boolean, p_name text, p_detail text) RETURNS void LANGUAGE sql AS
$$ INSERT INTO t_results(status,name,detail) VALUES (CASE WHEN coalesce(p_cond, false) THEN 'PASS' ELSE 'FAIL' END, p_name, p_detail) $$;
CREATE FUNCTION pg_temp.as(p_sql text, p_role text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r jsonb;
BEGIN
  BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('role', p_role)::text, true);
    EXECUTE format('SET LOCAL ROLE %I', p_role); EXECUTE p_sql INTO r; RESET ROLE;
  EXCEPTION WHEN OTHERS THEN RESET ROLE; r := jsonb_build_object('error', SQLERRM); END;
  RETURN r;
END $$;

DO $$
DECLARE r jsonb; cid uuid; i int;
BEGIN
  r := public.f360_pay_link_open('{"name":"Ana López","phone":"+525599990001","email":"ana@x.mx","country":"mx","products":"Botas Largas · Negro · 36","reason":"pago rechazado"}');
  cid := (r->>'id')::uuid;
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM f360.customer_cases WHERE id = cid AND kind = 'link_pago' AND source = 'web_checkout' AND status = 'nueva' AND phone = '+525599990001'),
    'a link request opens a case in the Bandeja (link_pago · web_checkout)', r::text);
  PERFORM public.f360_pay_link_done(cid, 990001, '$4,200', 'https://staging4.fuxiaballerinas.com/mx/finalizar-compra/order-pay/990001/?key=k');
  PERFORM pg_temp.ok((SELECT summary FROM f360.customer_cases WHERE id = cid) LIKE '%Pedido #990001%Link de pago: https://staging4%', 'the case keeps the order number and the link', '');
  PERFORM pg_temp.ok((SELECT count(*) FROM f360.email_outbox WHERE ref_id = cid AND kind = 'customer_case_link' AND to_email = 'info@fuxiaballerinas.com' AND body_text LIKE '%wa.me/525599990001%') = 1,
    'one e-mail to the team with WhatsApp and the link', '');
  -- a failure is recorded, no e-mail
  r := public.f360_pay_link_open('{"name":"Ana","phone":"+525599990001","email":"ana@x.mx","country":"mx"}');
  PERFORM public.f360_pay_link_done((r->>'id')::uuid, 0, NULL, NULL, 'Woo down');
  PERFORM pg_temp.ok((SELECT summary FROM f360.customer_cases WHERE id = (r->>'id')::uuid) LIKE '%No se pudo crear el pedido: Woo down%'
    AND NOT EXISTS (SELECT 1 FROM f360.email_outbox WHERE ref_id = (r->>'id')::uuid), 'a Woo failure is written in the case, without e-mail', '');
  -- limit: 3 per phone per day
  PERFORM public.f360_pay_link_open('{"name":"Ana","phone":"+525599990001","email":"ana@x.mx","country":"mx"}');
  BEGIN PERFORM public.f360_pay_link_open('{"name":"Ana","phone":"+525599990001","email":"ana@x.mx","country":"mx"}'); r := '{}';
  EXCEPTION WHEN OTHERS THEN r := jsonb_build_object('error', SQLERRM); END;
  PERFORM pg_temp.ok(r->>'error' LIKE 'Ya te generamos links hoy%', '4th link of the same phone in a day is refused', r::text);
  BEGIN PERFORM public.f360_pay_link_open('{"name":"Ana","phone":"5512","country":"mx"}'); r := '{}'; EXCEPTION WHEN OTHERS THEN r := jsonb_build_object('error', SQLERRM); END;
  PERFORM pg_temp.ok(r ? 'error', 'invalid phone refused', r::text);
  -- security: only the Edge Function (service role)
  r := pg_temp.as($q$SELECT public.f360_pay_link_open('{"phone":"+525599990002"}')$q$, 'anon');
  PERFORM pg_temp.ok(r ? 'error', 'anonymous cannot open links directly', r::text);
  r := pg_temp.as($q$SELECT to_jsonb(public.f360_pay_link_done(gen_random_uuid(), 1, '1', 'x'))$q$, 'authenticated');
  PERFORM pg_temp.ok(r ? 'error', 'app users cannot write link results', r::text);
  -- the inbox shows it
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM f360.customer_cases WHERE kind = 'escalacion' OR kind = 'a_la_medida' OR kind = 'link_pago'), 'older kinds still valid', '');
END $$;

SELECT status || ' | ' || name || ' | ' || left(coalesce(detail,''), 110) FROM t_results ORDER BY n;
ROLLBACK;
