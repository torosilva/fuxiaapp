-- Rollback of 20261030000100_f360_approval_registry. Run ONLY with Mario's explicit OK (after apply it is a teardown).
-- Refuses if: Academy (20261030000200) is still installed; any request exists for a non-academy scope (another module adopted the
-- registry); academy scopes still have people assigned. It never removes scopes other migrations may have added after this one:
-- the CHECK is rebuilt from the live definition minus the three academy scopes.
BEGIN;
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
COMMIT;
