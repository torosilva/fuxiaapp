-- Rollback of 20261015000100_f360_board_sb0_access.sql (roll back 20261015000300 and 20261015000200 first).
-- Removes the Strategy & Board module entirely: schema f360_board (members, access log, settings) + public.f360_board_*.
-- Nothing in f360/public data is touched. WARNING: the access log is audit evidence — export it before dropping
-- (SELECT * FROM f360_board.access_log) and keep the export with the pase record.
DROP FUNCTION IF EXISTS public.f360_board_access_log(int);
DROP FUNCTION IF EXISTS public.f360_board_nav_visible();
DROP FUNCTION IF EXISTS public.f360_board_me();
DROP SCHEMA IF EXISTS f360_board CASCADE;
DELETE FROM supabase_migrations.schema_migrations WHERE version = '20261015000100';
