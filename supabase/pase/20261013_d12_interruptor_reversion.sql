-- D12 interruptor · PRODUCCIÓN · REVERSIÓN exacta. Cuerpo = supabase/rollbacks/20261029000100_d12_legacy_pin_switch.down.sql (sha256 c51bd9b356b45e16…). Se niega si hay tiendas apagadas o registro con cambios.
BEGIN;
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
