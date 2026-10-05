-- Fuxia 360 · CRO-3A — Product knowledge + fit, ONE structured source per MODEL. STAGING.
-- Decisions: Mario 2026-10-05 (Storefront V1 closeout; Carolina is the content authority; pilots = products already in F360).
-- Audit (docs/fuxia360/cro/STOREFRONT_V1_CLOSEOUT.md §CRO-3A): no equivalent fields existed. f360.products only has free-text
-- description / short_description (0/62 short descriptions); Hilo's KB made unvalidated claims. This table is the source for
-- storefront PDP, Hilo, seller app, admin and Customer 360 / merchandising. Woo stays the channel (no second PIM there).
--   * Keyed by f360.products (id + immutable code): promotable to production as-is (no re-capture by Carolina).
--   * borrador → validado: only an owner validates; only VALIDATED knowledge is exposed to channels (f360.product_knowledge_public).
--     Any later edit by a non-owner returns it to borrador (must be re-validated). Every save is snapshotted (append-only).
-- Rollback: supabase/rollbacks/20261010000500_f360_product_knowledge.down.sql

CREATE TABLE f360.product_knowledge (
  product_id            uuid PRIMARY KEY REFERENCES f360.products(id) ON DELETE CASCADE,
  fit_category          text CHECK (fit_category IN ('true_to_size', 'runs_small', 'runs_large')),
  between_sizes         text CHECK (between_sizes IN ('mayor', 'menor')),
  recommended_size_note text CHECK (length(recommended_size_note) <= 240),
  last_fit              text CHECK (last_fit IN ('comoda', 'normal', 'ajustada')),            -- horma
  width_fit             text CHECK (width_fit IN ('angosto', 'normal', 'amplio')),            -- solo cuando aplica
  material_upper        text CHECK (length(material_upper) <= 120),                         -- exterior / corte
  material_lining       text CHECK (length(material_lining) <= 120),                        -- forro
  material_sole         text CHECK (length(material_sole) <= 120),                          -- suela
  heel_height_cm        numeric(4,1) CHECK (heel_height_cm >= 0 AND heel_height_cm <= 20),   -- tacón o plataforma
  toe_type              text CHECK (toe_type IN ('redonda', 'almendrada', 'puntuda', 'cuadrada', 'abierta')),
  comfort_notes         text CHECK (length(comfort_notes) <= 400),
  care_instructions     text CHECK (length(care_instructions) <= 400),
  status                text NOT NULL DEFAULT 'borrador' CHECK (status IN ('borrador', 'validado')),
  validated_by          uuid, validated_by_name text, validated_at timestamptz,
  updated_by            uuid, updated_by_name text NOT NULL, updated_at timestamptz NOT NULL DEFAULT now(),
  version               integer NOT NULL DEFAULT 1,
  CONSTRAINT knowledge_validated_needs_fit CHECK (status <> 'validado' OR (fit_category IS NOT NULL AND validated_at IS NOT NULL))
);
ALTER TABLE f360.product_knowledge ENABLE ROW LEVEL SECURITY;
COMMENT ON TABLE f360.product_knowledge IS 'CRO-3A: structured product knowledge per MODEL (fit, last, materials, comfort, care). Single source for storefront, Hilo, seller app, admin. Only status=validado is exposed to channels.';

CREATE TABLE f360.product_knowledge_history (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  product_id  uuid NOT NULL,
  version     integer NOT NULL,
  action      text NOT NULL CHECK (action IN ('saved', 'validated', 'unvalidated')),
  snapshot    jsonb NOT NULL,
  by_auth_user uuid, by_name text NOT NULL,
  at          timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX product_knowledge_history_idx ON f360.product_knowledge_history (product_id, id DESC);
ALTER TABLE f360.product_knowledge_history ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER product_knowledge_history_append_only BEFORE UPDATE OR DELETE ON f360.product_knowledge_history
  FOR EACH ROW WHEN (pg_trigger_depth() = 0) EXECUTE FUNCTION f360.reject_audit_change();

-- Labels shown to customers (one place; storefront / Hilo / app reuse them).
CREATE FUNCTION f360.knowledge_labels() RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT jsonb_build_object(
    'fit_category', jsonb_build_object('true_to_size', 'Talla exacta', 'runs_small', 'Talla chica', 'runs_large', 'Talla grande'),
    'fit_advice', jsonb_build_object('true_to_size', 'Te recomendamos pedir tu talla habitual.',
                                     'runs_small', 'Te recomendamos pedir media talla más de tu talla habitual.',
                                     'runs_large', 'Te recomendamos pedir media talla menos de tu talla habitual.'),
    'between_sizes', jsonb_build_object('mayor', '¿Entre dos tallas? Elige la mayor.', 'menor', '¿Entre dos tallas? Elige la menor.'),
    'last_fit', jsonb_build_object('comoda', 'Cómoda', 'normal', 'Normal', 'ajustada', 'Ajustada'),
    'width_fit', jsonb_build_object('angosto', 'Angosto', 'normal', 'Normal', 'amplio', 'Amplio'),
    'toe_type', jsonb_build_object('redonda', 'Redonda', 'almendrada', 'Almendrada', 'puntuda', 'Puntuda', 'cuadrada', 'Cuadrada', 'abierta', 'Abierta'))
$$;

-- What channels may show: validated only, with customer-facing labels. NULL when nothing validated.
CREATE FUNCTION f360.product_knowledge_public(p_product uuid) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT CASE WHEN k.status = 'validado' THEN jsonb_strip_nulls(jsonb_build_object(
    'product_key', 'F360-' || p.code, 'version', k.version, 'validated_at', k.validated_at,
    'fit', jsonb_build_object('category', k.fit_category, 'label', l->'fit_category'->>k.fit_category, 'advice', l->'fit_advice'->>k.fit_category,
                              'between_sizes', l->'between_sizes'->>k.between_sizes, 'note', k.recommended_size_note),
    'last', l->'last_fit'->>k.last_fit, 'width', l->'width_fit'->>k.width_fit, 'toe', l->'toe_type'->>k.toe_type,
    'heel_height_cm', k.heel_height_cm,
    'materials', jsonb_strip_nulls(jsonb_build_object('upper', k.material_upper, 'lining', k.material_lining, 'sole', k.material_sole)),
    'comfort', k.comfort_notes, 'care', k.care_instructions)) END
  FROM f360.product_knowledge k JOIN f360.products p ON p.id = k.product_id, LATERAL (SELECT f360.knowledge_labels() l) x
  WHERE k.product_id = p_product
$$;

CREATE FUNCTION f360.knowledge_row(p_product uuid) RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT to_jsonb(k) - 'updated_by' - 'validated_by' FROM f360.product_knowledge k WHERE k.product_id = p_product
$$;

-- Admin: read (anyone with Fuxia 360 access).
CREATE FUNCTION public.f360_product_knowledge_get(p_product_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('viewer');
BEGIN
  IF NOT EXISTS (SELECT 1 FROM f360.products WHERE id = p_product_id) THEN RAISE EXCEPTION 'Producto no encontrado.'; END IF;
  RETURN jsonb_build_object('knowledge', f360.knowledge_row(p_product_id), 'public', f360.product_knowledge_public(p_product_id),
    'labels', f360.knowledge_labels(), 'can_validate', r.role = 'owner',
    'history', coalesce((SELECT jsonb_agg(jsonb_build_object('version', version, 'action', action, 'by', by_name, 'at', at) ORDER BY id DESC)
                         FROM (SELECT * FROM f360.product_knowledge_history WHERE product_id = p_product_id ORDER BY id DESC LIMIT 10) h), '[]'));
END $$;

-- Admin: save (operator+). p_fields = only the keys below; '' clears a field. p_validate = owner marks it validated.
CREATE FUNCTION public.f360_product_knowledge_save(p_product_id uuid, p_fields jsonb, p_validate boolean DEFAULT false) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('operator'); k f360.product_knowledge; bad text; f jsonb := coalesce(p_fields, '{}');
  allowed text[] := ARRAY['fit_category', 'between_sizes', 'recommended_size_note', 'last_fit', 'width_fit', 'material_upper', 'material_lining',
                          'material_sole', 'heel_height_cm', 'toe_type', 'comfort_notes', 'care_instructions'];
  t text := NULL; changed boolean;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM f360.products WHERE id = p_product_id) THEN RAISE EXCEPTION 'Producto no encontrado.'; END IF;
  IF jsonb_typeof(f) <> 'object' THEN RAISE EXCEPTION 'Datos no válidos.'; END IF;
  SELECT string_agg(key, ', ') INTO bad FROM jsonb_object_keys(f) key WHERE key <> ALL (allowed);
  IF bad IS NOT NULL THEN RAISE EXCEPTION 'Campos no permitidos: %.', bad; END IF;
  IF coalesce(p_validate, false) AND r.role <> 'owner' THEN RAISE EXCEPTION 'Solo una dueña puede validar la información del producto.'; END IF;

  INSERT INTO f360.product_knowledge (product_id, updated_by, updated_by_name, version) VALUES (p_product_id, r.auth_user_id, r.display_name, 0)
    ON CONFLICT (product_id) DO NOTHING;
  SELECT * INTO k FROM f360.product_knowledge WHERE product_id = p_product_id FOR UPDATE;

  -- '' → NULL; text trimmed; numbers parsed. Unknown enum values are rejected by the CHECKs (clear Spanish message below).
  BEGIN
    UPDATE f360.product_knowledge SET
      fit_category = CASE WHEN f ? 'fit_category' THEN nullif(btrim(f->>'fit_category'), '') ELSE fit_category END,
      between_sizes = CASE WHEN f ? 'between_sizes' THEN nullif(btrim(f->>'between_sizes'), '') ELSE between_sizes END,
      recommended_size_note = CASE WHEN f ? 'recommended_size_note' THEN nullif(btrim(f->>'recommended_size_note'), '') ELSE recommended_size_note END,
      last_fit = CASE WHEN f ? 'last_fit' THEN nullif(btrim(f->>'last_fit'), '') ELSE last_fit END,
      width_fit = CASE WHEN f ? 'width_fit' THEN nullif(btrim(f->>'width_fit'), '') ELSE width_fit END,
      material_upper = CASE WHEN f ? 'material_upper' THEN nullif(btrim(f->>'material_upper'), '') ELSE material_upper END,
      material_lining = CASE WHEN f ? 'material_lining' THEN nullif(btrim(f->>'material_lining'), '') ELSE material_lining END,
      material_sole = CASE WHEN f ? 'material_sole' THEN nullif(btrim(f->>'material_sole'), '') ELSE material_sole END,
      heel_height_cm = CASE WHEN f ? 'heel_height_cm' THEN nullif(btrim(f->>'heel_height_cm'), '')::numeric ELSE heel_height_cm END,
      toe_type = CASE WHEN f ? 'toe_type' THEN nullif(btrim(f->>'toe_type'), '') ELSE toe_type END,
      comfort_notes = CASE WHEN f ? 'comfort_notes' THEN nullif(btrim(f->>'comfort_notes'), '') ELSE comfort_notes END,
      care_instructions = CASE WHEN f ? 'care_instructions' THEN nullif(btrim(f->>'care_instructions'), '') ELSE care_instructions END
    WHERE product_id = p_product_id;
  EXCEPTION
    WHEN check_violation THEN RAISE EXCEPTION 'Revisa los datos: un valor no es válido o el texto es demasiado largo.';
    WHEN invalid_text_representation THEN RAISE EXCEPTION 'La altura del tacón debe ser un número (cm).';
  END;

  SELECT (to_jsonb(n) - 'status' - 'validated_by' - 'validated_by_name' - 'validated_at' - 'updated_by' - 'updated_by_name' - 'updated_at' - 'version')
         IS DISTINCT FROM (to_jsonb(k) - 'status' - 'validated_by' - 'validated_by_name' - 'validated_at' - 'updated_by' - 'updated_by_name' - 'updated_at' - 'version')
    INTO changed FROM f360.product_knowledge n WHERE n.product_id = p_product_id;

  IF coalesce(p_validate, false) THEN
    IF (SELECT fit_category FROM f360.product_knowledge WHERE product_id = p_product_id) IS NULL THEN
      RAISE EXCEPTION 'Para validar, primero elige cómo queda la talla (exacta, chica o grande).';
    END IF;
    UPDATE f360.product_knowledge SET status = 'validado', validated_by = r.auth_user_id, validated_by_name = r.display_name, validated_at = now()
      WHERE product_id = p_product_id;
    t := 'validated';
  ELSIF changed AND k.status = 'validado' AND r.role <> 'owner' THEN
    UPDATE f360.product_knowledge SET status = 'borrador', validated_by = NULL, validated_by_name = NULL, validated_at = NULL WHERE product_id = p_product_id;
    t := 'unvalidated';
  END IF;
  IF NOT changed AND t IS NULL AND k.version > 0 THEN
    RETURN public.f360_product_knowledge_get(p_product_id);                        -- nothing changed: no new version
  END IF;
  UPDATE f360.product_knowledge SET version = k.version + 1, updated_by = r.auth_user_id, updated_by_name = r.display_name, updated_at = now()
    WHERE product_id = p_product_id;
  INSERT INTO f360.product_knowledge_history (product_id, version, action, snapshot, by_auth_user, by_name)
    VALUES (p_product_id, k.version + 1, coalesce(t, 'saved'), f360.knowledge_row(p_product_id), r.auth_user_id, r.display_name);
  RETURN public.f360_product_knowledge_get(p_product_id);
END $$;

-- Admin overview: pilot progress per model (no free text).
CREATE FUNCTION public.f360_product_knowledge_overview() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('viewer');
BEGIN
  RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('product_id', p.id, 'name', p.name, 'code', p.code, 'status', coalesce(k.status, 'sin_datos'),
      'filled', (SELECT count(*) FROM jsonb_each(coalesce(to_jsonb(k), '{}')) e WHERE e.key IN ('fit_category', 'between_sizes', 'recommended_size_note', 'last_fit',
                 'width_fit', 'material_upper', 'material_lining', 'material_sole', 'heel_height_cm', 'toe_type', 'comfort_notes', 'care_instructions')
                 AND e.value <> 'null'::jsonb),
      'validated_by', k.validated_by_name, 'updated_at', k.updated_at) ORDER BY (k.status = 'validado') DESC NULLS LAST, p.name)
    FROM f360.products p LEFT JOIN f360.product_knowledge k ON k.product_id = p.id WHERE p.status <> 'archived'), '[]');
END $$;

REVOKE ALL ON f360.product_knowledge, f360.product_knowledge_history FROM PUBLIC, anon, authenticated;
GRANT SELECT ON f360.product_knowledge, f360.product_knowledge_history TO service_role;
REVOKE ALL ON FUNCTION f360.knowledge_labels(), f360.product_knowledge_public(uuid), f360.knowledge_row(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION f360.knowledge_labels(), f360.product_knowledge_public(uuid) TO service_role;
REVOKE ALL ON FUNCTION public.f360_product_knowledge_get(uuid), public.f360_product_knowledge_save(uuid, jsonb, boolean),
  public.f360_product_knowledge_overview() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_product_knowledge_get(uuid), public.f360_product_knowledge_save(uuid, jsonb, boolean),
  public.f360_product_knowledge_overview() TO authenticated;
