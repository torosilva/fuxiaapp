-- Fuxia 360 · CRO-3A product knowledge — database tests (STAGING). One transaction, ROLLED BACK.
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
INSERT INTO f360.user_roles (auth_user_id, role, display_name, granted_by) SELECT id, 'operator', 'ZZ Operación', 'test (rolled back)' FROM auth.users WHERE email = '15550100011@fuxia.app'
  ON CONFLICT (auth_user_id) DO UPDATE SET role = 'operator' RETURNING auth_user_id AS op \gset
SELECT set_config('t.carolina', :'carolina', true), set_config('t.op', :'op', true) \gset t_

DO $$
DECLARE car uuid := current_setting('t.carolina')::uuid; op uuid := current_setting('t.op')::uuid; r jsonb; pid uuid; n int;
BEGIN
  pid := (pg_temp.as(car, $q$SELECT public.f360_create_product('ZZ Saber Modelo', ARRAY['36','37'], '[{"name":"Negro"}]'::jsonb)$q$)->>'id')::uuid;
  PERFORM pg_temp.ok(pid IS NOT NULL, 'fixture: a model', '');

  r := pg_temp.as(op, format($q$SELECT public.f360_product_knowledge_save(%L, '{"fit_category":"true_to_size","between_sizes":"mayor","last_fit":"comoda","material_upper":"  Piel de res  ","heel_height_cm":"1.5","toe_type":"redonda","comfort_notes":"Plantilla acolchada"}')$q$, pid));
  PERFORM pg_temp.ok(r->'knowledge'->>'status' = 'borrador' AND r->'knowledge'->>'material_upper' = 'Piel de res' AND (r->'knowledge'->>'heel_height_cm')::numeric = 1.5
      AND (r->'knowledge'->>'version')::int = 1, 'operator saves a draft (trimmed, parsed, version 1)', left(coalesce(r->>'error', (r->'knowledge')::text), 120));
  PERFORM pg_temp.ok(r->'public' = 'null'::jsonb AND f360.product_knowledge_public(pid) IS NULL, 'a draft is NEVER exposed to channels', coalesce((r->'public')::text, 'null'));
  r := pg_temp.as(op, format($q$SELECT public.f360_product_knowledge_save(%L, '{}', true)$q$, pid));
  PERFORM pg_temp.ok(r->>'error' LIKE 'Solo una dueña%', 'only an owner validates', r->>'error');
  r := pg_temp.as(op, format($q$SELECT public.f360_product_knowledge_save(%L, '{"fit_category":"enorme"}')$q$, pid));
  PERFORM pg_temp.ok(r->>'error' LIKE 'Revisa los datos%', 'unknown values are refused with a clear message', r->>'error');
  r := pg_temp.as(op, format($q$SELECT public.f360_product_knowledge_save(%L, '{"precio":"1"}')$q$, pid));
  PERFORM pg_temp.ok(r->>'error' LIKE 'Campos no permitidos%', 'unknown fields are refused', r->>'error');
  r := pg_temp.as(op, format($q$SELECT public.f360_product_knowledge_save(%L, '{"heel_height_cm":"alto"}')$q$, pid));
  PERFORM pg_temp.ok(r->>'error' LIKE '%número%', 'heel height must be a number', r->>'error');

  r := pg_temp.as(car, format($q$SELECT public.f360_product_knowledge_save(%L, '{}', true)$q$, pid));
  PERFORM pg_temp.ok(r->'knowledge'->>'status' = 'validado' AND r->'knowledge'->>'validated_by_name' = 'Carolina', 'Carolina validates', coalesce(r->>'error', 'ok'));
  r := f360.product_knowledge_public(pid);
  PERFORM pg_temp.ok(r->'fit'->>'label' = 'Talla exacta' AND r->'fit'->>'advice' = 'Te recomendamos pedir tu talla habitual.' AND r->'fit'->>'between_sizes' = '¿Entre dos tallas? Elige la mayor.'
      AND r->>'last' = 'Cómoda' AND r->'materials'->>'upper' = 'Piel de res' AND r->>'product_key' LIKE 'F360-%' AND NOT (r ? 'care'),
    'channels get validated knowledge with customer labels (empty fields omitted)', r::text);

  r := pg_temp.as(car, format($q$SELECT public.f360_product_knowledge_save(%L, '{"care_instructions":"Limpiar con paño seco"}')$q$, pid));
  PERFORM pg_temp.ok(r->'knowledge'->>'status' = 'validado', 'an owner edit keeps it validated', r->'knowledge'->>'status');
  r := pg_temp.as(op, format($q$SELECT public.f360_product_knowledge_save(%L, '{"comfort_notes":"Otra cosa"}')$q$, pid));
  PERFORM pg_temp.ok(r->'knowledge'->>'status' = 'borrador' AND f360.product_knowledge_public(pid) IS NULL, 'a non-owner edit sends it back to draft (hidden until re-validated)', r->'knowledge'->>'status');
  r := pg_temp.as(op, format($q$SELECT public.f360_product_knowledge_save(%L, '{"comfort_notes":"Otra cosa"}')$q$, pid));
  SELECT count(*) INTO n FROM f360.product_knowledge_history WHERE product_id = pid;
  PERFORM pg_temp.ok(n = 4, 'every real change is a version in the history; a no-op save is not', n::text);
  BEGIN
    DELETE FROM f360.product_knowledge_history WHERE product_id = pid;
    PERFORM pg_temp.ok(false, 'history is append-only', 'deleted!');
  EXCEPTION WHEN OTHERS THEN PERFORM pg_temp.ok(true, 'history is append-only', SQLERRM);
  END;
  r := pg_temp.as(car, format($q$SELECT public.f360_product_knowledge_save(%L, '{"fit_category":""}', true)$q$, pid));
  PERFORM pg_temp.ok(r->>'error' LIKE 'Para validar%', 'validation requires the fit', r->>'error');

  r := pg_temp.as(op, $q$SELECT public.f360_product_knowledge_overview()$q$);
  PERFORM pg_temp.ok(r @> jsonb_build_array(jsonb_build_object('name', 'ZZ Saber Modelo')), 'overview lists models with their progress', left(r::text, 80));
  r := pg_temp.as(NULL, format($q$SELECT public.f360_product_knowledge_get(%L)$q$, pid), 'anon');
  PERFORM pg_temp.ok(r ? 'error', 'anon cannot read the admin knowledge', r->>'error');
END $$;

SELECT status || ' | ' || name || ' | ' || coalesce(detail, '') FROM t_results ORDER BY n;
ROLLBACK;
