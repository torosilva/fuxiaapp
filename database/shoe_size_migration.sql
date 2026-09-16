-- Agrega la talla al perfil de la clienta.
--
-- Se guarda como TEXT (no INTEGER) porque manejamos medias tallas y algunas
-- clientas prefieren rangos ('24-25'). Nulable — no es obligatoria.
--
-- Cumpleaños sin año: cuando la clienta ingresa DD/MM (sin AAAA), la app
-- guarda `birthday` con año centinela 1900 (ej: 1900-08-25). Con eso no hace
-- falta cambiar el schema del tipo DATE; solo hay que ignorar el año al
-- comparar contra la fecha actual para mandar el saludo. No hace falta
-- migración para esto.

ALTER TABLE public.customers
  ADD COLUMN IF NOT EXISTS shoe_size TEXT;

COMMENT ON COLUMN public.customers.shoe_size IS
  'Talla mexicana declarada por la clienta (ej: "24", "24.5", "26"). Nullable.';
