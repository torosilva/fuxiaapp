-- Rollback of 20261010000900_f360_opening_undo.sql.
-- Entries already 'quitado' become 'resuelto' (same note), so they stay out of the open list and the log keeps them.
-- Sizes already cleared stay 'pendiente' (they simply need to be counted again).
DROP FUNCTION public.f360_opening_unlisted_open(uuid);
DROP FUNCTION public.f360_opening_remove_unlisted(uuid);
DROP FUNCTION public.f360_opening_clear_line(uuid, uuid);
UPDATE f360.opening_count_unlisted SET status = 'resuelto' WHERE status = 'quitado';
ALTER TABLE f360.opening_count_unlisted DROP CONSTRAINT opening_count_unlisted_status_check;
ALTER TABLE f360.opening_count_unlisted ADD CONSTRAINT opening_count_unlisted_status_check CHECK (status IN ('abierto', 'resuelto'));
