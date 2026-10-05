# Video demo de la tienda (staging4)

Graba el recorrido de una clienta en celular (iPhone 13), con letreros en español, y lo convierte a MP4 (H.264, 780×1688) para WhatsApp.
- Solo lee staging4: no compra, no paga y no manda formularios. La página de "Pedido recibido" es la del pedido de prueba #4114, con los datos personales difuminados.
- Inyecta en la grabación la versión más reciente de `tools/storefront/f360-compra.html` y el texto "10 días hábiles".

```
node tools/video/demo-tienda.mjs <carpeta>              # cuadros en <carpeta>/shots
swiftc -O tools/video/frames-to-mp4.swift -o /tmp/enc && /tmp/enc <carpeta>/shots <salida>.mp4
```
