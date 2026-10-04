-- Bandeja de clientas — database tests (STAGING). One transaction, ROLLED BACK.
BEGIN;
CREATE TEMP TABLE t_results (n serial, status text, name text, detail text) ON COMMIT DROP;
CREATE FUNCTION pg_temp.ok(p_cond boolean, p_name text, p_detail text) RETURNS void LANGUAGE sql AS
$$ INSERT INTO t_results(status,name,detail) VALUES (CASE WHEN coalesce(p_cond, false) THEN 'PASS' ELSE 'FAIL' END, p_name, p_detail) $$;
CREATE FUNCTION pg_temp.as(p_uid uuid, p_sql text, p_role text DEFAULT 'authenticated') RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r jsonb;
BEGIN
  BEGIN
    PERFORM set_config('request.jwt.claims', CASE WHEN p_uid IS NULL THEN json_build_object('role', p_role)::text ELSE json_build_object('sub', p_uid, 'role', p_role)::text END, true);
    EXECUTE format('SET LOCAL ROLE %I', p_role);
    EXECUTE p_sql INTO r;
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN RESET ROLE; r := jsonb_build_object('error', SQLERRM); END;
  RETURN r;
END $$;
SELECT auth_user_id AS carolina FROM f360.user_roles WHERE display_name = 'Carolina' \gset
SELECT set_config('t.carolina', :'carolina', true) \gset t_

DO $$
DECLARE car uuid := current_setting('t.carolina')::uuid; r jsonb; cid uuid; n int;
BEGIN
  -- 1 · Hilo escalates (no contact yet)
  r := public.f360_case_upsert('{"conversation_id":"zz-conv-1","source":"hilo_web","reason":"requested","summary":"Quiere hablar con alguien",
        "transcript":[{"role":"user","content":"quiero hablar con una persona"},{"role":"assistant","content":"Te conecto"}],"product":"Botas Largas","color":"Café","size":"24","country":"mx"}');
  cid := (r->>'id')::uuid;
  PERFORM pg_temp.ok(r->>'new' = 'true' AND EXISTS (SELECT 1 FROM f360.customer_cases WHERE id = cid AND kind = 'escalacion' AND status = 'nueva' AND jsonb_array_length(transcript) = 2),
    'Hilo escalation creates a case with summary + transcript', r::text);
  PERFORM pg_temp.ok((SELECT count(*) FROM f360.email_outbox WHERE ref_id = cid AND kind = 'customer_case_nuevo' AND to_email = 'info@fuxiaballerinas.com' AND body_text LIKE '%Clienta: quiero hablar%') = 1,
    'new case → one e-mail to info@ with the conversation', '');
  -- 2 · the customer leaves her WhatsApp in the web chat → same case, e-mail "dejó su WhatsApp", nothing erased
  r := public.f360_case_upsert('{"conversation_id":"zz-conv-1","name":"Ana","phone":"+15550100088"}');
  PERFORM pg_temp.ok(r->>'new' = 'false' AND (SELECT phone = '+15550100088' AND customer_name = 'Ana' AND summary = 'Quiere hablar con alguien' AND product_name = 'Botas Largas' FROM f360.customer_cases WHERE id = cid),
    'contact completes the SAME case; earlier data kept', r::text);
  PERFORM pg_temp.ok((SELECT count(*) FROM f360.email_outbox WHERE ref_id = cid AND kind = 'customer_case_contacto' AND body_text LIKE '%wa.me/15550100088%') = 1, 'contact → e-mail with WhatsApp link', '');
  r := public.f360_case_upsert('{"conversation_id":"zz-conv-1","name":"Ana","phone":"+15550100088"}');
  PERFORM pg_temp.ok((SELECT count(*) FROM f360.email_outbox WHERE ref_id = cid) = 2, 'repeating it does not e-mail again', '');
  -- 3 · "a la medida" also appears in the inbox
  r := public.f360_custom_request_create('{"target_key":"woo_staging4","woo_product_id":"145","product_name":"x","color":"Rojo","size":"25 MX","name":"Bea","phone":"+15550100066","country":"mx"}');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM f360.customer_cases WHERE custom_request_id = (r->>'id')::uuid AND kind = 'a_la_medida' AND color = 'Rojo'), 'a la medida request → case in the inbox', '');
  -- 4 · team
  r := pg_temp.as(car, $q$SELECT public.f360_inbox_list()$q$);
  PERFORM pg_temp.ok(jsonb_array_length(r) >= 2 AND EXISTS (SELECT 1 FROM jsonb_array_elements(r) x WHERE x->>'name' = 'Ana' AND x->>'phone' = '+15550100088'), 'team sees both kinds, with the phone', left(r::text, 100));
  r := pg_temp.as(car, format($q$SELECT public.f360_case_set(%L, 'resuelta')$q$, cid));
  PERFORM pg_temp.ok(r->>'status' = 'resuelta', 'operator resolves it', r::text);
  PERFORM public.f360_case_upsert('{"conversation_id":"zz-conv-1","summary":"Volvió a escribir"}');
  PERFORM pg_temp.ok((SELECT status FROM f360.customer_cases WHERE id = cid) = 'nueva', 'she writes again → reopened as nueva', '');
  -- 5 · security
  r := pg_temp.as(NULL, $q$SELECT public.f360_case_upsert('{"conversation_id":"x"}')$q$, 'anon');
  PERFORM pg_temp.ok(r ? 'error', 'anonymous cannot write cases directly', r::text);
  r := pg_temp.as(NULL, $q$SELECT public.f360_inbox_list()$q$, 'anon');
  PERFORM pg_temp.ok(r ? 'error', 'anonymous cannot read the inbox', r::text);
  BEGIN PERFORM public.f360_case_upsert('{"conversation_id":"zz-conv-2","phone":"5512"}'); r := '{}'; EXCEPTION WHEN OTHERS THEN r := jsonb_build_object('error', SQLERRM); END;
  PERFORM pg_temp.ok(r ? 'error', 'invalid phone refused', r::text);
END $$;

SELECT status || ' | ' || name || ' | ' || left(coalesce(detail,''), 110) FROM t_results ORDER BY n;
ROLLBACK;
