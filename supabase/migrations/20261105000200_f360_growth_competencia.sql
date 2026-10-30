-- Growth · Competencia (Mario 2026-10-30: "me habías puesto una tabla con mi competencia y ya no la veo").
--   · f360.competitors: the brands we watch. f360.competitor_observations: dated observations (followers, active ads in the Meta
--     Ad Library, price band, channels, how they advertise), each with its source. Nothing is overwritten: every week is a new row,
--     so the screen shows the change.
--   · Seed: the analysis of 2026-10-27 (Meta Ad Library by keyword → ad counts are approximate; "NV" = not verified → NULL).
--   · public.f360_growth_competencia() (operator) and public.f360_competitor_observe() (owner) to record a new observation.
-- Rollback: supabase/rollbacks/20261105000200_f360_growth_competencia.down.sql

CREATE TABLE f360.competitors (
  key        text PRIMARY KEY CHECK (key ~ '^[a-z0-9-]{2,40}$'),
  name       text NOT NULL CHECK (length(btrim(name)) BETWEEN 2 AND 80),
  origin     text CHECK (origin IS NULL OR length(origin) <= 80),
  url        text CHECK (url IS NULL OR url ~ '^https://[^\s]{4,200}$'),
  ig_handle  text CHECK (ig_handle IS NULL OR ig_handle ~ '^[A-Za-z0-9._]{2,30}$'),
  is_self    boolean NOT NULL DEFAULT false,
  sort       smallint NOT NULL DEFAULT 100,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE f360.competitor_observations (
  id               bigserial PRIMARY KEY,
  competitor_key   text NOT NULL REFERENCES f360.competitors(key) ON DELETE RESTRICT,
  observed_on      date NOT NULL,
  followers_ig     integer CHECK (followers_ig IS NULL OR followers_ig >= 0),
  active_ads_meta  integer CHECK (active_ads_meta IS NULL OR active_ads_meta >= 0),
  ads_approx       boolean NOT NULL DEFAULT true,
  price_text       text CHECK (price_text IS NULL OR length(price_text) <= 300),
  channels         text CHECK (channels IS NULL OR length(channels) <= 300),
  how_they_advertise text CHECK (how_they_advertise IS NULL OR length(how_they_advertise) <= 1500),
  source           text NOT NULL CHECK (length(btrim(source)) BETWEEN 3 AND 300),
  recorded_by_name text NOT NULL,
  recorded_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (competitor_key, observed_on)
);
COMMENT ON TABLE f360.competitor_observations IS 'Growth Competencia: dated public observations of competitor brands (followers, Meta Ad Library counts, prices). One row per brand per day; history is kept.';

INSERT INTO f360.competitors (key, name, origin, url, is_self, sort) VALUES
  ('fuxia', 'Fuxia', 'MX / CO', 'https://fuxiaballerinas.com', true, 0),
  ('regina-romero', 'Regina Romero', 'MX, desde 1984', 'https://reginaromero.com', false, 10),
  ('bala-di-gala', 'Bala Di Gala', 'MX, hecho a mano', 'https://baladigala.com.mx', false, 20),
  ('dione', 'Dione', 'MX', 'https://dione.com.mx', false, 30),
  ('goroshus', 'Goroshus', 'MX', 'https://goroshus.com', false, 40),
  ('loly-in-the-sky', 'Loly in the Sky', 'MX, León', 'https://lolyinthesky.com.mx', false, 50),
  ('milamilu', 'MilaMilu', 'MX, Guadalajara', 'https://milamilu.com', false, 60),
  ('pretty-ballerinas', 'Pretty Ballerinas', 'España', 'https://prettyballerinas.com', false, 70),
  ('flamingos-life', 'Flamingos'' Life', 'España', 'https://flamingoslife.com', false, 80),
  ('bimba-y-lola', 'Bimba y Lola', 'España', 'https://bimbaylola.com', false, 90),
  ('roth-malere', 'Roth Malère', 'MX, lujo', 'https://rothmalere.com', false, 95);

INSERT INTO f360.competitor_observations (competitor_key, observed_on, followers_ig, active_ads_meta, price_text, channels, how_they_advertise, source, recorded_by_name) VALUES
  ('fuxia', '2026-10-27', 99000, 5, '2,800–4,500 MXN', 'Sitio propio',
   '3 de los 5 anuncios mandan al perfil de Instagram o piden "Comenta FUXIA y te mandamos el link"; solo 2 llevan a la tienda. Ninguno menciona meses sin intereses, envío gratis, cambio de talla ni precio.',
   'Biblioteca de anuncios de Meta (búsqueda por palabra, conteo aproximado) y perfil de Instagram, 27 oct 2026', 'Análisis de competencia (Claude)'),
  ('regina-romero', '2026-10-27', 211000, 100, 'Flats y loafers de 2,000 (rebaja) a 4,599 MXN; mediana del catálogo 3,899', 'Sitio, Palacio de Hierro, Liverpool, boutiques en Lomas y Roma (CDMX)',
   'Video corto (3–31 s), carrusel y catálogo con precio tachado. Mensajes: "Hechos a mano en México desde 1984", hasta 6 MSI, envío gratis desde $1,500, recuperación de carrito con reseña de clienta. Del 11 sep al 10 oct corrió "THE FINAL EDIT": pares a $2,000 y $2,500 con envío gratis. Lleva a la página de producto.',
   'Biblioteca de anuncios de Meta (búsqueda por palabra, conteo aproximado), sitio y perfil de Instagram, 27 oct 2026', 'Análisis de competencia (Claude)'),
  ('bala-di-gala', '2026-10-27', 190000, 110, 'Botines en Palacio a 3,990 MXN; clog Penny en promoción a 1,000; sitio en USD 169–349', 'Sitio MX y sitio en USD, Palacio de Hierro, TikTok @baladigala',
   'Muchos videos cortos, uno o dos por modelo. Le habla a un dolor concreto ("tu western necesita contraste", "Ojo con el fit"). Repite "Envío gratis + primer cambio de talla sin costo" y "Hecho a mano en México". Escasez: "1,000 Penny''s a $1,000" (código PENNY1000). Colaboración FLUX MITS x BDG. Lleva a su tienda.',
   'Biblioteca de anuncios de Meta (búsqueda por palabra, conteo aproximado), sitio y perfil de Instagram, 27 oct 2026', 'Análisis de competencia (Claude)'),
  ('dione', '2026-10-27', 61000, 32, 'Ballerinas de piel de 2,094 a 3,490 MXN (Sandy y Margot 2,990; Aurielle 3,490)', 'Sitio, boutiques (según su sitio), TikTok @dione_moda',
   'Lanzamiento de la colección OI26: más de 20 anuncios entre el 21 y el 26 de octubre, videos con hashtags (#ballerinas). Gancho: 10% en la primera compra. Un anuncio en alianza con una creadora (Ciara Gómez Ibarra). Reseñas con Judge.me. Lleva a su tienda.',
   'Biblioteca de anuncios de Meta (búsqueda por palabra, conteo aproximado), sitio y perfil de Instagram, 27 oct 2026', 'Análisis de competencia (Claude)'),
  ('goroshus', '2026-10-27', 26000, NULL, 'Flats de 830 a 998 MXN', 'Sitio', NULL, 'Sitio y perfil de Instagram, 27 oct 2026; anuncios no revisados', 'Análisis de competencia (Claude)'),
  ('loly-in-the-sky', '2026-10-27', 416000, NULL, NULL, 'Sitio', NULL, 'Perfil de Instagram, 27 oct 2026; precios y anuncios no verificados', 'Análisis de competencia (Claude)'),
  ('milamilu', '2026-10-27', 51000, NULL, '599–3,800 MXN (mules 1,300)', 'Sitio', 'Su producto más reciente es de diciembre de 2025.', 'Sitio y perfil de Instagram, 27 oct 2026; anuncios no revisados', 'Análisis de competencia (Claude)'),
  ('pretty-ballerinas', '2026-10-27', 179000, NULL, '99–229 € (≈2,100–4,900 MXN)', 'Tienda propia en México según Modaes (no verificado)', NULL, 'Sitio y perfil de Instagram, 27 oct 2026; anuncios no revisados', 'Análisis de competencia (Claude)'),
  ('flamingos-life', '2026-10-27', 147000, NULL, NULL, 'Sitio', NULL, 'Perfil de Instagram, 27 oct 2026; precios y anuncios no verificados', 'Análisis de competencia (Claude)'),
  ('bimba-y-lola', '2026-10-27', 2000000, NULL, NULL, 'Presencia en México no verificada', NULL, 'Perfil de Instagram, 27 oct 2026', 'Análisis de competencia (Claude)'),
  ('roth-malere', '2026-10-27', NULL, NULL, '8,550–12,500 MXN, sin flats', 'Sitio', NULL, 'Sitio, 27 oct 2026', 'Análisis de competencia (Claude)');

CREATE FUNCTION public.f360_growth_competencia() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('operator'); res jsonb;
BEGIN
  SELECT coalesce(jsonb_agg(jsonb_build_object('key', c.key, 'name', c.name, 'origin', c.origin, 'url', c.url, 'is_self', c.is_self,
      'latest', (SELECT to_jsonb(o) - 'id' FROM f360.competitor_observations o WHERE o.competitor_key = c.key ORDER BY o.observed_on DESC LIMIT 1),
      'previous', (SELECT jsonb_build_object('observed_on', o.observed_on, 'followers_ig', o.followers_ig, 'active_ads_meta', o.active_ads_meta)
                   FROM f360.competitor_observations o WHERE o.competitor_key = c.key ORDER BY o.observed_on DESC OFFSET 1 LIMIT 1)
    ) ORDER BY c.sort), '[]') INTO res FROM f360.competitors c;
  RETURN jsonb_build_object('brands', res, 'can_record', r.role = 'owner',
    'notes', jsonb_build_array(
      'Anuncios activos: Biblioteca de anuncios de Meta (facebook.com/ads/library), país México. Busca por palabra, así que el número es aproximado.',
      'Seguidores: el número que muestra el perfil de Instagram ese día.',
      'Vacío = no se revisó o no se pudo verificar. Nunca es 0.'));
END $$;

-- Owner records one brand's observation for a day (a second save the same day replaces that day's row).
CREATE FUNCTION public.f360_competitor_observe(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('owner'); k text; d date;
BEGIN
  IF jsonb_typeof(p) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'Datos no válidos.'; END IF;
  FOR k IN SELECT jsonb_object_keys(p) LOOP
    IF k NOT IN ('competitor_key', 'observed_on', 'followers_ig', 'active_ads_meta', 'price_text', 'channels', 'how_they_advertise', 'source') THEN RAISE EXCEPTION 'Campo no permitido: %', k; END IF;
  END LOOP;
  d := coalesce((p->>'observed_on')::date, (now() AT TIME ZONE 'America/Mexico_City')::date);
  IF d > (now() AT TIME ZONE 'America/Mexico_City')::date THEN RAISE EXCEPTION 'La fecha no puede ser futura.'; END IF;
  INSERT INTO f360.competitor_observations (competitor_key, observed_on, followers_ig, active_ads_meta, price_text, channels, how_they_advertise, source, recorded_by_name)
  VALUES (p->>'competitor_key', d, nullif(p->>'followers_ig', '')::int, nullif(p->>'active_ads_meta', '')::int, nullif(btrim(p->>'price_text'), ''),
          nullif(btrim(p->>'channels'), ''), nullif(btrim(p->>'how_they_advertise'), ''), coalesce(nullif(btrim(p->>'source'), ''), 'Revisión manual'), r.display_name)
  ON CONFLICT (competitor_key, observed_on) DO UPDATE SET followers_ig = EXCLUDED.followers_ig, active_ads_meta = EXCLUDED.active_ads_meta,
    price_text = coalesce(EXCLUDED.price_text, f360.competitor_observations.price_text), channels = coalesce(EXCLUDED.channels, f360.competitor_observations.channels),
    how_they_advertise = coalesce(EXCLUDED.how_they_advertise, f360.competitor_observations.how_they_advertise),
    source = EXCLUDED.source, recorded_by_name = EXCLUDED.recorded_by_name, recorded_at = now();
  RETURN jsonb_build_object('ok', true);
END $$;

ALTER TABLE f360.competitors ENABLE ROW LEVEL SECURITY;
ALTER TABLE f360.competitor_observations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON f360.competitors, f360.competitor_observations FROM PUBLIC, anon, authenticated;
GRANT ALL ON f360.competitors, f360.competitor_observations TO service_role;
GRANT USAGE ON SEQUENCE f360.competitor_observations_id_seq TO service_role;
REVOKE ALL ON FUNCTION public.f360_growth_competencia(), public.f360_competitor_observe(jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.f360_growth_competencia(), public.f360_competitor_observe(jsonb) TO authenticated, service_role;
