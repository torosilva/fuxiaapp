-- Fuxia Academy · A1 — learning engine for Sales Academy (Mario 2026-10-11: "A1 exclusivamente en staging, alcance controlado").
-- STAGING FIRST. ADDITIVE: own schema f360_academy + public.f360_academy_* RPCs. Depends on 20261030000100 (approval registry).
-- Design: docs/fuxia360/academy/00_FUXIA_ACADEMY_DISENO.md (§3–§5, §9.4, §10, §12) · A1 conditions:
--   · NO real seller access while P0-6 is open: settings.learner_access_enabled is false and a CHECK forbids true — only a reviewed
--     migration can lift it (after P0-6 is fixed). Learners in A1 = people with an explicit 'tester' grant, loaded per environment.
--   · NO certificates, NO points, NO rewards: no tables for them; settings flags are false with CHECKs.
--   · Authentication is untouched. Learners get NO privileged permission: they read published Sales content and write only their
--     own progress / practice answers, server-graded.
--   · Sales and Executive strictly separated: every learner RPC filters school = 'sales'; no executive RPC exists in A1.
--   · Product facts are NEVER stored as course text: lessons reference products by immutable code; on submission the validated
--     public knowledge (f360.product_knowledge_public) is frozen into a snapshot that is part of the approved hash (§9.4).
--   · Publication = shared registry (academy_content.publish_sales, aal2; self-approval only for ordinary product content).
-- Rollback: supabase/rollbacks/20261030000200_f360_academy_a1.down.sql

DO $$ BEGIN
  IF to_regclass('f360.approval_requests') IS NULL THEN RAISE EXCEPTION 'ABORT: falta 20261030000100 (registro de aprobaciones)'; END IF;
END $$;

CREATE SCHEMA f360_academy;
REVOKE ALL ON SCHEMA f360_academy FROM PUBLIC, anon, authenticated, service_role;

-- ── Settings (A1 gates) ──────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE f360_academy.settings (
  id                     boolean PRIMARY KEY DEFAULT true CHECK (id),
  learner_access_enabled boolean NOT NULL DEFAULT false,
  certificates_enabled   boolean NOT NULL DEFAULT false,
  points_enabled         boolean NOT NULL DEFAULT false,
  redemptions_enabled    boolean NOT NULL DEFAULT false,
  note                   text NOT NULL DEFAULT 'A1: acceso real de vendedoras bloqueado mientras P0-6 siga abierto (Mario 2026-10-11).',
  CONSTRAINT a1_no_real_learners CHECK (NOT learner_access_enabled),   -- lifted only by a reviewed migration after P0-6
  CONSTRAINT a1_no_certificates  CHECK (NOT certificates_enabled),
  CONSTRAINT a1_no_points        CHECK (NOT points_enabled),
  CONSTRAINT a1_no_redemptions   CHECK (NOT redemptions_enabled)
);
INSERT INTO f360_academy.settings DEFAULT VALUES;

-- ── Educational roles (layer 1). Loaded per environment by a reviewed script. ────────────────────────────────────────────────
CREATE TABLE f360_academy.grants (
  auth_user_id    uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  role            text NOT NULL CHECK (role IN ('tester', 'editor', 'admin', 'executive_learner')),
  display_name    text NOT NULL CHECK (length(btrim(display_name)) BETWEEN 2 AND 80),
  active          boolean NOT NULL DEFAULT true,
  granted_by_name text NOT NULL,
  evidence        text NOT NULL CHECK (length(btrim(evidence)) >= 5),
  granted_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  revoked_at      timestamptz,
  PRIMARY KEY (auth_user_id, role)
);
COMMENT ON TABLE f360_academy.grants IS 'Academy educational roles (not Fuxia 360 roles, not approvals). tester = authorized test learner (A1).';
CREATE TABLE f360_academy.grant_changes (
  id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  at     timestamptz NOT NULL DEFAULT clock_timestamp(),
  op     text NOT NULL,
  before jsonb,
  after  jsonb
);
CREATE TRIGGER grant_changes_append_only BEFORE UPDATE OR DELETE ON f360_academy.grant_changes FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();
CREATE FUNCTION f360_academy.log_grant_change() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  INSERT INTO f360_academy.grant_changes (op, before, after)
  VALUES (TG_OP, CASE WHEN TG_OP <> 'INSERT' THEN to_jsonb(OLD) END, CASE WHEN TG_OP <> 'DELETE' THEN to_jsonb(NEW) END);
  RETURN coalesce(NEW, OLD);
END $$;
CREATE TRIGGER grants_log AFTER INSERT OR UPDATE OR DELETE ON f360_academy.grants FOR EACH ROW EXECUTE FUNCTION f360_academy.log_grant_change();

-- ── Content (versioned; immutable once submitted) ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE f360_academy.courses (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school               text NOT NULL CHECK (school IN ('sales', 'executive')),
  key                  text NOT NULL UNIQUE CHECK (key ~ '^[a-z0-9-]{3,60}$'),
  title                text NOT NULL CHECK (length(btrim(title)) BETWEEN 3 AND 120),
  kind                 text NOT NULL CHECK (kind IN ('nivel', 'parte', 'microcert', 'programa', 'bienvenida')),   -- bienvenida = first-entry video
  level_key            text CHECK (level_key IN ('starter', 'product_expert', 'sales_pro', 'master')),
  sort                 int NOT NULL DEFAULT 0,
  published_version_id uuid,
  created_by_name      text NOT NULL,
  created_at           timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE f360_academy.course_versions (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  course_id           uuid NOT NULL REFERENCES f360_academy.courses (id),
  version             int NOT NULL CHECK (version > 0),
  status              text NOT NULL DEFAULT 'borrador' CHECK (status IN ('borrador', 'en_revision', 'publicado', 'retirado')),
  title               text NOT NULL CHECK (length(btrim(title)) BETWEEN 3 AND 120),
  summary             text CHECK (summary IS NULL OR length(summary) <= 600),
  content_hash        text CHECK (content_hash IS NULL OR content_hash ~ '^[0-9a-f]{64}$'),
  approval_request_id uuid REFERENCES f360.approval_requests (id),
  created_by_name     text NOT NULL,
  created_at          timestamptz NOT NULL DEFAULT clock_timestamp(),
  submitted_at        timestamptz,
  published_at        timestamptz,
  retired_at          timestamptz,
  UNIQUE (course_id, version)
);
CREATE UNIQUE INDEX course_versions_one_published ON f360_academy.course_versions (course_id) WHERE status = 'publicado';
CREATE UNIQUE INDEX course_versions_one_open ON f360_academy.course_versions (course_id) WHERE status IN ('borrador', 'en_revision');
ALTER TABLE f360_academy.courses ADD CONSTRAINT courses_published_version_fk FOREIGN KEY (published_version_id) REFERENCES f360_academy.course_versions (id);

CREATE TABLE f360_academy.lessons (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  course_version_id uuid NOT NULL REFERENCES f360_academy.course_versions (id),
  key               text NOT NULL CHECK (key ~ '^[a-z0-9.-]{1,20}$'),
  position          int NOT NULL CHECK (position > 0),
  title             text NOT NULL CHECK (length(btrim(title)) BETWEEN 3 AND 120),
  minutes           int NOT NULL CHECK (minutes BETWEEN 1 AND 15),
  blocks            jsonb NOT NULL DEFAULT '[]' CHECK (jsonb_typeof(blocks) = 'array'),
  product_codes     text[] NOT NULL DEFAULT '{}',
  product_snapshot  jsonb,                    -- frozen at submission from f360.product_knowledge_public (validated only)
  UNIQUE (course_version_id, key),
  UNIQUE (course_version_id, position)
);
CREATE TABLE f360_academy.items (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  course_version_id uuid NOT NULL REFERENCES f360_academy.course_versions (id),
  key               text NOT NULL CHECK (key ~ '^[A-Za-z0-9-]{2,40}$'),
  lesson_key        text,
  uses              text[] NOT NULL DEFAULT '{practica}' CHECK (uses <@ ARRAY['practica', 'examen'] AND cardinality(uses) > 0),
  area              text NOT NULL CHECK (area IN ('producto', 'tallas', 'cuidados', 'atencion', 'marca_politicas')),
  kind              text NOT NULL CHECK (kind IN ('opcion', 'vf', 'varias', 'ordenar')),
  prompt            text NOT NULL CHECK (length(btrim(prompt)) BETWEEN 5 AND 600),
  options           jsonb NOT NULL DEFAULT '[]' CHECK (jsonb_typeof(options) = 'array'),
  answer            jsonb NOT NULL,           -- never returned to a learner
  explanation       text NOT NULL CHECK (length(btrim(explanation)) BETWEEN 3 AND 600),
  source            text NOT NULL CHECK (length(btrim(source)) >= 3),
  product_code      text,
  status            text NOT NULL DEFAULT 'ok' CHECK (status IN ('ok', 'bloqueada')),
  UNIQUE (course_version_id, key)
);
CREATE TABLE f360_academy.review_comments (
  id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  course_version_id uuid NOT NULL REFERENCES f360_academy.course_versions (id),
  lesson_key        text,
  item_key          text,
  block_index       int,
  body              text NOT NULL CHECK (length(btrim(body)) BETWEEN 2 AND 1000),
  by_user           uuid NOT NULL,
  by_name           text NOT NULL,
  at                timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TRIGGER review_comments_append_only BEFORE UPDATE OR DELETE ON f360_academy.review_comments FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();

-- Children of a version can be written only while the version is a draft. The version itself: content fixed once submitted.
CREATE FUNCTION f360_academy.guard_draft_child() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE st text;
BEGIN
  SELECT status INTO st FROM f360_academy.course_versions WHERE id = coalesce(NEW.course_version_id, OLD.course_version_id);
  IF st IS DISTINCT FROM 'borrador' THEN RAISE EXCEPTION 'Esta versión ya no es borrador: no se puede cambiar su contenido.'; END IF;
  IF TG_OP = 'UPDATE' AND NEW.course_version_id IS DISTINCT FROM OLD.course_version_id THEN RAISE EXCEPTION 'No se puede mover contenido entre versiones.'; END IF;
  RETURN coalesce(NEW, OLD);
END $$;
CREATE TRIGGER lessons_draft_only BEFORE INSERT OR UPDATE OR DELETE ON f360_academy.lessons FOR EACH ROW EXECUTE FUNCTION f360_academy.guard_draft_child();
CREATE TRIGGER items_draft_only BEFORE INSERT OR UPDATE OR DELETE ON f360_academy.items FOR EACH ROW EXECUTE FUNCTION f360_academy.guard_draft_child();

CREATE FUNCTION f360_academy.guard_version() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'Una versión de curso no se borra.'; END IF;
  IF (NEW.course_id, NEW.version, NEW.created_by_name, NEW.created_at) IS DISTINCT FROM (OLD.course_id, OLD.version, OLD.created_by_name, OLD.created_at) THEN
    RAISE EXCEPTION 'Estos datos de la versión no cambian.';
  END IF;
  IF OLD.status <> 'borrador' AND (NEW.title, NEW.summary) IS DISTINCT FROM (OLD.title, OLD.summary) THEN
    RAISE EXCEPTION 'Esta versión ya no es borrador: no se puede cambiar su contenido.';
  END IF;
  IF OLD.status IN ('publicado', 'en_revision') AND NEW.content_hash IS DISTINCT FROM OLD.content_hash AND NEW.status <> 'borrador' THEN
    RAISE EXCEPTION 'La huella de una versión enviada no cambia.';
  END IF;
  IF NEW.status <> OLD.status AND NOT ((OLD.status = 'borrador' AND NEW.status = 'en_revision')
      OR (OLD.status = 'en_revision' AND NEW.status IN ('borrador', 'publicado'))
      OR (OLD.status = 'publicado' AND NEW.status = 'retirado')) THEN
    RAISE EXCEPTION 'Transición de versión no permitida: % → %', OLD.status, NEW.status;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER course_versions_guard BEFORE UPDATE OR DELETE ON f360_academy.course_versions FOR EACH ROW EXECUTE FUNCTION f360_academy.guard_version();

-- ── Learner progress (own rows only, through RPCs) ───────────────────────────────────────────────────────────────────────────
CREATE TABLE f360_academy.enrollments (
  auth_user_id      uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  course_id         uuid NOT NULL REFERENCES f360_academy.courses (id),
  course_version_id uuid NOT NULL REFERENCES f360_academy.course_versions (id),
  location_id       uuid REFERENCES f360.locations (id),       -- store at enrollment (reports)
  enrolled_at       timestamptz NOT NULL DEFAULT clock_timestamp(),
  completed_at      timestamptz,
  PRIMARY KEY (auth_user_id, course_id)
);
CREATE TABLE f360_academy.lesson_progress (
  auth_user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  lesson_id    uuid NOT NULL REFERENCES f360_academy.lessons (id),
  card_index   int NOT NULL DEFAULT 0 CHECK (card_index >= 0),
  status       text NOT NULL DEFAULT 'en_curso' CHECK (status IN ('en_curso', 'completada')),
  started_at   timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at   timestamptz NOT NULL DEFAULT clock_timestamp(),
  completed_at timestamptz,
  PRIMARY KEY (auth_user_id, lesson_id)
);
CREATE TABLE f360_academy.attempts (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  auth_user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  item_id      uuid NOT NULL REFERENCES f360_academy.items (id),
  kind         text NOT NULL DEFAULT 'practica' CHECK (kind = 'practica'),   -- A1: practice only (no exam, no certificate)
  answer       jsonb NOT NULL,
  correct      boolean NOT NULL,
  at           timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX attempts_user_idx ON f360_academy.attempts (auth_user_id, at DESC);
CREATE TRIGGER attempts_append_only BEFORE UPDATE OR DELETE ON f360_academy.attempts FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();

CREATE TABLE f360_academy.admin_events (
  id      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  by_user uuid,
  by_name text NOT NULL,
  action  text NOT NULL,
  ref     text,
  detail  jsonb NOT NULL DEFAULT '{}'
);
CREATE TRIGGER admin_events_append_only BEFORE UPDATE OR DELETE ON f360_academy.admin_events FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();

-- ── Access (layer 2) ─────────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION f360_academy.has_grant(p_uid uuid, p_role text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT p_uid IS NOT NULL AND EXISTS (SELECT 1 FROM f360_academy.grants WHERE auth_user_id = p_uid AND role = p_role AND active) $$;

-- Sales learner state: 'ok' (tester, or active seller when access is enabled) | 'bloqueado' (active seller, access disabled: P0-6) | 'none'
CREATE FUNCTION f360_academy.sales_access(p_uid uuid) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT CASE
    WHEN p_uid IS NULL THEN 'none'
    WHEN f360_academy.has_grant(p_uid, 'tester') THEN 'ok'
    WHEN EXISTS (SELECT 1 FROM f360.sellers s WHERE s.auth_user_id = p_uid AND s.status = 'activa')
      THEN CASE WHEN (SELECT learner_access_enabled FROM f360_academy.settings WHERE id) THEN 'ok' ELSE 'bloqueado' END
    ELSE 'none' END $$;

CREATE FUNCTION f360_academy.is_editor(p_uid uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT f360_academy.has_grant(p_uid, 'editor') OR f360_academy.has_grant(p_uid, 'admin') $$;
CREATE FUNCTION f360_academy.is_content_approver(p_uid uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT f360.can_approve_op('academy_content', 'publish_sales', p_uid) OR f360.can_approve_op('academy_content', 'publish_sales_policy', p_uid) $$;
CREATE FUNCTION f360_academy.is_staff(p_uid uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT f360_academy.is_editor(p_uid) OR f360_academy.is_content_approver(p_uid) $$;
CREATE FUNCTION f360_academy.caller_name(p_uid uuid) RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT coalesce((SELECT display_name FROM f360_academy.grants WHERE auth_user_id = p_uid AND active ORDER BY granted_at LIMIT 1),
                  (SELECT display_name FROM f360.user_roles WHERE auth_user_id = p_uid), 'Usuario') $$;

CREATE FUNCTION f360_academy.denied() RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$ SELECT jsonb_build_object('ok', false, 'error', 'No disponible.') $$;

-- ── Content helpers ──────────────────────────────────────────────────────────────────────────────────────────────────────────
-- Validated product facts for one code (NULL when the model is not active or its knowledge is not validated).
CREATE FUNCTION f360_academy.product_card(p_code text) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT CASE WHEN f360.product_knowledge_public(p.id) IS NOT NULL THEN jsonb_build_object(
    'code', p.code, 'name', p.name, 'category', p.category_key,
    'photo', f360.product_primary_image(p.id),
    'sizes', (SELECT jsonb_agg(s.label ORDER BY s.sort) FROM f360.product_sizes s WHERE s.product_id = p.id),
    'colors', (SELECT jsonb_agg(jsonb_build_object('name', c.name, 'photo', f360.color_primary_image(c.id)) ORDER BY c.sort, c.created_at)
               FROM f360.product_colors c WHERE c.product_id = p.id),
    'knowledge', f360.product_knowledge_public(p.id)) END
  FROM f360.products p WHERE p.code = p_code AND p.status = 'active' $$;

CREATE FUNCTION f360_academy.valid_blocks(p jsonb) RETURNS text LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE b jsonb;
BEGIN
  IF jsonb_typeof(p) <> 'array' OR jsonb_array_length(p) = 0 OR jsonb_array_length(p) > 40 THEN RETURN 'Una lección necesita entre 1 y 40 tarjetas.'; END IF;
  FOR b IN SELECT * FROM jsonb_array_elements(p) LOOP
    IF jsonb_typeof(b) <> 'object' OR NOT (b->>'type' = ANY (ARRAY['texto', 'ficha', 'ficha_talla', 'pendiente', 'politica', 'video'])) THEN RETURN 'Tipo de tarjeta no válido.'; END IF;
    -- a video is a static file of the app, bound to its exact bytes by sha256 (part of the approved hash)
    IF b->>'type' = 'video' AND (coalesce(b->>'src', '') !~ '^/academy/[a-z0-9._-]+\.mp4$' OR coalesce(b->>'sha256', '') !~ '^[0-9a-f]{64}$'
        OR length(btrim(coalesce(b->>'source', ''))) < 3) THEN RETURN 'Una tarjeta de video necesita archivo, huella sha256 y fuente.'; END IF;
    IF b->>'type' IN ('texto', 'pendiente', 'politica') AND length(btrim(coalesce(b->>'text', ''))) NOT BETWEEN 2 AND 600 THEN RETURN 'Cada tarjeta de texto lleva entre 2 y 600 caracteres.'; END IF;
    IF b->>'type' IN ('texto', 'politica') AND length(btrim(coalesce(b->>'source', ''))) < 3 THEN RETURN 'Cada tarjeta de texto lleva su etiqueta de fuente.'; END IF;
    IF b->>'type' IN ('ficha', 'ficha_talla') AND coalesce(b->>'code', '') !~ '^[A-Z0-9-]{2,60}$' THEN RETURN 'Una tarjeta de ficha necesita el código del modelo.'; END IF;
  END LOOP;
  RETURN NULL;
END $$;

-- Canonical content of a version → sha256. Everything an approval covers is in here (texts, product snapshot, questions + answers).
CREATE FUNCTION f360_academy.version_hash(p_version uuid) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT encode(sha256(convert_to(jsonb_build_object(
    'course', (SELECT c.key FROM f360_academy.courses c WHERE c.id = v.course_id), 'version', v.version, 'title', v.title, 'summary', v.summary,
    'lessons', coalesce((SELECT jsonb_agg(jsonb_build_object('key', l.key, 'position', l.position, 'title', l.title, 'minutes', l.minutes,
                 'blocks', l.blocks, 'products', to_jsonb(l.product_codes), 'snapshot', l.product_snapshot) ORDER BY l.position)
               FROM f360_academy.lessons l WHERE l.course_version_id = v.id), '[]'),
    'items', coalesce((SELECT jsonb_agg(jsonb_build_object('key', i.key, 'lesson', i.lesson_key, 'uses', to_jsonb(i.uses), 'area', i.area,
                 'kind', i.kind, 'prompt', i.prompt, 'options', i.options, 'answer', i.answer, 'explanation', i.explanation,
                 'source', i.source, 'product', i.product_code, 'status', i.status) ORDER BY i.key)
               FROM f360_academy.items i WHERE i.course_version_id = v.id), '[]'))::text, 'UTF8')), 'hex')
  FROM f360_academy.course_versions v WHERE v.id = p_version $$;

-- Learner-safe item (no answer).
CREATE FUNCTION f360_academy.item_public(i f360_academy.items) RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object('id', i.id, 'key', i.key, 'kind', i.kind, 'area', i.area, 'prompt', i.prompt, 'options', i.options) $$;

-- Server-side grading. answer shapes: opcion {"choice":"b"} · vf {"value":true} · varias {"choices":[..]} · ordenar {"order":[..]}
CREATE FUNCTION f360_academy.grade(i f360_academy.items, p_answer jsonb) RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE i.kind
    WHEN 'opcion' THEN (p_answer->>'choice') IS NOT NULL AND (p_answer->>'choice') = (i.answer->>'choice')
    WHEN 'vf'     THEN jsonb_typeof(p_answer->'value') = 'boolean' AND (p_answer->'value') = (i.answer->'value')
    WHEN 'varias' THEN jsonb_typeof(p_answer->'choices') = 'array'
      AND (SELECT coalesce(array_agg(x ORDER BY x), '{}') FROM jsonb_array_elements_text(p_answer->'choices') x)
        = (SELECT coalesce(array_agg(x ORDER BY x), '{}') FROM jsonb_array_elements_text(i.answer->'choices') x)
    WHEN 'ordenar' THEN jsonb_typeof(p_answer->'order') = 'array' AND (p_answer->'order') = (i.answer->'order')
    ELSE false END $$;

-- The version a learner sees for a course: her pinned enrollment, else the published one.
CREATE FUNCTION f360_academy.learner_version(p_uid uuid, p_course uuid) RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT coalesce((SELECT e.course_version_id FROM f360_academy.enrollments e WHERE e.auth_user_id = p_uid AND e.course_id = p_course),
                  (SELECT c.published_version_id FROM f360_academy.courses c WHERE c.id = p_course)) $$;

CREATE FUNCTION f360_academy.render_lesson(l f360_academy.lessons, p_live boolean) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT jsonb_build_object('id', l.id, 'key', l.key, 'position', l.position, 'title', l.title, 'minutes', l.minutes, 'blocks', l.blocks,
    'products', CASE WHEN p_live THEN coalesce((SELECT jsonb_object_agg(c, coalesce(f360_academy.product_card(c), 'null'::jsonb)) FROM unnest(l.product_codes) c), '{}')
                     ELSE coalesce(l.product_snapshot, '{}') END) $$;

-- ── Learner RPCs ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION public.f360_academy_me() RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT jsonb_build_object('ok', true, 'sales', f360_academy.sales_access(auth.uid()),
    'editor', f360_academy.is_editor(auth.uid()), 'approver', f360_academy.is_content_approver(auth.uid()),
    'admin', f360_academy.has_grant(auth.uid(), 'admin'), 'aal', coalesce(auth.jwt()->>'aal', ''),
    'name', f360_academy.caller_name(auth.uid()),
    'gates', (SELECT jsonb_build_object('learner_access_enabled', learner_access_enabled, 'certificates_enabled', certificates_enabled,
                'points_enabled', points_enabled, 'redemptions_enabled', redemptions_enabled, 'note', note) FROM f360_academy.settings WHERE id)) $$;

CREATE FUNCTION public.f360_academy_home() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid();
BEGIN
  IF f360_academy.sales_access(uid) <> 'ok' THEN RETURN f360_academy.denied(); END IF;
  RETURN jsonb_build_object('ok', true, 'courses', coalesce((
    SELECT jsonb_agg(jsonb_build_object('id', c.id, 'key', c.key, 'title', v.title, 'summary', v.summary, 'kind', c.kind, 'version', v.version,
      'enrolled', EXISTS (SELECT 1 FROM f360_academy.enrollments e WHERE e.auth_user_id = uid AND e.course_id = c.id),
      'lessons', (SELECT jsonb_agg(jsonb_build_object('id', l.id, 'key', l.key, 'title', l.title, 'minutes', l.minutes, 'cards', jsonb_array_length(l.blocks),
                    'status', coalesce(p.status, 'pendiente'), 'card_index', coalesce(p.card_index, 0)) ORDER BY l.position)
                  FROM f360_academy.lessons l LEFT JOIN f360_academy.lesson_progress p ON p.lesson_id = l.id AND p.auth_user_id = uid
                  WHERE l.course_version_id = v.id)) ORDER BY c.sort, c.title)
    FROM f360_academy.courses c JOIN f360_academy.course_versions v ON v.id = f360_academy.learner_version(uid, c.id)
    WHERE c.school = 'sales' AND v.status IN ('publicado', 'retirado')), '[]'));
END $$;

CREATE FUNCTION public.f360_academy_lesson(p_lesson uuid) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid(); l f360_academy.lessons; v f360_academy.course_versions; c f360_academy.courses; loc uuid;
BEGIN
  IF f360_academy.sales_access(uid) <> 'ok' THEN RETURN f360_academy.denied(); END IF;
  SELECT * INTO l FROM f360_academy.lessons WHERE id = p_lesson;
  SELECT * INTO v FROM f360_academy.course_versions WHERE id = l.course_version_id;
  SELECT * INTO c FROM f360_academy.courses WHERE id = v.course_id;
  IF l.id IS NULL OR c.school <> 'sales' OR v.id IS DISTINCT FROM f360_academy.learner_version(uid, c.id) OR v.status NOT IN ('publicado', 'retirado') THEN
    RETURN f360_academy.denied();
  END IF;
  IF NOT EXISTS (SELECT 1 FROM f360_academy.enrollments WHERE auth_user_id = uid AND course_id = c.id) THEN
    SELECT location_id INTO loc FROM f360.location_assignments WHERE auth_user_id = uid AND active ORDER BY granted_at DESC LIMIT 1;
    INSERT INTO f360_academy.enrollments (auth_user_id, course_id, course_version_id, location_id) VALUES (uid, c.id, v.id, loc);
  END IF;
  INSERT INTO f360_academy.lesson_progress (auth_user_id, lesson_id) VALUES (uid, l.id) ON CONFLICT DO NOTHING;
  RETURN jsonb_build_object('ok', true, 'course', jsonb_build_object('id', c.id, 'title', v.title),
    'lesson', f360_academy.render_lesson(l, false),
    'progress', (SELECT jsonb_build_object('card_index', card_index, 'status', status) FROM f360_academy.lesson_progress WHERE auth_user_id = uid AND lesson_id = l.id),
    'practice', coalesce((SELECT jsonb_agg(f360_academy.item_public(i) ORDER BY i.key) FROM f360_academy.items i
                          WHERE i.course_version_id = v.id AND i.lesson_key = l.key AND 'practica' = ANY (i.uses) AND i.status = 'ok'), '[]'),
    'next', (SELECT n.id FROM f360_academy.lessons n WHERE n.course_version_id = v.id AND n.position > l.position ORDER BY n.position LIMIT 1));
END $$;

CREATE FUNCTION public.f360_academy_progress_save(p_lesson uuid, p_card int, p_done boolean DEFAULT false) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid(); l f360_academy.lessons; n int;
BEGIN
  IF f360_academy.sales_access(uid) <> 'ok' THEN RETURN f360_academy.denied(); END IF;
  SELECT * INTO l FROM f360_academy.lessons WHERE id = p_lesson;
  IF l.id IS NULL OR NOT EXISTS (SELECT 1 FROM f360_academy.enrollments e WHERE e.auth_user_id = uid AND e.course_version_id = l.course_version_id) THEN
    RETURN f360_academy.denied();
  END IF;
  n := jsonb_array_length(l.blocks);
  IF p_card IS NULL OR p_card < 0 OR p_card > n THEN RETURN jsonb_build_object('ok', false, 'error', 'Tarjeta no válida.'); END IF;
  INSERT INTO f360_academy.lesson_progress AS p (auth_user_id, lesson_id, card_index, status, completed_at)
  VALUES (uid, l.id, p_card, CASE WHEN coalesce(p_done, false) THEN 'completada' ELSE 'en_curso' END, CASE WHEN coalesce(p_done, false) THEN clock_timestamp() END)
  ON CONFLICT (auth_user_id, lesson_id) DO UPDATE SET card_index = EXCLUDED.card_index, updated_at = clock_timestamp(),
    status = CASE WHEN p.status = 'completada' OR coalesce(p_done, false) THEN 'completada' ELSE 'en_curso' END,
    completed_at = coalesce(p.completed_at, EXCLUDED.completed_at);
  UPDATE f360_academy.enrollments e SET completed_at = clock_timestamp()
   WHERE e.auth_user_id = uid AND e.course_version_id = l.course_version_id AND e.completed_at IS NULL
     AND NOT EXISTS (SELECT 1 FROM f360_academy.lessons x LEFT JOIN f360_academy.lesson_progress q ON q.lesson_id = x.id AND q.auth_user_id = uid
                      WHERE x.course_version_id = l.course_version_id AND coalesce(q.status, '') <> 'completada');
  RETURN jsonb_build_object('ok', true);
END $$;

CREATE FUNCTION public.f360_academy_answer(p_item uuid, p_answer jsonb) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid(); i f360_academy.items; ok boolean;
BEGIN
  IF f360_academy.sales_access(uid) <> 'ok' THEN RETURN f360_academy.denied(); END IF;
  SELECT * INTO i FROM f360_academy.items WHERE id = p_item;
  IF i.id IS NULL OR i.status <> 'ok' OR NOT ('practica' = ANY (i.uses))
     OR NOT EXISTS (SELECT 1 FROM f360_academy.enrollments e WHERE e.auth_user_id = uid AND e.course_version_id = i.course_version_id) THEN
    RETURN f360_academy.denied();
  END IF;
  IF p_answer IS NULL OR jsonb_typeof(p_answer) <> 'object' OR length(p_answer::text) > 2000 THEN RETURN jsonb_build_object('ok', false, 'error', 'Respuesta no válida.'); END IF;
  ok := f360_academy.grade(i, p_answer);
  INSERT INTO f360_academy.attempts (auth_user_id, item_id, answer, correct) VALUES (uid, i.id, p_answer, ok);
  RETURN jsonb_build_object('ok', true, 'correct', ok, 'explanation', i.explanation, 'source', i.source, 'answer', i.answer);   -- practice: show the right answer after answering
END $$;

CREATE FUNCTION public.f360_academy_fichas() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid();
BEGIN
  IF f360_academy.sales_access(uid) <> 'ok' THEN RETURN f360_academy.denied(); END IF;
  RETURN jsonb_build_object('ok', true, 'fichas', coalesce((
    SELECT jsonb_agg(card ORDER BY card->>'name') FROM (
      SELECT DISTINCT ON (s.key) s.value AS card
      FROM f360_academy.courses c
      JOIN f360_academy.lessons l ON l.course_version_id = f360_academy.learner_version(uid, c.id)
      JOIN f360_academy.course_versions v ON v.id = l.course_version_id AND v.status IN ('publicado', 'retirado'),
      LATERAL jsonb_each(coalesce(l.product_snapshot, '{}')) s
      WHERE c.school = 'sales' AND jsonb_typeof(s.value) = 'object') x), '[]'));
END $$;

-- ── Content administration RPCs (editor / approver) ──────────────────────────────────────────────────────────────────────────
CREATE FUNCTION f360_academy.admin_log(p_uid uuid, p_action text, p_ref text, p_detail jsonb DEFAULT '{}') RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  INSERT INTO f360_academy.admin_events (by_user, by_name, action, ref, detail) VALUES (p_uid, f360_academy.caller_name(p_uid), p_action, p_ref, coalesce(p_detail, '{}')) $$;

CREATE FUNCTION public.f360_academy_admin_overview() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid();
BEGIN
  IF NOT f360_academy.is_staff(uid) THEN RETURN f360_academy.denied(); END IF;
  RETURN jsonb_build_object('ok', true, 'me', public.f360_academy_me(), 'courses', coalesce((
    SELECT jsonb_agg(jsonb_build_object('id', c.id, 'key', c.key, 'title', c.title, 'school', c.school, 'kind', c.kind,
      'published_version_id', c.published_version_id,
      'versions', (SELECT jsonb_agg(jsonb_build_object('id', v.id, 'version', v.version, 'status', v.status, 'title', v.title,
          'lessons', (SELECT count(*) FROM f360_academy.lessons l WHERE l.course_version_id = v.id),
          'items', (SELECT count(*) FROM f360_academy.items i WHERE i.course_version_id = v.id),
          'comments', (SELECT count(*) FROM f360_academy.review_comments r WHERE r.course_version_id = v.id),
          'request', (SELECT jsonb_build_object('id', r.id, 'status', r.status, 'operation', r.operation, 'requested_by', r.requested_by_name,
                        'requested_at', r.requested_at, 'expires_at', r.expires_at, 'decided_by', r.decided_by_name, 'self_approval', r.self_approval)
                      FROM f360.approval_requests r WHERE r.id = v.approval_request_id),
          -- §9.4: a published snapshot whose product knowledge was re-validated since → needs review
          'stale_products', CASE WHEN v.status = 'publicado' THEN (SELECT coalesce(jsonb_agg(DISTINCT s.key), '[]') FROM f360_academy.lessons l,
              LATERAL jsonb_each(coalesce(l.product_snapshot, '{}')) s
              WHERE l.course_version_id = v.id AND (s.value->'knowledge'->>'version') IS DISTINCT FROM (f360_academy.product_card(s.key)->'knowledge'->>'version')) END
        ) ORDER BY v.version DESC) FROM f360_academy.course_versions v WHERE v.course_id = c.id)
    ) ORDER BY c.school, c.sort, c.title) FROM f360_academy.courses c), '[]'),
    'events', coalesce((SELECT jsonb_agg(jsonb_build_object('at', e.at, 'action', e.action, 'by', e.by_name, 'reason', e.reason, 'self', e.self_approval,
                  'aal', e.aal, 'operation', r.operation, 'version', r.object_version) ORDER BY e.id DESC)
                FROM (SELECT * FROM f360.approval_events ORDER BY id DESC LIMIT 400) e JOIN f360.approval_requests r ON r.id = e.request_id
                WHERE r.scope LIKE 'academy\_%'), '[]'));
END $$;

CREATE FUNCTION public.f360_academy_admin_version(p_version uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid(); v f360_academy.course_versions;
BEGIN
  IF NOT f360_academy.is_staff(uid) THEN RETURN f360_academy.denied(); END IF;
  SELECT * INTO v FROM f360_academy.course_versions WHERE id = p_version;
  IF v.id IS NULL THEN RETURN f360_academy.denied(); END IF;
  RETURN jsonb_build_object('ok', true,
    'version', jsonb_build_object('id', v.id, 'version', v.version, 'status', v.status, 'title', v.title, 'summary', v.summary,
      'course', (SELECT jsonb_build_object('id', c.id, 'key', c.key, 'school', c.school) FROM f360_academy.courses c WHERE c.id = v.course_id),
      'hash', v.content_hash, 'current_hash', f360_academy.version_hash(v.id)),
    'lessons', coalesce((SELECT jsonb_agg(f360_academy.render_lesson(l, v.status = 'borrador') ORDER BY l.position) FROM f360_academy.lessons l WHERE l.course_version_id = v.id), '[]'),
    'items', coalesce((SELECT jsonb_agg(to_jsonb(i) - 'course_version_id' ORDER BY i.key) FROM f360_academy.items i WHERE i.course_version_id = v.id), '[]'),
    'comments', coalesce((SELECT jsonb_agg(jsonb_build_object('lesson', r.lesson_key, 'item', r.item_key, 'block', r.block_index, 'body', r.body, 'by', r.by_name, 'at', r.at) ORDER BY r.id)
                          FROM f360_academy.review_comments r WHERE r.course_version_id = v.id), '[]'),
    'request', (SELECT jsonb_build_object('id', r.id, 'status', r.status, 'operation', r.operation, 'requested_by', r.requested_by_name, 'reason', r.reason,
                  'requested_at', r.requested_at, 'expires_at', r.expires_at, 'hash', r.object_hash,
                  'events', (SELECT jsonb_agg(jsonb_build_object('action', e.action, 'by', e.by_name, 'reason', e.reason, 'at', e.at, 'aal', e.aal, 'self', e.self_approval) ORDER BY e.id)
                             FROM f360.approval_events e WHERE e.request_id = r.id))
                FROM f360.approval_requests r WHERE r.id = v.approval_request_id),
    'can_edit', f360_academy.is_editor(uid) AND v.status = 'borrador',
    'can_decide', v.status = 'en_revision' AND f360_academy.is_content_approver(uid));
END $$;

CREATE FUNCTION public.f360_academy_lesson_save(p_lesson uuid, p_title text, p_minutes int, p_blocks jsonb, p_product_codes text[]) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid(); l f360_academy.lessons; bad text; st text;
BEGIN
  IF NOT f360_academy.is_editor(uid) THEN RETURN f360_academy.denied(); END IF;
  SELECT * INTO l FROM f360_academy.lessons WHERE id = p_lesson;
  SELECT status INTO st FROM f360_academy.course_versions WHERE id = l.course_version_id;
  IF l.id IS NULL THEN RETURN f360_academy.denied(); END IF;
  IF st <> 'borrador' THEN RETURN jsonb_build_object('ok', false, 'error', 'Esta versión ya no es borrador. Crea una nueva versión para editar.'); END IF;
  bad := f360_academy.valid_blocks(p_blocks);
  IF bad IS NOT NULL THEN RETURN jsonb_build_object('ok', false, 'error', bad); END IF;
  IF length(btrim(coalesce(p_title, ''))) NOT BETWEEN 3 AND 120 OR coalesce(p_minutes, 0) NOT BETWEEN 1 AND 15 THEN RETURN jsonb_build_object('ok', false, 'error', 'Revisa el título y los minutos.'); END IF;
  UPDATE f360_academy.lessons SET title = btrim(p_title), minutes = p_minutes, blocks = p_blocks,
    product_codes = coalesce((SELECT array_agg(DISTINCT upper(btrim(c))) FROM unnest(p_product_codes) c WHERE btrim(c) <> ''), '{}'), product_snapshot = NULL
  WHERE id = l.id;
  PERFORM f360_academy.admin_log(uid, 'lesson_save', l.id::text, jsonb_build_object('key', l.key));
  RETURN jsonb_build_object('ok', true);
END $$;

CREATE FUNCTION public.f360_academy_item_save(p_item uuid, p_fields jsonb) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid(); i f360_academy.items; st text; f jsonb := coalesce(p_fields, '{}'); bad text;
BEGIN
  IF NOT f360_academy.is_editor(uid) THEN RETURN f360_academy.denied(); END IF;
  SELECT * INTO i FROM f360_academy.items WHERE id = p_item;
  SELECT status INTO st FROM f360_academy.course_versions WHERE id = i.course_version_id;
  IF i.id IS NULL THEN RETURN f360_academy.denied(); END IF;
  IF st <> 'borrador' THEN RETURN jsonb_build_object('ok', false, 'error', 'Esta versión ya no es borrador.'); END IF;
  SELECT string_agg(k, ', ') INTO bad FROM jsonb_object_keys(f) k WHERE k <> ALL (ARRAY['prompt', 'options', 'answer', 'explanation', 'source', 'status']);
  IF bad IS NOT NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'Campos no permitidos: ' || bad); END IF;
  BEGIN
    UPDATE f360_academy.items SET
      prompt = coalesce(f->>'prompt', prompt), options = coalesce(f->'options', options), answer = coalesce(f->'answer', answer),
      explanation = coalesce(f->>'explanation', explanation), source = coalesce(f->>'source', source), status = coalesce(f->>'status', status)
    WHERE id = i.id;
  EXCEPTION WHEN check_violation THEN RETURN jsonb_build_object('ok', false, 'error', 'Revisa los datos de la pregunta.');
  END;
  PERFORM f360_academy.admin_log(uid, 'item_save', i.id::text, jsonb_build_object('key', i.key, 'fields', (SELECT jsonb_agg(k) FROM jsonb_object_keys(f) k)));
  RETURN jsonb_build_object('ok', true);
END $$;

CREATE FUNCTION public.f360_academy_comment(p_version uuid, p_lesson_key text, p_item_key text, p_block int, p_body text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid();
BEGIN
  IF NOT f360_academy.is_staff(uid) OR NOT EXISTS (SELECT 1 FROM f360_academy.course_versions WHERE id = p_version) THEN RETURN f360_academy.denied(); END IF;
  IF length(btrim(coalesce(p_body, ''))) NOT BETWEEN 2 AND 1000 THEN RETURN jsonb_build_object('ok', false, 'error', 'Escribe el comentario.'); END IF;
  INSERT INTO f360_academy.review_comments (course_version_id, lesson_key, item_key, block_index, body, by_user, by_name)
  VALUES (p_version, p_lesson_key, p_item_key, p_block, btrim(p_body), uid, f360_academy.caller_name(uid));
  RETURN jsonb_build_object('ok', true);
END $$;

-- New draft = copy of the latest version (published or not), version + 1.
CREATE FUNCTION public.f360_academy_new_draft(p_course uuid) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid(); src f360_academy.course_versions; nv uuid;
BEGIN
  IF NOT f360_academy.is_editor(uid) THEN RETURN f360_academy.denied(); END IF;
  IF EXISTS (SELECT 1 FROM f360_academy.course_versions WHERE course_id = p_course AND status IN ('borrador', 'en_revision')) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Ya hay un borrador o una versión en revisión de este curso.');
  END IF;
  SELECT * INTO src FROM f360_academy.course_versions WHERE course_id = p_course ORDER BY version DESC LIMIT 1;
  IF src.id IS NULL THEN RETURN f360_academy.denied(); END IF;
  INSERT INTO f360_academy.course_versions (course_id, version, title, summary, created_by_name)
  VALUES (p_course, src.version + 1, src.title, src.summary, f360_academy.caller_name(uid)) RETURNING id INTO nv;
  INSERT INTO f360_academy.lessons (course_version_id, key, position, title, minutes, blocks, product_codes)
  SELECT nv, key, position, title, minutes, blocks, product_codes FROM f360_academy.lessons WHERE course_version_id = src.id;
  INSERT INTO f360_academy.items (course_version_id, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code, status)
  SELECT nv, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code, status FROM f360_academy.items WHERE course_version_id = src.id;
  PERFORM f360_academy.admin_log(uid, 'new_draft', nv::text, jsonb_build_object('from', src.version));
  RETURN jsonb_build_object('ok', true, 'id', nv);
END $$;

-- Submit: validate, freeze validated product snapshots, hash, open the approval request.
CREATE FUNCTION public.f360_academy_submit(p_version uuid, p_reason text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid(); v f360_academy.course_versions; c f360_academy.courses; l record; missing text; h text; rid uuid; op text;
BEGIN
  IF NOT f360_academy.is_editor(uid) THEN RETURN f360_academy.denied(); END IF;
  SELECT * INTO v FROM f360_academy.course_versions WHERE id = p_version FOR UPDATE;
  SELECT * INTO c FROM f360_academy.courses WHERE id = v.course_id;
  IF v.id IS NULL THEN RETURN f360_academy.denied(); END IF;
  IF c.school <> 'sales' THEN RETURN jsonb_build_object('ok', false, 'error', 'La Escuela Ejecutiva no se publica en A1.'); END IF;
  IF v.status <> 'borrador' THEN RETURN jsonb_build_object('ok', false, 'error', 'Solo un borrador se envía a revisión.'); END IF;
  IF length(btrim(coalesce(p_reason, ''))) < 3 THEN RETURN jsonb_build_object('ok', false, 'error', 'Escribe qué cambió o por qué se envía.'); END IF;
  IF NOT EXISTS (SELECT 1 FROM f360_academy.lessons WHERE course_version_id = v.id) THEN RETURN jsonb_build_object('ok', false, 'error', 'El curso no tiene lecciones.'); END IF;
  SELECT string_agg(l2.key, ', ') INTO missing FROM f360_academy.lessons l2
   WHERE l2.course_version_id = v.id AND EXISTS (SELECT 1 FROM jsonb_array_elements(l2.blocks) b WHERE b->>'type' = 'pendiente');
  IF missing IS NOT NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'Hay tarjetas pendientes de Carolina en: ' || missing || '.'); END IF;
  SELECT string_agg(i.key, ', ') INTO missing FROM f360_academy.items i
   WHERE i.course_version_id = v.id AND i.status = 'ok' AND (length(btrim(i.explanation)) < 3 OR length(btrim(i.source)) < 3);
  IF missing IS NOT NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'Preguntas sin explicación o fuente: ' || missing || '.'); END IF;
  -- every block that names a model must point to a code listed in its lesson, and every listed model must have validated knowledge
  FOR l IN SELECT * FROM f360_academy.lessons WHERE course_version_id = v.id LOOP
    SELECT string_agg(b->>'code', ', ') INTO missing FROM jsonb_array_elements(l.blocks) b
     WHERE b->>'type' IN ('ficha', 'ficha_talla') AND NOT ((b->>'code') = ANY (l.product_codes));
    IF missing IS NOT NULL THEN RETURN jsonb_build_object('ok', false, 'error', format('En %s hay fichas que no están en su lista de modelos: %s.', l.key, missing)); END IF;
    SELECT string_agg(x, ', ') INTO missing FROM unnest(l.product_codes) x WHERE f360_academy.product_card(x) IS NULL;
    IF missing IS NOT NULL THEN RETURN jsonb_build_object('ok', false, 'error', format('En %s hay modelos sin ficha validada o inactivos: %s.', l.key, missing)); END IF;
    UPDATE f360_academy.lessons SET product_snapshot = coalesce((SELECT jsonb_object_agg(x, f360_academy.product_card(x)) FROM unnest(product_codes) x), '{}')
     WHERE id = l.id;
  END LOOP;
  SELECT string_agg(i.key, ', ') INTO missing FROM f360_academy.items i
   WHERE i.course_version_id = v.id AND i.product_code IS NOT NULL AND f360_academy.product_card(i.product_code) IS NULL;
  IF missing IS NOT NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'Preguntas sobre modelos sin ficha validada: ' || missing || '.'); END IF;
  op := CASE WHEN EXISTS (SELECT 1 FROM f360_academy.lessons l3, jsonb_array_elements(l3.blocks) b WHERE l3.course_version_id = v.id AND b->>'type' = 'politica')
             THEN 'publish_sales_policy' ELSE 'publish_sales' END;
  h := f360_academy.version_hash(v.id);
  rid := f360.approval_request('academy_content', op, 'academy.course_version', v.id, v.version, h, NULL,
    jsonb_build_object('course', c.key, 'title', v.title, 'lessons', (SELECT count(*) FROM f360_academy.lessons WHERE course_version_id = v.id)),
    p_reason, uid, f360_academy.caller_name(uid));
  UPDATE f360_academy.course_versions SET status = 'en_revision', content_hash = h, approval_request_id = rid, submitted_at = clock_timestamp() WHERE id = v.id;
  PERFORM f360_academy.admin_log(uid, 'submit', v.id::text, jsonb_build_object('request', rid, 'operation', op, 'hash', h));
  RETURN jsonb_build_object('ok', true, 'request_id', rid, 'operation', op, 'hash', h);
END $$;

-- Decide (approver, aal2). Approve → consume + publish in the same transaction. Reject → back to draft (new request on resubmit).
CREATE FUNCTION public.f360_academy_decide(p_version uuid, p_approve boolean, p_reason text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid(); v f360_academy.course_versions; r f360.approval_requests; d jsonb; h text; nm text;
BEGIN
  IF NOT f360_academy.is_content_approver(uid) THEN RETURN f360_academy.denied(); END IF;
  SELECT * INTO v FROM f360_academy.course_versions WHERE id = p_version FOR UPDATE;
  IF v.id IS NULL OR v.status <> 'en_revision' OR v.approval_request_id IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'Esta versión no está en revisión.'); END IF;
  SELECT * INTO r FROM f360.approval_requests WHERE id = v.approval_request_id;
  nm := f360_academy.caller_name(uid);
  h := f360_academy.version_hash(v.id);
  d := f360.approval_decide(r.id, coalesce(p_approve, false), h, uid, nm, p_reason);
  IF NOT (d->>'ok')::boolean THEN
    IF (SELECT status FROM f360.approval_requests WHERE id = r.id) IN ('invalidated', 'expired') THEN
      UPDATE f360_academy.course_versions SET status = 'borrador', content_hash = NULL WHERE id = v.id;
    END IF;
    RETURN d;
  END IF;
  IF d->>'status' = 'rejected' THEN
    UPDATE f360_academy.course_versions SET status = 'borrador', content_hash = NULL WHERE id = v.id;
    PERFORM f360_academy.admin_log(uid, 'reject', v.id::text, jsonb_build_object('request', r.id));
    RETURN jsonb_build_object('ok', true, 'status', 'rechazado');
  END IF;
  IF NOT f360.approval_consume(r.id, 'academy_content', r.operation, 'academy.course_version', v.id, v.version, h, uid, nm) THEN
    RAISE EXCEPTION 'La aprobación no se pudo usar (cambió o venció).';
  END IF;
  UPDATE f360_academy.course_versions SET status = 'retirado', retired_at = clock_timestamp() WHERE course_id = v.course_id AND status = 'publicado';
  UPDATE f360_academy.course_versions SET status = 'publicado', published_at = clock_timestamp() WHERE id = v.id;
  UPDATE f360_academy.courses SET published_version_id = v.id WHERE id = v.course_id;
  PERFORM f360_academy.admin_log(uid, 'publish', v.id::text, jsonb_build_object('request', r.id, 'self_approval', d->'self_approval'));
  RETURN jsonb_build_object('ok', true, 'status', 'publicado', 'self_approval', d->'self_approval');
END $$;

-- Individual progress per learner and store (staff only).
CREATE FUNCTION public.f360_academy_team() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid();
BEGIN
  IF NOT f360_academy.is_staff(uid) THEN RETURN f360_academy.denied(); END IF;
  RETURN jsonb_build_object('ok', true, 'learners', coalesce((
    SELECT jsonb_agg(jsonb_build_object('name', f360_academy.caller_name(e.auth_user_id),
      'store', (SELECT name FROM f360.locations WHERE id = e.location_id), 'course', v.title, 'version', v.version,
      'enrolled_at', e.enrolled_at, 'completed_at', e.completed_at,
      'lessons_total', (SELECT count(*) FROM f360_academy.lessons l WHERE l.course_version_id = v.id),
      'lessons_done', (SELECT count(*) FROM f360_academy.lesson_progress p JOIN f360_academy.lessons l ON l.id = p.lesson_id
                        WHERE p.auth_user_id = e.auth_user_id AND l.course_version_id = v.id AND p.status = 'completada'),
      'practice', (SELECT jsonb_build_object('answered', count(*), 'correct', count(*) FILTER (WHERE a.correct)) FROM f360_academy.attempts a
                    JOIN f360_academy.items i ON i.id = a.item_id WHERE a.auth_user_id = e.auth_user_id AND i.course_version_id = v.id),
      'tester', f360_academy.has_grant(e.auth_user_id, 'tester')) ORDER BY e.enrolled_at)
    FROM f360_academy.enrollments e JOIN f360_academy.course_versions v ON v.id = e.course_version_id
    JOIN f360_academy.courses c ON c.id = e.course_id WHERE c.school = 'sales'), '[]'));
END $$;

-- ── Privileges ───────────────────────────────────────────────────────────────────────────────────────────────────────────────
DO $$ DECLARE t text; BEGIN
  FOR t IN SELECT format('%I.%I', schemaname, tablename) FROM pg_tables WHERE schemaname = 'f360_academy' LOOP
    EXECUTE format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY', t);
  END LOOP;
END $$;
REVOKE ALL ON ALL TABLES IN SCHEMA f360_academy FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA f360_academy FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA f360_academy FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.f360_academy_me(), public.f360_academy_home(), public.f360_academy_lesson(uuid),
  public.f360_academy_progress_save(uuid, int, boolean), public.f360_academy_answer(uuid, jsonb), public.f360_academy_fichas(),
  public.f360_academy_admin_overview(), public.f360_academy_admin_version(uuid), public.f360_academy_lesson_save(uuid, text, int, jsonb, text[]),
  public.f360_academy_item_save(uuid, jsonb), public.f360_academy_comment(uuid, text, text, int, text), public.f360_academy_new_draft(uuid),
  public.f360_academy_submit(uuid, text), public.f360_academy_decide(uuid, boolean, text), public.f360_academy_team() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_academy_me(), public.f360_academy_home(), public.f360_academy_lesson(uuid),
  public.f360_academy_progress_save(uuid, int, boolean), public.f360_academy_answer(uuid, jsonb), public.f360_academy_fichas(),
  public.f360_academy_admin_overview(), public.f360_academy_admin_version(uuid), public.f360_academy_lesson_save(uuid, text, int, jsonb, text[]),
  public.f360_academy_item_save(uuid, jsonb), public.f360_academy_comment(uuid, text, text, int, text), public.f360_academy_new_draft(uuid),
  public.f360_academy_submit(uuid, text), public.f360_academy_decide(uuid, boolean, text), public.f360_academy_team() TO authenticated;
