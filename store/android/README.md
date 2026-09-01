# Assets de la ficha de Google Play

## feature-graphic.png — 1024×500

Obligatorio para publicar. Apple no pide un equivalente, por eso no existía.

Se ve arriba de todo en la ficha de Play y en secciones destacadas. Google puede
recortarlo en algunos formatos, así que el texto y el logo están sobre el tercio
izquierdo, lejos de los bordes.

### Regenerarlo

La fuente es `feature-graphic.src.html`, con el logo y la foto embebidos como
data URI (no depende de archivos externos). Para re-renderizar con cualquier
Chromium headless:

```bash
chrome --headless --no-sandbox --hide-scrollbars \
  --force-device-scale-factor=1 --window-size=1024,500 \
  --screenshot=feature-graphic.png feature-graphic.src.html
```

Verificá siempre que el PNG salga de 1024×500 exactos: según el binario de
Chromium, la ventana puede no coincidir con el viewport y queda una banda negra
abajo. El binario `headless_shell` de Playwright no tiene ese problema.

## play-icon-512.png — 512×512

Obligatorio. Es el mismo icono de la app (`fuxia-native/assets/images/icon-brand.png`,
1024×1024) reducido a 512×512 y **aplanado a RGB, sin canal alfa**: Play redondea las
esquinas por su cuenta y un icono con transparencia le queda mal.

Se mantuvo idéntico al de iOS a propósito, para que la marca se vea igual en las dos
tiendas.

Regenerarlo: mismo comando que el feature graphic, con `--window-size=512,512` y
`play-icon-512.src.html`. Verificá que el PNG salga con color type 2 (RGB) y no 6 (RGBA):

```bash
python3 -c "d=open('play-icon-512.png','rb').read(); print('color type:', d[25])"
```

## Falta todavía

- **Screenshots de teléfono** — mínimo 4. Se pueden reusar los de iOS reencuadrados
  a 16:9 / 9:16.
