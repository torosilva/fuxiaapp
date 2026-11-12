-- Fuxia 360 · Fase 1 · Usuarios y roles (Mario 2026-11-12, diseño "Fuxia 360 · Diseño: usuarios, Fuxia Skills, inicio y bitácora").
-- ADDITIVE. One screen (Configuración → Usuarios) for Dirección to see who can do what and to change profiles.
--   · Profiles are a view over what already exists: Dirección = owner, Operación = operator, Vendedora = seller,
--     Marketing / Agencia / Solo lectura = viewer + module access (new table f360.user_module_access).
--   · Reuses public.f360_set_user_role (owner-only, never leaves the system without an owner, logs to f360.access_changes).
--   · Customer personal data (f360.customer_pii_viewers), Strategy & Board (f360_board.board_members) and approval scopes
--     (f360.approval_scopes) stay changeable ONLY by a reviewed pass, as designed. This migration only READS them.
--     Mario 2026-11-12: personal data stays with Carolina and Mario only.
--   · Every change asks for a reason and is written to f360.access_changes (append-only).
-- Rollback: supabase/rollbacks/20261112000100_f360_user_admin.down.sql

CREATE TABLE f360.user_module_access (
  auth_user_id     uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  module           text NOT NULL CHECK (module IN ('growth', 'marketing', 'tareas', 'skills')),
  granted_by_name  text NOT NULL,
  granted_at       timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (auth_user_id, module)
);
COMMENT ON TABLE f360.user_module_access IS 'Module access for viewer-level staff (Marketing, Agencia). Owner/operator see every module through their role. Changed only via f360_admin_* (owner, with reason, logged).';
ALTER TABLE f360.user_module_access ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON f360.user_module_access FROM PUBLIC, anon, authenticated;
GRANT ALL ON f360.user_module_access TO service_role;

-- Profile shown on screen, derived (never stored twice).
CREATE FUNCTION f360.user_profile(p_role text, p_modules text[]) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_role
    WHEN 'owner' THEN 'direccion' WHEN 'operator' THEN 'operacion' WHEN 'seller' THEN 'vendedora'
    ELSE CASE WHEN 'marketing' = ANY(coalesce(p_modules, '{}')) THEN 'marketing'
              WHEN cardinality(coalesce(p_modules, '{}')) > 0 THEN 'agencia' ELSE 'lectura' END END $$;

CREATE FUNCTION f360.user_modules(p_user uuid) RETURNS text[] LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT coalesce(array_agg(module ORDER BY module), '{}') FROM f360.user_module_access WHERE auth_user_id = p_user $$;

CREATE FUNCTION f360.require_reason(p_reason text) RETURNS text LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
  IF length(btrim(coalesce(p_reason, ''))) < 5 THEN RAISE EXCEPTION 'Escribe el motivo del cambio.'; END IF;
  IF length(p_reason) > 300 THEN RAISE EXCEPTION 'El motivo es demasiado largo (máximo 300 caracteres).'; END IF;
  RETURN btrim(p_reason);
END $$;

-- People who hold a sensitive permission that only a reviewed pass may change.
CREATE FUNCTION f360.user_sensitive(p_user uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE pii boolean; board boolean := false; scopes text[];
BEGIN
  pii := EXISTS (SELECT 1 FROM f360.customer_pii_viewers WHERE auth_user_id = p_user);
  IF to_regclass('f360_board.board_members') IS NOT NULL THEN
    EXECUTE 'SELECT EXISTS (SELECT 1 FROM f360_board.board_members WHERE auth_user_id = $1 AND active)' INTO board USING p_user;
  END IF;
  SELECT coalesce(array_agg(scope ORDER BY scope), '{}') INTO scopes FROM f360.approval_scopes WHERE auth_user_id = p_user;
  RETURN jsonb_build_object('pii', pii, 'board', board, 'scopes', to_jsonb(scopes));
END $$;

-- Configuración → Usuarios: everyone with a Fuxia 360 role, plus signed-in accounts that have none yet (to add them).
CREATE FUNCTION public.f360_admin_users() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  PERFORM f360.require_role('owner');
  RETURN jsonb_build_object(
    'users', (SELECT coalesce(jsonb_agg(jsonb_build_object(
        'auth_user_id', u.auth_user_id, 'display_name', u.display_name, 'role', u.role,
        'email', au.email,
        'modules', to_jsonb(f360.user_modules(u.auth_user_id)),
        'profile', f360.user_profile(u.role, f360.user_modules(u.auth_user_id)),
        'locations', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'name', l.name) ORDER BY l.name), '[]')
                      FROM f360.location_assignments a JOIN f360.locations l ON l.id = a.location_id
                      WHERE a.auth_user_id = u.auth_user_id AND a.active),
        'sensitive', f360.user_sensitive(u.auth_user_id),
        'me', u.auth_user_id = auth.uid())
      ORDER BY f360.role_rank(u.role) DESC, u.display_name), '[]')
      FROM f360.user_roles u LEFT JOIN auth.users au ON au.id = u.auth_user_id),
    'without_role', (SELECT coalesce(jsonb_agg(jsonb_build_object('auth_user_id', au.id, 'email', au.email, 'created_at', au.created_at)
        ORDER BY au.created_at DESC), '[]')
      FROM auth.users au
      WHERE au.email IS NOT NULL AND NOT EXISTS (SELECT 1 FROM f360.user_roles r WHERE r.auth_user_id = au.id)
        AND au.last_sign_in_at IS NOT NULL),
    'changes', (SELECT coalesce(jsonb_agg(x ORDER BY x->>'at' DESC), '[]') FROM (
        SELECT jsonb_build_object('at', c.at, 'what', c.what, 'subject', c.subject, 'by_name', c.by_name,
               'reason', c.after->>'reason', 'profile', c.after->>'profile', 'module', c.after->>'module', 'on', c.after->'on') x
        FROM f360.access_changes c WHERE c.what IN ('role', 'profile', 'module', 'removed') ORDER BY c.at DESC LIMIT 50) t));
END $$;

-- Set a person's profile (role + module preset) in one step.
CREATE FUNCTION public.f360_admin_set_profile(p_auth_user_id uuid, p_profile text, p_display_name text, p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; reason text := f360.require_reason(p_reason); new_role text; preset text[]; before jsonb; m text;
BEGIN
  r := f360.require_role('owner');
  new_role := CASE p_profile WHEN 'direccion' THEN 'owner' WHEN 'operacion' THEN 'operator' WHEN 'vendedora' THEN 'seller'
                             WHEN 'marketing' THEN 'viewer' WHEN 'agencia' THEN 'viewer' WHEN 'lectura' THEN 'viewer' END;
  IF new_role IS NULL THEN RAISE EXCEPTION 'Perfil no válido.'; END IF;
  IF p_auth_user_id = r.auth_user_id AND new_role <> 'owner' THEN
    RAISE EXCEPTION 'No puedes quitarte a ti misma el perfil de Dirección; pídeselo a otra persona de Dirección.';
  END IF;
  preset := CASE p_profile WHEN 'marketing' THEN ARRAY['growth', 'marketing', 'skills', 'tareas']
                           WHEN 'agencia' THEN ARRAY['growth', 'tareas'] ELSE ARRAY[]::text[] END;
  SELECT jsonb_build_object('role', u.role, 'display_name', u.display_name, 'modules', to_jsonb(f360.user_modules(u.auth_user_id)))
    INTO before FROM f360.user_roles u WHERE u.auth_user_id = p_auth_user_id;
  PERFORM public.f360_set_user_role(p_auth_user_id, new_role, p_display_name);  -- owner check, last-owner rule, role log
  DELETE FROM f360.user_module_access WHERE auth_user_id = p_auth_user_id AND NOT (module = ANY(preset));
  FOREACH m IN ARRAY preset LOOP
    INSERT INTO f360.user_module_access (auth_user_id, module, granted_by_name) VALUES (p_auth_user_id, m, r.display_name)
      ON CONFLICT (auth_user_id, module) DO NOTHING;
  END LOOP;
  INSERT INTO f360.access_changes (what, subject, before, after, by_name, by_user)
  VALUES ('profile', p_auth_user_id::text, before,
          jsonb_build_object('profile', p_profile, 'role', new_role, 'modules', to_jsonb(preset), 'reason', reason), r.display_name, r.auth_user_id);
  RETURN jsonb_build_object('ok', true, 'profile', p_profile, 'role', new_role, 'modules', to_jsonb(preset));
END $$;

-- Turn one module on or off for a viewer-level person (Marketing / Agencia / Solo lectura).
CREATE FUNCTION public.f360_admin_set_module(p_auth_user_id uuid, p_module text, p_on boolean, p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; reason text := f360.require_reason(p_reason); target f360.user_roles; before text[];
BEGIN
  r := f360.require_role('owner');
  IF p_module NOT IN ('growth', 'marketing', 'tareas', 'skills') THEN RAISE EXCEPTION 'Módulo no válido.'; END IF;
  SELECT * INTO target FROM f360.user_roles WHERE auth_user_id = p_auth_user_id;
  IF target.auth_user_id IS NULL THEN RAISE EXCEPTION 'Esa persona no tiene acceso a Fuxia 360.'; END IF;
  IF target.role <> 'viewer' THEN RAISE EXCEPTION 'Este perfil ya incluye sus pantallas; los módulos se dan a Marketing, Agencia o Solo lectura.'; END IF;
  before := f360.user_modules(p_auth_user_id);
  IF p_on THEN
    INSERT INTO f360.user_module_access (auth_user_id, module, granted_by_name) VALUES (p_auth_user_id, p_module, r.display_name)
      ON CONFLICT (auth_user_id, module) DO NOTHING;
  ELSE
    DELETE FROM f360.user_module_access WHERE auth_user_id = p_auth_user_id AND module = p_module;
  END IF;
  INSERT INTO f360.access_changes (what, subject, before, after, by_name, by_user)
  VALUES ('module', p_auth_user_id::text, jsonb_build_object('modules', to_jsonb(before)),
          jsonb_build_object('module', p_module, 'on', p_on, 'modules', to_jsonb(f360.user_modules(p_auth_user_id)), 'reason', reason),
          r.display_name, r.auth_user_id);
  RETURN jsonb_build_object('ok', true, 'modules', to_jsonb(f360.user_modules(p_auth_user_id)));
END $$;

-- Remove a person's access (role, modules, store assignments). The row history stays in f360.access_changes.
-- Someone who holds customer personal data, Board or an approval scope is removed only through a reviewed pass.
CREATE FUNCTION public.f360_admin_remove_user(p_auth_user_id uuid, p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; reason text := f360.require_reason(p_reason); target f360.user_roles; s jsonb;
BEGIN
  r := f360.require_role('owner');
  IF p_auth_user_id = r.auth_user_id THEN RAISE EXCEPTION 'No puedes darte de baja a ti misma.'; END IF;
  SELECT * INTO target FROM f360.user_roles WHERE auth_user_id = p_auth_user_id FOR UPDATE;
  IF target.auth_user_id IS NULL THEN RAISE EXCEPTION 'Esa persona no tiene acceso a Fuxia 360.'; END IF;
  IF target.role = 'owner' AND (SELECT count(*) FROM f360.user_roles WHERE role = 'owner') = 1 THEN
    RAISE EXCEPTION 'Debe quedar al menos una dueña.';
  END IF;
  s := f360.user_sensitive(p_auth_user_id);
  IF (s->>'pii')::boolean OR (s->>'board')::boolean OR jsonb_array_length(s->'scopes') > 0 THEN
    RAISE EXCEPTION 'Esta persona ve datos de clientas, Board o aprueba montos; esos accesos se quitan con un pase revisado.';
  END IF;
  DELETE FROM f360.user_module_access WHERE auth_user_id = p_auth_user_id;
  UPDATE f360.location_assignments SET active = false, revoked_by_name = r.display_name, revoked_at = now()
    WHERE auth_user_id = p_auth_user_id AND active;
  DELETE FROM f360.user_roles WHERE auth_user_id = p_auth_user_id;
  INSERT INTO f360.access_changes (what, subject, before, after, by_name, by_user)
  VALUES ('removed', p_auth_user_id::text, to_jsonb(target), jsonb_build_object('reason', reason), r.display_name, r.auth_user_id);
  RETURN jsonb_build_object('ok', true);
END $$;

-- The caller's own modules, for the menu (menu is a hint only; each screen re-checks in the database).
CREATE FUNCTION public.f360_my_access() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles;
BEGIN
  r := f360.require_role('viewer');
  RETURN jsonb_build_object('role', r.role, 'modules', to_jsonb(f360.user_modules(r.auth_user_id)),
    'profile', f360.user_profile(r.role, f360.user_modules(r.auth_user_id)));
END $$;

-- Database-side check for module screens: owner/operator always; viewers only with the module.
CREATE FUNCTION f360.require_module(p_module text) RETURNS f360.user_roles
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('viewer');
BEGIN
  IF r.role IN ('owner', 'operator') THEN RETURN r; END IF;
  IF r.role = 'viewer' AND EXISTS (SELECT 1 FROM f360.user_module_access WHERE auth_user_id = r.auth_user_id AND module = p_module) THEN RETURN r; END IF;
  RAISE EXCEPTION 'Tu cuenta no tiene acceso a esta sección.' USING ERRCODE = 'insufficient_privilege';
END $$;

REVOKE ALL ON FUNCTION f360.user_profile(text, text[]), f360.user_modules(uuid), f360.require_reason(text), f360.user_sensitive(uuid),
  f360.require_module(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION f360.user_profile(text, text[]), f360.user_modules(uuid), f360.require_reason(text), f360.user_sensitive(uuid),
  f360.require_module(text) TO service_role;
REVOKE EXECUTE ON FUNCTION public.f360_admin_users(), public.f360_admin_set_profile(uuid, text, text, text),
  public.f360_admin_set_module(uuid, text, boolean, text), public.f360_admin_remove_user(uuid, text), public.f360_my_access()
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_admin_users(), public.f360_admin_set_profile(uuid, text, text, text),
  public.f360_admin_set_module(uuid, text, boolean, text), public.f360_admin_remove_user(uuid, text), public.f360_my_access()
  TO authenticated, service_role;
