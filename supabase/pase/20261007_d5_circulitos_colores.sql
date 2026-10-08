-- Fuxia 360 · pase D5 (2026-10-07) — circulito para los colores EN VIVO que no tenían (Mario: "ponlo tú").
-- El selector de color de la tienda dibuja el círculo que se elige en Fuxia 360 ("Cambiar circulito"); 14 colores no tenían.
-- Se pone un tono sugerido por nombre (combinaciones de dos colores: el tono principal). Carolina puede cambiar cualquiera
-- desde la ficha del modelo y se ve al instante en la tienda. Solo colores SIN circulito (nunca se pisa uno elegido).
-- Mismo camino que el admin (f360_set_color_hex), como Mario. Aplicar SOLO con scripts/f360/prod_sql.sh.
BEGIN;
SELECT set_config('request.jwt.claims', json_build_object('sub', 'd11a8d33-cae6-46a5-9d0f-bd2516e8712b', 'role', 'authenticated')::text, true);
CREATE TEMP TABLE d5 (modelo text, color text, hex text) ON COMMIT DROP;
INSERT INTO d5 VALUES
  ('Paula', 'Dorada con plata', '#C9A94E'), ('Paula', 'Plata con dorado', '#C0C0C0'),
  ('Sueco cucarrón', 'Azul', '#2B4C7E'), ('Mafalda Láser', 'Azul', '#2B4C7E'),
  ('Mafalda taches gamuza', 'Terracota', '#B4583A'), ('Leather Loafers', 'Beige', '#D9C3A5'),
  ('Tacon mule cruzado', 'Plateado', '#BFC1C2'), ('Sandalia flip flop con canutillos', 'Plateado', '#BFC1C2'),
  ('Peep toe', 'Topo', '#8B7D6B'), ('Sandalia flat doble tira trenzada', 'Topo', '#8B7D6B'),
  ('Plataforma entrelazada', 'Plomo', '#6E7378'), ('Sandalia trapecio', 'Plomo', '#6E7378'),
  ('Plataforma Marcela', 'Negra', '#1C1A17'), ('Mule punta afilada con tacon', 'Champagne', '#E3D3B0');
SELECT public.f360_set_color_hex(c.id, d5.hex)
FROM d5 JOIN f360.products p ON p.name = d5.modelo AND p.status = 'active'
JOIN f360.product_colors c ON c.product_id = p.id AND c.name = d5.color
WHERE c.hex IS NULL;
SELECT jsonb_build_object('con_circulito', (SELECT count(*) FROM d5 JOIN f360.products p ON p.name = d5.modelo JOIN f360.product_colors c ON c.product_id = p.id AND c.name = d5.color WHERE c.hex IS NOT NULL),
  'esperados', (SELECT count(*) FROM d5));
COMMIT;
