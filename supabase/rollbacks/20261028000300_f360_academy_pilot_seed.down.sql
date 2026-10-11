-- Rollback of 20261028000300 (pilot seed). Only possible while version 1 is still a DRAFT nobody studied: once submitted/published,
-- content and its approval history are kept (revert 20261028000200 instead, with Mario's OK).
BEGIN;
DO $$
DECLARE c uuid := (SELECT id FROM f360_academy.courses WHERE key = 'starter-ballerinas-parte-1');
BEGIN
  IF c IS NULL THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM f360_academy.course_versions WHERE course_id = c AND status <> 'borrador')
     OR EXISTS (SELECT 1 FROM f360_academy.enrollments WHERE course_id = c) THEN
    RAISE EXCEPTION 'ABORT: el curso piloto ya se envió, publicó o alguien lo estudió';
  END IF;
  DELETE FROM f360_academy.items WHERE course_version_id IN (SELECT id FROM f360_academy.course_versions WHERE course_id = c);
  DELETE FROM f360_academy.lessons WHERE course_version_id IN (SELECT id FROM f360_academy.course_versions WHERE course_id = c);
  ALTER TABLE f360_academy.course_versions DISABLE TRIGGER course_versions_guard;
  DELETE FROM f360_academy.course_versions WHERE course_id = c;
  ALTER TABLE f360_academy.course_versions ENABLE TRIGGER course_versions_guard;
  DELETE FROM f360_academy.courses WHERE id = c;
END $$;
COMMIT;
