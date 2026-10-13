-- Rollback of 20261029000100_d12_legacy_pin_switch. The app keeps working without the column (it reads channels with * and
-- treats a missing legacy_pin_enabled as "encendido"), so every store is back on the legacy PIN screen.
DROP FUNCTION public.f360_legacy_pin_status();
DROP FUNCTION public.f360_legacy_pin_set(uuid, boolean, text);
DROP TRIGGER channels_legacy_pin_guard ON public.channels;
DROP FUNCTION f360.channels_legacy_pin_guard();
DROP TABLE f360.legacy_pin_switch_log;   -- its statement trigger goes with it
DROP FUNCTION f360.legacy_pin_log_immutable();
ALTER TABLE public.channels DROP COLUMN legacy_pin_enabled;
