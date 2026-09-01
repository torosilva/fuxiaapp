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

## Falta todavía

- **Icono 512×512** — derivar de `fuxia-native/assets/images/icon-brand.png`
  (es 1024×1024 PNG RGBA). Play lo pide sin transparencia.
- **Screenshots de teléfono** — mínimo 4. Se pueden reusar los de iOS reencuadrados
  a 16:9 / 9:16.
