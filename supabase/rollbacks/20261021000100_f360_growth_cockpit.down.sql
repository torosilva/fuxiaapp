-- Rollback of 20261021000100_f360_growth_cockpit.sql (read-only functions; nothing depends on them).
DROP FUNCTION IF EXISTS public.f360_growth_cockpit(date, date);
DROP FUNCTION IF EXISTS f360.growth_market_block(text, timestamptz, timestamptz, timestamptz, timestamptz);
DROP FUNCTION IF EXISTS f360.classify_channel_v1(text, text, text, text);
