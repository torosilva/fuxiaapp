-- Fuxia 360 · Fase 2 · Fuxia Skills: biblioteca (Mario 2026-11-12, diseño "Fuxia 360 · Diseño: usuarios, Fuxia Skills, inicio y bitácora").
-- ADDITIVE. The company's Claude skills (copy de ficha, pricing, retención, pauta, CRO, UGC, expansión, analista, orquestador,
-- stack verificado) live in Fuxia 360 with every version kept, instead of only in one person's Claude account.
--   · f360.skills: one row per skill (key, name, what it is for, review status).
--   · f360.skill_versions: append-only. Editing creates a new version; old versions are never changed or deleted.
--   · Who sees the library: Dirección and Operación (role), and viewers with the 'skills' module (Marketing).
--   · Who edits: Dirección only. Every edit asks for a note and is kept with its author.
--   · Nothing here calls Claude or uploads anything: uploading to the company's Anthropic account is a later step
--     (needs Mario's decision on the company account).
-- Rollback: supabase/rollbacks/20261112000200_f360_fuxia_skills.down.sql

CREATE TABLE f360.skills (
  key          text PRIMARY KEY CHECK (key ~ '^[a-z0-9][a-z0-9-]{1,62}$'),
  name         text NOT NULL CHECK (length(btrim(name)) > 0),
  purpose      text NOT NULL CHECK (length(btrim(purpose)) > 0),
  area         text NOT NULL CHECK (area IN ('contenido', 'growth', 'pauta', 'crm', 'datos', 'operacion', 'expansion')),
  status       text NOT NULL DEFAULT 'revisada' CHECK (status IN ('revisada', 'actualizar', 'archivada')),
  status_note  text CHECK (status_note IS NULL OR length(status_note) <= 500),
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE f360.skill_versions (
  id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  skill_key        text NOT NULL REFERENCES f360.skills(key) ON DELETE RESTRICT,
  version          int NOT NULL CHECK (version >= 1),
  description      text NOT NULL CHECK (length(btrim(description)) > 0 AND length(description) <= 1024),
  body             text NOT NULL CHECK (length(btrim(body)) > 0),
  note             text NOT NULL CHECK (length(btrim(note)) > 0 AND length(note) <= 500),
  created_by_name  text NOT NULL,
  created_by       uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (skill_key, version)
);
CREATE TRIGGER skill_versions_append_only BEFORE UPDATE OR DELETE ON f360.skill_versions FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();
CREATE TABLE f360.skill_status_changes (
  id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  skill_key        text NOT NULL REFERENCES f360.skills(key) ON DELETE RESTRICT,
  before           text, after text NOT NULL, note text NOT NULL,
  by_name          text NOT NULL, by_user uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  at               timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER skill_status_changes_append_only BEFORE UPDATE OR DELETE ON f360.skill_status_changes FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();
ALTER TABLE f360.skills ENABLE ROW LEVEL SECURITY;
ALTER TABLE f360.skill_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE f360.skill_status_changes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON f360.skills, f360.skill_versions, f360.skill_status_changes FROM PUBLIC, anon, authenticated;
GRANT ALL ON f360.skills, f360.skill_versions, f360.skill_status_changes TO service_role;

-- The library: every skill with its current version (no body; the detail call returns it).
CREATE FUNCTION public.f360_skills() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_module('skills');
BEGIN
  RETURN jsonb_build_object('can_edit', r.role = 'owner', 'skills', (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'key', s.key, 'name', s.name, 'purpose', s.purpose, 'area', s.area, 'status', s.status, 'status_note', s.status_note,
      'version', v.version, 'updated_at', v.created_at, 'updated_by', v.created_by_name)
    ORDER BY (s.status = 'archivada'), s.area, s.name), '[]')
    FROM f360.skills s
    LEFT JOIN LATERAL (SELECT * FROM f360.skill_versions x WHERE x.skill_key = s.key ORDER BY x.version DESC LIMIT 1) v ON true));
END $$;

-- One skill: current body + full version history (bodies of old versions on request).
CREATE FUNCTION public.f360_skill(p_key text, p_version int DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_module('skills'); s f360.skills; v f360.skill_versions;
BEGIN
  SELECT * INTO s FROM f360.skills WHERE key = p_key;
  IF s.key IS NULL THEN RAISE EXCEPTION 'Esa skill no existe.'; END IF;
  SELECT * INTO v FROM f360.skill_versions WHERE skill_key = p_key AND (p_version IS NULL OR version = p_version) ORDER BY version DESC LIMIT 1;
  RETURN jsonb_build_object('can_edit', r.role = 'owner',
    'skill', jsonb_build_object('key', s.key, 'name', s.name, 'purpose', s.purpose, 'area', s.area, 'status', s.status, 'status_note', s.status_note),
    'shown', CASE WHEN v.id IS NULL THEN NULL ELSE jsonb_build_object('version', v.version, 'description', v.description, 'body', v.body,
      'note', v.note, 'by', v.created_by_name, 'at', v.created_at) END,
    'versions', (SELECT coalesce(jsonb_agg(jsonb_build_object('version', x.version, 'note', x.note, 'by', x.created_by_name, 'at', x.created_at)
      ORDER BY x.version DESC), '[]') FROM f360.skill_versions x WHERE x.skill_key = p_key),
    'status_changes', (SELECT coalesce(jsonb_agg(jsonb_build_object('before', c.before, 'after', c.after, 'note', c.note, 'by', c.by_name, 'at', c.at)
      ORDER BY c.at DESC), '[]') FROM f360.skill_status_changes c WHERE c.skill_key = p_key));
END $$;

-- Save a new version (Dirección only). The previous versions stay as they were.
CREATE FUNCTION public.f360_skill_save(p_key text, p_description text, p_body text, p_note text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; note text := f360.require_reason(p_note); n int; cur f360.skill_versions;
BEGIN
  r := f360.require_role('owner');
  IF NOT EXISTS (SELECT 1 FROM f360.skills WHERE key = p_key) THEN RAISE EXCEPTION 'Esa skill no existe.'; END IF;
  IF length(btrim(coalesce(p_body, ''))) < 20 THEN RAISE EXCEPTION 'El contenido de la skill está vacío.'; END IF;
  IF length(btrim(coalesce(p_description, ''))) = 0 OR length(p_description) > 1024 THEN RAISE EXCEPTION 'La descripción va de 1 a 1,024 caracteres.'; END IF;
  SELECT * INTO cur FROM f360.skill_versions WHERE skill_key = p_key ORDER BY version DESC LIMIT 1 FOR UPDATE;
  IF cur.id IS NOT NULL AND cur.body = p_body AND cur.description = btrim(p_description) THEN RAISE EXCEPTION 'No hay cambios que guardar.'; END IF;
  n := coalesce(cur.version, 0) + 1;
  INSERT INTO f360.skill_versions (skill_key, version, description, body, note, created_by_name, created_by)
  VALUES (p_key, n, btrim(p_description), p_body, note, r.display_name, r.auth_user_id);
  RETURN jsonb_build_object('ok', true, 'version', n);
END $$;

-- Mark a skill as reviewed / needs update / archived (Dirección only, with note).
CREATE FUNCTION public.f360_skill_set_status(p_key text, p_status text, p_note text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; note text := f360.require_reason(p_note); s f360.skills;
BEGIN
  r := f360.require_role('owner');
  IF p_status NOT IN ('revisada', 'actualizar', 'archivada') THEN RAISE EXCEPTION 'Estado no válido.'; END IF;
  SELECT * INTO s FROM f360.skills WHERE key = p_key FOR UPDATE;
  IF s.key IS NULL THEN RAISE EXCEPTION 'Esa skill no existe.'; END IF;
  UPDATE f360.skills SET status = p_status, status_note = note WHERE key = p_key;
  INSERT INTO f360.skill_status_changes (skill_key, before, after, note, by_name, by_user) VALUES (p_key, s.status, p_status, note, r.display_name, r.auth_user_id);
  RETURN jsonb_build_object('ok', true, 'status', p_status);
END $$;

REVOKE EXECUTE ON FUNCTION public.f360_skills(), public.f360_skill(text, int), public.f360_skill_save(text, text, text, text),
  public.f360_skill_set_status(text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_skills(), public.f360_skill(text, int), public.f360_skill_save(text, text, text, text),
  public.f360_skill_set_status(text, text, text) TO authenticated, service_role;
