-- D12 fase B (pieza §2 del plan v2) · interruptor por tienda de la pantalla de NIP anterior. STAGING (Mario 2026-10-13: "dale" → staging).
-- Una tienda ya migrada a cuentas F360 deja de aparecer en la pantalla de NIP de la app (vendedora/index.tsx filtra
-- legacy_pin_enabled = false). NO cambia ninguna política anon (el cierre del acceso anónimo es §5 y no está autorizado):
-- es la guía por tienda de la migración progresiva. Volver a encenderlo devuelve la app anterior a esa tienda el mismo día.
-- Solo la dueña lo cambia, con motivo, por RPC; cada cambio queda en un registro inmutable. Un disparador impide cambiarlo
-- por cualquier otra vía (incluida la política channels.admins_all_channels basada en user_metadata, hallazgo D12).
-- f360_legacy_pin_status() da, por tienda, el estado y las ventas por la app anterior de los últimos 14 días (criterio de cierre).
-- Rollback: supabase/rollbacks/20261029000100_d12_legacy_pin_switch.down.sql

ALTER TABLE public.channels ADD COLUMN legacy_pin_enabled boolean NOT NULL DEFAULT true;
COMMENT ON COLUMN public.channels.legacy_pin_enabled IS
  'D12: false = la tienda ya vende con cuentas F360 y no aparece en la pantalla de NIP anterior. Solo se cambia con public.f360_legacy_pin_set.';

CREATE TABLE f360.legacy_pin_switch_log (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  channel_id  uuid NOT NULL REFERENCES public.channels(id) ON DELETE RESTRICT,
  enabled     boolean NOT NULL,
  reason      text NOT NULL CHECK (length(btrim(reason)) BETWEEN 3 AND 300),
  actor       uuid NOT NULL,
  actor_name  text NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE f360.legacy_pin_switch_log ENABLE ROW LEVEL SECURITY;   -- sin políticas: solo las RPC de abajo
REVOKE ALL ON f360.legacy_pin_switch_log FROM PUBLIC, anon, authenticated;

CREATE FUNCTION f360.legacy_pin_log_immutable() RETURNS trigger LANGUAGE plpgsql SET search_path = pg_catalog, pg_temp AS $$
BEGIN RAISE EXCEPTION 'El registro del interruptor de NIP no se modifica ni se borra.' USING ERRCODE = 'insufficient_privilege'; END $$;
CREATE TRIGGER legacy_pin_log_immutable BEFORE UPDATE OR DELETE OR TRUNCATE ON f360.legacy_pin_switch_log
  FOR EACH STATEMENT EXECUTE FUNCTION f360.legacy_pin_log_immutable();

-- the switch only moves through the RPC (transaction-local flag), never by a direct UPDATE on public.channels
CREATE FUNCTION f360.channels_legacy_pin_guard() RETURNS trigger LANGUAGE plpgsql SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  IF NEW.legacy_pin_enabled IS DISTINCT FROM OLD.legacy_pin_enabled AND current_setting('f360.legacy_pin_rpc', true) IS DISTINCT FROM 'on' THEN
    RAISE EXCEPTION 'El interruptor de NIP solo se cambia desde Fuxia 360 (f360_legacy_pin_set).' USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER channels_legacy_pin_guard BEFORE UPDATE OF legacy_pin_enabled ON public.channels
  FOR EACH ROW EXECUTE FUNCTION f360.channels_legacy_pin_guard();
REVOKE ALL ON FUNCTION f360.legacy_pin_log_immutable(), f360.channels_legacy_pin_guard() FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.f360_legacy_pin_set(p_channel uuid, p_enabled boolean, p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('owner'); ch public.channels;
BEGIN
  IF p_enabled IS NULL THEN RAISE EXCEPTION 'Indica si la pantalla de NIP queda encendida o apagada.'; END IF;
  IF p_reason IS NULL OR length(btrim(p_reason)) < 3 THEN RAISE EXCEPTION 'Escribe el motivo del cambio.'; END IF;
  SELECT * INTO ch FROM public.channels WHERE id = p_channel FOR UPDATE;
  IF ch.id IS NULL THEN RAISE EXCEPTION 'Tienda no encontrada.'; END IF;
  IF ch.legacy_pin_enabled = p_enabled THEN
    RETURN jsonb_build_object('ok', true, 'channel', ch.name, 'legacy_pin_enabled', p_enabled, 'changed', false);
  END IF;
  PERFORM set_config('f360.legacy_pin_rpc', 'on', true);
  UPDATE public.channels SET legacy_pin_enabled = p_enabled WHERE id = ch.id;
  PERFORM set_config('f360.legacy_pin_rpc', 'off', true);
  INSERT INTO f360.legacy_pin_switch_log (channel_id, enabled, reason, actor, actor_name)
    VALUES (ch.id, p_enabled, btrim(p_reason), r.auth_user_id, r.display_name);
  RETURN jsonb_build_object('ok', true, 'channel', ch.name, 'legacy_pin_enabled', p_enabled, 'changed', true);
END $$;

-- per store: switch state, legacy (non-RPC) sales in the last 14 days and the last one, last change. It never reads
-- public.staff (D12 P8: no client-callable definer function reads staff/pin).
CREATE FUNCTION public.f360_legacy_pin_status() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('operator');
BEGIN
  RETURN coalesce((SELECT jsonb_agg(jsonb_build_object(
      'channel_id', c.id, 'channel', c.name, 'type', c.type, 'active', c.active, 'legacy_pin_enabled', c.legacy_pin_enabled,
      'legacy_sales_14d', (SELECT count(*) FROM public.offline_sales o WHERE o.channel_id = c.id AND NOT o.created_by_rpc AND o.created_at > now() - interval '14 days'),
      'last_legacy_sale', (SELECT max(o.created_at) FROM public.offline_sales o WHERE o.channel_id = c.id AND NOT o.created_by_rpc),
      'last_change', (SELECT jsonb_build_object('enabled', l.enabled, 'reason', l.reason, 'by', l.actor_name, 'at', l.created_at)
                        FROM f360.legacy_pin_switch_log l WHERE l.channel_id = c.id ORDER BY l.id DESC LIMIT 1))
    ORDER BY c.name) FROM public.channels c), '[]'::jsonb);
END $$;

REVOKE ALL ON FUNCTION public.f360_legacy_pin_set(uuid, boolean, text), public.f360_legacy_pin_status() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_legacy_pin_set(uuid, boolean, text), public.f360_legacy_pin_status() TO authenticated, service_role;
