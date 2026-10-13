# Video de bienvenida de Fuxia Academy (vendedoras)

Mismo método que `../historia` y `../inversionistas`:
- animación HTML con `window.render(t)` y `window.DUR`;
- cuadros con Playwright;
- MP4 con AVFoundation;
- música con la pista de piano de `../historia`.

No usa ffmpeg ni voz. Guion y fuentes: `GUION_BIENVENIDA.md` (**borrador, requiere aprobación de Carolina**).

```bash
# 0 · fotos públicas de los 5 modelos del piloto → <img-dir>/<CODE>.jpg (≤ 900 px), p. ej. con sips -Z 900
# 1 · cuadros (1500 a 25 fps, 1080×1920, ~1 min)
node tools/video/academy/render.mjs <frames-dir> <img-dir>
# 2 · codificar (sin audio) y 3 · música (fade in 1.5 s, nivel 0.6, fade out 3 s; video sin recodificar)
swiftc -O tools/video/academy/encode.swift -o /tmp/encode && swiftc -O tools/video/academy/music.swift -o /tmp/music
/tmp/encode <frames-dir> silent_1080.mp4 1080 1920 1000000
/tmp/music  silent_1080.mp4 tools/video/historia/rockot-inspiring-piano-corporate-184592.mp3 fuxia-academy-bienvenida-1080x1920.mp4 0.6 1.5 3.0
/tmp/encode <frames-dir> silent_720.mp4 720 1280 650000
/tmp/music  silent_720.mp4  tools/video/historia/rockot-inspiring-piano-corporate-184592.mp3 fuxia-academy-bienvenida-720x1280.mp4 0.6 1.5 3.0
```

**Revisar cuadros sueltos:** `node tools/video/academy/render.mjs <out> <img-dir> 3,17,24,40,53.5,58`
