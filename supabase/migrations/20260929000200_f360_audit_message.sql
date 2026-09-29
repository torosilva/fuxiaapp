-- Fuxia 360 — generic append-only message. f360.reject_audit_change() is now used by publication, webhook,
-- stock-sync, reconciliation and planning audit tables; its message said "historial de publicación" for all of them.
-- Behavior unchanged (still raises). Rollback: re-apply the definition from 20260927010000.
CREATE OR REPLACE FUNCTION f360.reject_audit_change() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'Este historial no se puede modificar (%.%)', TG_TABLE_SCHEMA, TG_TABLE_NAME;
END $$;
REVOKE ALL ON FUNCTION f360.reject_audit_change() FROM PUBLIC, anon, authenticated;
