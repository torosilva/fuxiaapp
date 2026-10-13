-- D12 interruptor · PRODUCCIÓN · ENSAYO (solo --dry-run): aplicar → prueba T1–T5 → reversión → comprobación, en UNA transacción que se deshace.
BEGIN;
DO $$ BEGIN
  IF (SELECT md5(string_agg(c::text, ',' ORDER BY id)) FROM (SELECT id, name, type, location, active FROM public.channels) c) <> '4f613a63cdefa76ff2f3c4c762e008fa' THEN RAISE EXCEPTION 'D12-SW PRE: tiendas distintas a lo revisado'; END IF;
  IF (SELECT md5(string_agg(format('%s|%s|%s|%s|%s|%s', tablename, policyname, cmd, roles::text, coalesce(qual,''), coalesce(with_check,'')), E'\n' ORDER BY tablename, policyname)) || ' ' || count(*) FROM pg_policies WHERE schemaname = 'public' AND roles::text LIKE '%anon%') <> 'a8609ffb7700f84e1104acf7e2b76732 7' THEN RAISE EXCEPTION 'D12-SW PRE: políticas anon distintas'; END IF;
  IF (SELECT md5(string_agg(format('%s|%s|%s|%s|%s|%s', tablename, policyname, cmd, roles::text, coalesce(qual,''), coalesce(with_check,'')), E'\n' ORDER BY tablename, policyname)) || ' ' || count(*) FROM pg_policies WHERE schemaname = 'public' AND tablename = 'channels') <> '383f6af1e1ef126ac0dd32df314ba34e 5' THEN RAISE EXCEPTION 'D12-SW PRE: políticas de channels distintas'; END IF;
  IF (SELECT md5(string_agg(format('%s|%s|%s', table_name, grantee, privilege_type), ',' ORDER BY table_name, grantee, privilege_type)) FROM information_schema.role_table_grants WHERE table_schema = 'public' AND table_name = 'channels') <> '6efe9c243a288c6fda5fe5b54d55faa4' THEN RAISE EXCEPTION 'D12-SW PRE: permisos de channels distintos'; END IF;
  IF (SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'channels' AND column_name = 'legacy_pin_enabled') <> 0 OR EXISTS (SELECT 1 FROM pg_proc WHERE proname IN ('f360_legacy_pin_set', 'f360_legacy_pin_status', 'legacy_pin_log_immutable', 'channels_legacy_pin_guard'))
     OR to_regclass('f360.legacy_pin_switch_log') IS NOT NULL OR EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version = '20261029000100')
    THEN RAISE EXCEPTION 'D12-SW PRE: el interruptor ya existe'; END IF;
END $$;
-- >>> cuerpo de la migración
-- D12 fase B (pieza §2 del plan v2) · interruptor por tienda de la pantalla de NIP anterior. STAGING (Mario 2026-10-13: "dale" → staging).
-- Una tienda ya migrada a cuentas F360 deja de aparecer en la pantalla de NIP de la app (vendedora/index.tsx filtra
-- legacy_pin_enabled = false). NO cambia ninguna política anon (el cierre del acceso anónimo es §5 y no está autorizado):
-- es la guía por tienda de la migración progresiva. Volver a encenderlo devuelve la app anterior a esa tienda el mismo día.
-- Solo la dueña lo cambia, con motivo, por RPC; cada cambio queda en un registro inmutable. Un disparador impide cambiarlo
-- por cualquier otra vía (incluida la política channels.admins_all_channels basada en user_metadata, hallazgo D12).
-- f360_legacy_pin_status() da, por tienda, el estado y las ventas por la app anterior de los últimos 14 días (criterio de cierre).

ALTER TABLE public.channels ADD COLUMN legacy_pin_enabled boolean NOT NULL DEFAULT true;
COMMENT ON COLUMN public.channels.legacy_pin_enabled IS
  'D12: false = la tienda ya vende con cuentas F360 y no aparece en la pantalla de NIP anterior. Solo se cambia con public.f360_legacy_pin_set.';

CREATE TABLE f360.legacy_pin_switch_log (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  channel_id  uuid NOT NULL REFERENCES public.channels(id) ON DELETE RESTRICT,
  enabled     boolean NOT NULL,
  reason      text NOT NULL CHECK (length(btrim(reason)) BETWEEN 3 AND 300),
  actor       uuid NOT NULL,
  actor_name  text NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE f360.legacy_pin_switch_log ENABLE ROW LEVEL SECURITY;   -- sin políticas: solo las RPC de abajo
REVOKE ALL ON f360.legacy_pin_switch_log FROM PUBLIC, anon, authenticated;

CREATE FUNCTION f360.legacy_pin_log_immutable() RETURNS trigger LANGUAGE plpgsql SET search_path = pg_catalog, pg_temp AS $$
BEGIN RAISE EXCEPTION 'El registro del interruptor de NIP no se modifica ni se borra.' USING ERRCODE = 'insufficient_privilege'; END $$;
CREATE TRIGGER legacy_pin_log_immutable BEFORE UPDATE OR DELETE OR TRUNCATE ON f360.legacy_pin_switch_log
  FOR EACH STATEMENT EXECUTE FUNCTION f360.legacy_pin_log_immutable();

-- the switch only moves through the RPC (transaction-local flag), never by a direct UPDATE on public.channels
CREATE FUNCTION f360.channels_legacy_pin_guard() RETURNS trigger LANGUAGE plpgsql SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  IF NEW.legacy_pin_enabled IS DISTINCT FROM OLD.legacy_pin_enabled AND current_setting('f360.legacy_pin_rpc', true) IS DISTINCT FROM 'on' THEN
    RAISE EXCEPTION 'El interruptor de NIP solo se cambia desde Fuxia 360 (f360_legacy_pin_set).' USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER channels_legacy_pin_guard BEFORE UPDATE OF legacy_pin_enabled ON public.channels
  FOR EACH ROW EXECUTE FUNCTION f360.channels_legacy_pin_guard();
REVOKE ALL ON FUNCTION f360.legacy_pin_log_immutable(), f360.channels_legacy_pin_guard() FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.f360_legacy_pin_set(p_channel uuid, p_enabled boolean, p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('owner'); ch public.channels;
BEGIN
  IF p_enabled IS NULL THEN RAISE EXCEPTION 'Indica si la pantalla de NIP queda encendida o apagada.'; END IF;
  IF p_reason IS NULL OR length(btrim(p_reason)) < 3 THEN RAISE EXCEPTION 'Escribe el motivo del cambio.'; END IF;
  SELECT * INTO ch FROM public.channels WHERE id = p_channel FOR UPDATE;
  IF ch.id IS NULL THEN RAISE EXCEPTION 'Tienda no encontrada.'; END IF;
  IF ch.legacy_pin_enabled = p_enabled THEN
    RETURN jsonb_build_object('ok', true, 'channel', ch.name, 'legacy_pin_enabled', p_enabled, 'changed', false);
  END IF;
  PERFORM set_config('f360.legacy_pin_rpc', 'on', true);
  UPDATE public.channels SET legacy_pin_enabled = p_enabled WHERE id = ch.id;
  PERFORM set_config('f360.legacy_pin_rpc', 'off', true);
  INSERT INTO f360.legacy_pin_switch_log (channel_id, enabled, reason, actor, actor_name)
    VALUES (ch.id, p_enabled, btrim(p_reason), r.auth_user_id, r.display_name);
  RETURN jsonb_build_object('ok', true, 'channel', ch.name, 'legacy_pin_enabled', p_enabled, 'changed', true);
END $$;

-- per store: switch state, legacy (non-RPC) sales in the last 14 days and the last one, last change. It never reads
-- public.staff (D12 P8: no client-callable definer function reads staff/pin).
CREATE FUNCTION public.f360_legacy_pin_status() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('operator');
BEGIN
  RETURN coalesce((SELECT jsonb_agg(jsonb_build_object(
      'channel_id', c.id, 'channel', c.name, 'type', c.type, 'active', c.active, 'legacy_pin_enabled', c.legacy_pin_enabled,
      'legacy_sales_14d', (SELECT count(*) FROM public.offline_sales o WHERE o.channel_id = c.id AND NOT o.created_by_rpc AND o.created_at > now() - interval '14 days'),
      'last_legacy_sale', (SELECT max(o.created_at) FROM public.offline_sales o WHERE o.channel_id = c.id AND NOT o.created_by_rpc),
      'last_change', (SELECT jsonb_build_object('enabled', l.enabled, 'reason', l.reason, 'by', l.actor_name, 'at', l.created_at)
                        FROM f360.legacy_pin_switch_log l WHERE l.channel_id = c.id ORDER BY l.id DESC LIMIT 1))
    ORDER BY c.name) FROM public.channels c), '[]'::jsonb);
END $$;

REVOKE ALL ON FUNCTION public.f360_legacy_pin_set(uuid, boolean, text), public.f360_legacy_pin_status() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_legacy_pin_set(uuid, boolean, text), public.f360_legacy_pin_status() TO authenticated, service_role;
-- <<< fin del cuerpo
INSERT INTO supabase_migrations.schema_migrations (version, name) VALUES ('20261029000100', 'd12_legacy_pin_switch');
DO $$ BEGIN
  IF (SELECT md5(string_agg(c::text, ',' ORDER BY id)) FROM (SELECT id, name, type, location, active FROM public.channels) c) <> '4f613a63cdefa76ff2f3c4c762e008fa' THEN RAISE EXCEPTION 'D12-SW POST: tiendas distintas a lo revisado'; END IF;
  IF (SELECT md5(string_agg(format('%s|%s|%s|%s|%s|%s', tablename, policyname, cmd, roles::text, coalesce(qual,''), coalesce(with_check,'')), E'\n' ORDER BY tablename, policyname)) || ' ' || count(*) FROM pg_policies WHERE schemaname = 'public' AND roles::text LIKE '%anon%') <> 'a8609ffb7700f84e1104acf7e2b76732 7' THEN RAISE EXCEPTION 'D12-SW POST: políticas anon distintas'; END IF;
  IF (SELECT md5(string_agg(format('%s|%s|%s|%s|%s|%s', tablename, policyname, cmd, roles::text, coalesce(qual,''), coalesce(with_check,'')), E'\n' ORDER BY tablename, policyname)) || ' ' || count(*) FROM pg_policies WHERE schemaname = 'public' AND tablename = 'channels') <> '383f6af1e1ef126ac0dd32df314ba34e 5' THEN RAISE EXCEPTION 'D12-SW POST: políticas de channels distintas'; END IF;
  IF (SELECT md5(string_agg(format('%s|%s|%s', table_name, grantee, privilege_type), ',' ORDER BY table_name, grantee, privilege_type)) FROM information_schema.role_table_grants WHERE table_schema = 'public' AND table_name = 'channels') <> '6efe9c243a288c6fda5fe5b54d55faa4' THEN RAISE EXCEPTION 'D12-SW POST: permisos de channels distintos'; END IF;
  IF (SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'channels' AND column_name = 'legacy_pin_enabled') <> 1 THEN RAISE EXCEPTION 'D12-SW POST: falta la columna'; END IF;
  IF EXISTS (SELECT 1 FROM public.channels WHERE legacy_pin_enabled IS DISTINCT FROM true) THEN RAISE EXCEPTION 'D12-SW POST: una tienda no quedó encendida'; END IF;
  IF (SELECT count(*) FROM public.channels) <> 5 OR (SELECT count(*) FROM public.channels WHERE active AND legacy_pin_enabled) <> 5 THEN RAISE EXCEPTION 'D12-SW POST: cambió el número de tiendas visibles'; END IF;
  IF (SELECT count(*) FROM f360.legacy_pin_switch_log) <> 0 THEN RAISE EXCEPTION 'D12-SW POST: registro no vacío'; END IF;
  -- permisos efectivos
  IF has_function_privilege('anon', 'public.f360_legacy_pin_set(uuid,boolean,text)', 'EXECUTE') OR has_function_privilege('anon', 'public.f360_legacy_pin_status()', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.f360_legacy_pin_set(uuid,boolean,text)', 'EXECUTE') OR NOT has_function_privilege('authenticated', 'public.f360_legacy_pin_status()', 'EXECUTE')
    THEN RAISE EXCEPTION 'D12-SW POST: permisos de las RPC'; END IF;
  IF has_function_privilege('anon', 'f360.channels_legacy_pin_guard()', 'EXECUTE') OR has_function_privilege('authenticated', 'f360.channels_legacy_pin_guard()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'f360.legacy_pin_log_immutable()', 'EXECUTE') THEN RAISE EXCEPTION 'D12-SW POST: permisos de los disparadores'; END IF;
  IF has_table_privilege('anon', 'f360.legacy_pin_switch_log', 'SELECT') OR has_table_privilege('authenticated', 'f360.legacy_pin_switch_log', 'SELECT')
     OR has_table_privilege('authenticated', 'f360.legacy_pin_switch_log', 'INSERT') THEN RAISE EXCEPTION 'D12-SW POST: el registro es accesible'; END IF;
  IF NOT (SELECT prosecdef FROM pg_proc WHERE oid = 'public.f360_legacy_pin_set(uuid,boolean,text)'::regprocedure) THEN RAISE EXCEPTION 'D12-SW POST: no es SECURITY DEFINER'; END IF;
END $$;
DO $$
DECLARE u_owner uuid; u_seller uuid; u_cli uuid; admin_phone text; ok boolean; j jsonb; who text; u uuid; n bigint;
BEGIN
  SELECT r.auth_user_id INTO u_owner FROM f360.user_roles r WHERE r.role = 'owner' LIMIT 1;
  SELECT r.auth_user_id INTO u_seller FROM f360.user_roles r WHERE r.role = 'seller' LIMIT 1;
  SELECT c.auth_user_id INTO u_cli FROM public.customers c WHERE c.role = 'customer' AND c.auth_user_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM f360.user_roles r WHERE r.auth_user_id = c.auth_user_id) LIMIT 1;
  SELECT c.phone INTO admin_phone FROM public.customers c WHERE c.role = 'admin' LIMIT 1;
  IF u_owner IS NULL OR u_seller IS NULL OR u_cli IS NULL OR admin_phone IS NULL THEN RAISE EXCEPTION 'D12-SW prueba: falta un perfil real'; END IF;

  -- T1 todas las tiendas encendidas; la pantalla de NIP (anon) ve las mismas 5 tiendas activas que antes
  IF EXISTS (SELECT 1 FROM public.channels WHERE legacy_pin_enabled IS DISTINCT FROM true) THEN RAISE EXCEPTION 'D12-SW T1 tienda apagada'; END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  SET LOCAL ROLE anon;
  IF (SELECT count(*) FROM public.channels WHERE active) <> 5 OR (SELECT count(*) FROM public.channels WHERE active AND legacy_pin_enabled IS DISTINCT FROM false) <> 5
    THEN RAISE EXCEPTION 'D12-SW T1 la pantalla de NIP no ve las 5 tiendas'; END IF;
  -- T2 anon no cambia el interruptor (ni RPC ni UPDATE) y no lee el estado
  ok := false; BEGIN PERFORM public.f360_legacy_pin_set((SELECT id FROM public.channels LIMIT 1), false, 'prueba anon'); EXCEPTION WHEN insufficient_privilege THEN ok := true; END;
  IF NOT ok THEN RAISE EXCEPTION 'D12-SW T2 anon RPC'; END IF;
  ok := false; BEGIN PERFORM public.f360_legacy_pin_status(); EXCEPTION WHEN insufficient_privilege THEN ok := true; END;
  IF NOT ok THEN RAISE EXCEPTION 'D12-SW T2 anon status'; END IF;
  UPDATE public.channels SET legacy_pin_enabled = false;   -- sin política UPDATE para anon: 0 filas
  RESET ROLE;
  IF EXISTS (SELECT 1 FROM public.channels WHERE NOT legacy_pin_enabled) THEN RAISE EXCEPTION 'D12-SW T2 anon UPDATE'; END IF;

  -- T3 vendedora y clienta: RPC rechazada; clienta con el teléfono de una admin en user_metadata (perfil editable):
  --    la política channels.admins_all_channels la dejaría escribir, pero el disparador lo impide
  FOREACH who IN ARRAY ARRAY['vendedora', 'clienta', 'clienta_falsificada'] LOOP
    u := CASE who WHEN 'vendedora' THEN u_seller ELSE u_cli END;
    PERFORM set_config('request.jwt.claims', CASE WHEN who = 'clienta_falsificada'
      THEN json_build_object('sub', u, 'role', 'authenticated', 'user_metadata', json_build_object('phone', admin_phone))::text
      ELSE json_build_object('sub', u, 'role', 'authenticated')::text END, true);
    ok := false;
    BEGIN SET LOCAL ROLE authenticated; PERFORM public.f360_legacy_pin_set((SELECT id FROM public.channels LIMIT 1), false, 'prueba'); RESET ROLE;
    EXCEPTION WHEN insufficient_privilege THEN RESET ROLE; ok := true; END;
    IF NOT ok THEN RAISE EXCEPTION 'D12-SW T3 % cambió por RPC', who; END IF;
    ok := false;
    BEGIN SET LOCAL ROLE authenticated; UPDATE public.channels SET legacy_pin_enabled = false; GET DIAGNOSTICS n = ROW_COUNT; RESET ROLE;
      ok := n = 0;   -- sin política de escritura: 0 filas
    EXCEPTION WHEN insufficient_privilege THEN RESET ROLE; ok := true; END;
    IF NOT ok OR EXISTS (SELECT 1 FROM public.channels WHERE NOT legacy_pin_enabled) THEN RAISE EXCEPTION 'D12-SW T3 % cambió por UPDATE', who; END IF;
    ok := false;
    BEGIN SET LOCAL ROLE authenticated; PERFORM public.f360_legacy_pin_status(); RESET ROLE; EXCEPTION WHEN insufficient_privilege THEN RESET ROLE; ok := true; END;
    IF NOT ok THEN RAISE EXCEPTION 'D12-SW T3 % lee el estado', who; END IF;
  END LOOP;

  -- T4 ni postgres cambia la columna fuera de la RPC
  ok := false; BEGIN UPDATE public.channels SET legacy_pin_enabled = false; EXCEPTION WHEN insufficient_privilege THEN ok := true; END;
  IF NOT ok THEN RAISE EXCEPTION 'D12-SW T4 cambio directo'; END IF;

  -- T5 la dueña lee el estado (solo lectura): 5 tiendas, todas encendidas, sin cambios registrados
  PERFORM set_config('request.jwt.claims', json_build_object('sub', u_owner, 'role', 'authenticated')::text, true);
  SET LOCAL ROLE authenticated; j := public.f360_legacy_pin_status(); RESET ROLE;
  IF jsonb_array_length(j) <> 5 OR EXISTS (SELECT 1 FROM jsonb_array_elements(j) e WHERE NOT (e->>'legacy_pin_enabled')::boolean OR e->'last_change' <> 'null'::jsonb)
    THEN RAISE EXCEPTION 'D12-SW T5 estado %', j; END IF;
  IF (SELECT count(*) FROM f360.legacy_pin_switch_log) <> 0 THEN RAISE EXCEPTION 'D12-SW T5 hubo cambios'; END IF;
END $$;
DO $$ BEGIN
  IF (SELECT md5(string_agg(c::text, ',' ORDER BY id)) FROM (SELECT id, name, type, location, active FROM public.channels) c) <> '4f613a63cdefa76ff2f3c4c762e008fa' THEN RAISE EXCEPTION 'D12-SW PRE-REV: tiendas distintas a lo revisado'; END IF;
  IF (SELECT md5(string_agg(format('%s|%s|%s|%s|%s|%s', tablename, policyname, cmd, roles::text, coalesce(qual,''), coalesce(with_check,'')), E'\n' ORDER BY tablename, policyname)) || ' ' || count(*) FROM pg_policies WHERE schemaname = 'public' AND roles::text LIKE '%anon%') <> 'a8609ffb7700f84e1104acf7e2b76732 7' THEN RAISE EXCEPTION 'D12-SW PRE-REV: políticas anon distintas'; END IF;
  IF (SELECT md5(string_agg(format('%s|%s|%s|%s|%s|%s', tablename, policyname, cmd, roles::text, coalesce(qual,''), coalesce(with_check,'')), E'\n' ORDER BY tablename, policyname)) || ' ' || count(*) FROM pg_policies WHERE schemaname = 'public' AND tablename = 'channels') <> '383f6af1e1ef126ac0dd32df314ba34e 5' THEN RAISE EXCEPTION 'D12-SW PRE-REV: políticas de channels distintas'; END IF;
  IF (SELECT md5(string_agg(format('%s|%s|%s', table_name, grantee, privilege_type), ',' ORDER BY table_name, grantee, privilege_type)) FROM information_schema.role_table_grants WHERE table_schema = 'public' AND table_name = 'channels') <> '6efe9c243a288c6fda5fe5b54d55faa4' THEN RAISE EXCEPTION 'D12-SW PRE-REV: permisos de channels distintos'; END IF;
  IF (SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'channels' AND column_name = 'legacy_pin_enabled') <> 1 THEN RAISE EXCEPTION 'D12-SW PRE-REV: no está aplicada'; END IF;
  IF EXISTS (SELECT 1 FROM public.channels WHERE NOT legacy_pin_enabled) THEN RAISE EXCEPTION 'D12-SW PRE-REV: hay tiendas apagadas; enciéndelas con f360_legacy_pin_set antes de revertir'; END IF;
  IF (SELECT count(*) FROM f360.legacy_pin_switch_log) > 0 THEN RAISE EXCEPTION 'D12-SW PRE-REV: el registro tiene cambios; respáldalo antes de revertir (se perdería la auditoría)'; END IF;
END $$;
-- >>> cuerpo de la reversión
-- Rollback of 20261029000100_d12_legacy_pin_switch. The app keeps working without the column (it reads channels with * and
-- treats a missing legacy_pin_enabled as "encendido"), so every store is back on the legacy PIN screen.
DROP FUNCTION public.f360_legacy_pin_status();
DROP FUNCTION public.f360_legacy_pin_set(uuid, boolean, text);
DROP TRIGGER channels_legacy_pin_guard ON public.channels;
DROP FUNCTION f360.channels_legacy_pin_guard();
DROP TABLE f360.legacy_pin_switch_log;   -- its statement trigger goes with it
DROP FUNCTION f360.legacy_pin_log_immutable();
ALTER TABLE public.channels DROP COLUMN legacy_pin_enabled;
-- <<< fin del cuerpo
DELETE FROM supabase_migrations.schema_migrations WHERE version = '20261029000100';
DO $$ BEGIN
  IF (SELECT md5(string_agg(c::text, ',' ORDER BY id)) FROM (SELECT id, name, type, location, active FROM public.channels) c) <> '4f613a63cdefa76ff2f3c4c762e008fa' THEN RAISE EXCEPTION 'D12-SW POST-REV: tiendas distintas a lo revisado'; END IF;
  IF (SELECT md5(string_agg(format('%s|%s|%s|%s|%s|%s', tablename, policyname, cmd, roles::text, coalesce(qual,''), coalesce(with_check,'')), E'\n' ORDER BY tablename, policyname)) || ' ' || count(*) FROM pg_policies WHERE schemaname = 'public' AND roles::text LIKE '%anon%') <> 'a8609ffb7700f84e1104acf7e2b76732 7' THEN RAISE EXCEPTION 'D12-SW POST-REV: políticas anon distintas'; END IF;
  IF (SELECT md5(string_agg(format('%s|%s|%s|%s|%s|%s', tablename, policyname, cmd, roles::text, coalesce(qual,''), coalesce(with_check,'')), E'\n' ORDER BY tablename, policyname)) || ' ' || count(*) FROM pg_policies WHERE schemaname = 'public' AND tablename = 'channels') <> '383f6af1e1ef126ac0dd32df314ba34e 5' THEN RAISE EXCEPTION 'D12-SW POST-REV: políticas de channels distintas'; END IF;
  IF (SELECT md5(string_agg(format('%s|%s|%s', table_name, grantee, privilege_type), ',' ORDER BY table_name, grantee, privilege_type)) FROM information_schema.role_table_grants WHERE table_schema = 'public' AND table_name = 'channels') <> '6efe9c243a288c6fda5fe5b54d55faa4' THEN RAISE EXCEPTION 'D12-SW POST-REV: permisos de channels distintos'; END IF;
  IF (SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'channels' AND column_name = 'legacy_pin_enabled') <> 0 OR EXISTS (SELECT 1 FROM pg_proc WHERE proname IN ('f360_legacy_pin_set', 'f360_legacy_pin_status', 'legacy_pin_log_immutable', 'channels_legacy_pin_guard'))
     OR to_regclass('f360.legacy_pin_switch_log') IS NOT NULL OR EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version = '20261029000100')
    THEN RAISE EXCEPTION 'D12-SW POST-REV: quedaron restos'; END IF;
END $$;
COMMIT;
