-- Rollback of 20261019000300_f360_weekly_board.sql (export f360.weekly_cards / weekly_metrics / weekly_changes first: they hold the team's notes).
DROP FUNCTION IF EXISTS public.f360_weekly_person_set(text, text, text), public.f360_weekly_metrics_save(text, jsonb, text), public.f360_weekly_card_save(text, text, text, jsonb, text), public.f360_weekly_board(text), public.f360_weekly_me(), f360.weekly_online_pairs(date, date), f360.weekly_actor();
DROP TABLE IF EXISTS f360.weekly_changes, f360.weekly_metrics, f360.weekly_cards, f360.weekly_plan, f360.weekly_people;
