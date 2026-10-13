-- Fuxia Academy · PRODUCCIÓN · REVERSIÓN (DESMONTA: borra contenido, avance e historial de práctica de Academy). Solo con OK expreso de Mario.
-- Cuerpos = supabase/rollbacks/20261030000400, permisos, 0200 (incluye 0300) y 0100, sin sus BEGIN/COMMIT.
BEGIN;
DO $$ BEGIN IF to_regnamespace('f360_academy') IS NULL THEN RAISE EXCEPTION 'ACADEMY-REV PRE: Academy no existe'; END IF; END $$;
-- Rollback of 20261030000400: vuelve a bloquear a las vendedoras reales (los testers siguen entrando).
UPDATE f360_academy.settings
   SET learner_access_enabled = false,
       note = 'A1: acceso real de vendedoras bloqueado mientras P0-6 siga abierto (Mario 2026-10-11).'
 WHERE id;
ALTER TABLE f360_academy.settings ADD CONSTRAINT a1_no_real_learners CHECK (NOT learner_access_enabled);
DELETE FROM f360.approval_scope_operations WHERE scope = 'academy_content';
DELETE FROM f360.approval_scopes WHERE scope = 'academy_content';
-- Rollback of 20261030000200_f360_academy_a1 (and of 20261030000300, whose rows live in this schema).
-- Run ONLY with Mario's explicit OK: after apply it is a TEARDOWN (drops content, progress and practice history).
-- The shared approval registry keeps its academy requests/events (append-only history); revert 20261030000100 separately.
DROP FUNCTION public.f360_academy_team();
DROP FUNCTION public.f360_academy_decide(uuid, boolean, text);
DROP FUNCTION public.f360_academy_submit(uuid, text);
DROP FUNCTION public.f360_academy_new_draft(uuid);
DROP FUNCTION public.f360_academy_comment(uuid, text, text, int, text);
DROP FUNCTION public.f360_academy_item_save(uuid, jsonb);
DROP FUNCTION public.f360_academy_lesson_save(uuid, text, int, jsonb, text[]);
DROP FUNCTION public.f360_academy_admin_version(uuid);
DROP FUNCTION public.f360_academy_admin_overview();
DROP FUNCTION public.f360_academy_fichas();
DROP FUNCTION public.f360_academy_answer(uuid, jsonb);
DROP FUNCTION public.f360_academy_progress_save(uuid, int, boolean);
DROP FUNCTION public.f360_academy_lesson(uuid);
DROP FUNCTION public.f360_academy_home();
DROP FUNCTION public.f360_academy_me();
DROP SCHEMA f360_academy CASCADE;
-- Rollback of 20261030000100_f360_approval_registry. Run ONLY with Mario's explicit OK (after apply it is a teardown).
-- Refuses if: Academy (20261030000200) is still installed; any request exists for a non-academy scope (another module adopted the
-- registry); academy scopes still have people assigned. It never removes scopes other migrations may have added after this one:
-- the CHECK is rebuilt from the live definition minus the three academy scopes.
DO $$
DECLARE def text; vals text[];
BEGIN
  IF to_regnamespace('f360_academy') IS NOT NULL THEN RAISE EXCEPTION 'ABORT: primero revierta 20261030000200 (f360_academy)'; END IF;
  IF EXISTS (SELECT 1 FROM f360.approval_requests WHERE scope NOT LIKE 'academy\_%') THEN
    RAISE EXCEPTION 'ABORT: otro módulo ya usa el registro de aprobaciones';
  END IF;
  IF EXISTS (SELECT 1 FROM f360.approval_scopes WHERE scope LIKE 'academy\_%') THEN
    RAISE EXCEPTION 'ABORT: quite primero a las personas de los alcances academy_* (revisado por Mario)';
  END IF;
  SELECT pg_get_constraintdef(c.oid) INTO def FROM pg_constraint c
   WHERE c.conrelid = 'f360.approval_scopes'::regclass AND c.conname = 'approval_scopes_scope_check';
  SELECT array_agg(t.m[1] ORDER BY t.o) INTO vals FROM regexp_matches(def, '''([a-z_]+)''', 'g') WITH ORDINALITY AS t(m, o) WHERE t.m[1] NOT LIKE 'academy\_%';   -- keeps the live order
  EXECUTE 'ALTER TABLE f360.approval_scopes DROP CONSTRAINT approval_scopes_scope_check';
  EXECUTE format('ALTER TABLE f360.approval_scopes ADD CONSTRAINT approval_scopes_scope_check CHECK (scope IN (%s))',
    (SELECT string_agg(quote_literal(v), ', ') FROM unnest(vals) v));
END $$;
DROP FUNCTION f360.approval_cancel(uuid, uuid, text, text);
DROP FUNCTION f360.approval_consume(uuid, text, text, text, uuid, int, text, uuid, text);
DROP FUNCTION f360.approval_decide(uuid, boolean, text, uuid, text, text);
DROP FUNCTION f360.approval_request(text, text, text, uuid, int, text, uuid, jsonb, text, uuid, text);
DROP FUNCTION f360.approval_event(uuid, text, uuid, text, text, text, boolean);
DROP TABLE f360.approval_events;
DROP TABLE f360.approval_requests;
DROP FUNCTION f360.approval_requests_guard();
DROP FUNCTION f360.can_approve_op(text, text, uuid);
DROP TABLE f360.approval_scope_operations;
DROP TABLE f360.approval_operations;
DELETE FROM supabase_migrations.schema_migrations WHERE version LIKE '20261030%';
DO $$ BEGIN IF to_regnamespace('f360_academy') IS NOT NULL OR to_regclass('f360.approval_requests') IS NOT NULL THEN RAISE EXCEPTION 'ACADEMY-REV POST: quedó algo'; END IF;
  IF (SELECT md5(pg_get_functiondef('f360.can_approve(text,uuid)'::regprocedure))) <> '565a9163f96b40b17895b2cbdd1b1729' THEN RAISE EXCEPTION 'ACADEMY-REV POST: can_approve distinta'; END IF; END $$;
COMMIT;
