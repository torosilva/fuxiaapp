-- Rollback of 20261007000700_f360_d3_opening_count.sql. Refuses while a count is frozen/approved (it holds a location).
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM f360.opening_counts WHERE status IN ('congelado', 'aprobado')) THEN
    RAISE EXCEPTION 'Hay un conteo congelado o aprobado: cancélalo antes de revertir.';
  END IF;
END $$;
CREATE OR REPLACE FUNCTION f360.location_in_cutover(p_location uuid) RETURNS boolean LANGUAGE sql STABLE AS
$$ SELECT EXISTS (SELECT 1 FROM f360.location_cutovers WHERE location_id = p_location AND status IN ('preparing', 'counting', 'verification', 'ready')) $$;
DROP FUNCTION IF EXISTS public.f360_opening_set_woo_reference(uuid, jsonb);
DROP FUNCTION IF EXISTS public.f360_opening_cancel(uuid, text);
DROP FUNCTION IF EXISTS public.f360_opening_approve(uuid, text);
DROP FUNCTION IF EXISTS public.f360_opening_reconcile(uuid);
DROP FUNCTION IF EXISTS public.f360_opening_freeze(uuid);
DROP FUNCTION IF EXISTS public.f360_opening_resolve_unlisted(uuid, text);
DROP FUNCTION IF EXISTS public.f360_opening_add_unlisted(uuid, text, text, int);
DROP FUNCTION IF EXISTS public.f360_opening_record(uuid, text, jsonb);
DROP FUNCTION IF EXISTS public.f360_opening_sheet(uuid, text);
DROP FUNCTION IF EXISTS public.f360_opening_state(uuid);
DROP FUNCTION IF EXISTS public.f360_opening_refresh_scope(uuid);
DROP FUNCTION IF EXISTS public.f360_opening_start(text, text);
DROP FUNCTION IF EXISTS f360.opening_blockers(uuid);
DROP FUNCTION IF EXISTS f360.opening_summary(uuid);
DROP FUNCTION IF EXISTS f360.opening_sync_scope(uuid);
DROP FUNCTION IF EXISTS f360.opening_log(uuid, text, jsonb, f360.user_roles);
DROP TABLE IF EXISTS f360.opening_count_changes;
DROP TABLE IF EXISTS f360.opening_count_unlisted;
DROP TABLE IF EXISTS f360.opening_count_lines;
DROP TABLE IF EXISTS f360.opening_counts;
DROP FUNCTION IF EXISTS f360.opening_changes_append_only();
