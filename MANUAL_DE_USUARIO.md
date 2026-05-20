# Manual de Usuario — Fuxia Ballerinas App

Guía completa de funcionalidades de la aplicación móvil de Fuxia Ballerinas, organizada por tipo de usuario. Documento vivo — actualizar cuando se agreguen features.

**Versión de la app:** 1.0.0
**Última actualización del manual:** 20 mayo 2026
**Países soportados:** México, Colombia, Estados Unidos, Canadá, Guatemala, El Salvador, Chile, Argentina, Panamá, Costa Rica, Perú

---

## Tabla de contenidos

1. [Tipos de usuario](#tipos-de-usuario)
2. [Para Clientes](#para-clientes)
3. [Para Vendedoras](#para-vendedoras)
4. [Para Administradores](#para-administradores)
5. [Sistema de Puntos y Niveles](#sistema-de-puntos-y-niveles)
6. [Sistema de Referidos](#sistema-de-referidos)
7. [Países y moneda](#países-y-moneda)
8. [Preguntas frecuentes](#preguntas-frecuentes)

---

## Tipos de usuario

La app maneja **tres roles** con permisos distintos:

| Rol | Acceso | Cómo se asigna |
|---|---|---|
| **Cliente** | Compras, tarjeta de lealtad, chat, perfil | Auto-registro al instalar |
| **Vendedora** | Registrar ventas en tienda/bazar | El admin asigna PIN + canal |
| **Administrador** | Gestionar canales, vendedoras, ver analíticas | Asignación manual en base de datos |

---

## Para Clientes

### Primer ingreso (Onboarding)

Al abrir la app por primera vez, hay 5 pantallas:

1. **Bienvenida** — Marca y tagline "UN PAR A LA VEZ".
2. **País** — Seleccionar el país de residencia. Esto define la moneda y los envíos.
3. **Teléfono** — Ingresar número de WhatsApp. Se envía código de verificación por WhatsApp.
4. **Verificar OTP** — Ingresar el código de 6 dígitos que llegó por WhatsApp.
5. **Completar perfil** — Nombre, email (opcional pero recomendado), cumpleaños (opcional), código de referida (si te invitaron).

Si pones tu email, la app se conecta automáticamente con tu cuenta de WooCommerce de fuxiaballerinas.com para mostrarte tus compras anteriores.

### Pantalla principal — Inicio

- **Hero**: imagen editorial de la colección actual con botón "Ver colección".
- **Novedades**: carrusel con los 6 productos más recientes.
- **Botón flotante Hilo (gold)**: abre el chat con la asistente AI desde cualquier pantalla.

### Pantalla Tienda

- Barra de búsqueda en la parte superior.
- Categorías rápidas: Ballerinas, Sandalias, Botas, Outlet.
- Lista completa de productos con imagen, nombre y precio.
- Tap en un producto → vista de detalle.

### Detalle del producto

Al tocar cualquier producto se ve:

- Galería de imágenes.
- Nombre y categoría.
- **Precio en tu moneda local** (ej. `$2,800 MXN`, `$150 USD`, `$420,000 COP`).
- Descripción.
- Selector de talla (si el producto tiene variaciones).
- Botón **❤️ corazón** (esquina superior derecha de cada imagen) → agrega/quita de tu lista de deseos.
- Indicador de puntos que ganarás con esta compra.
- Acción de compra: redirige al carrito web de fuxiaballerinas.com para el pago.

### Lista de deseos

- Pestaña con el ícono de corazón.
- Muestra todos los productos a los que les diste corazón.
- Se sincroniza entre dispositivos al iniciar sesión con el mismo número.

### Tarjeta de Lealtad

El corazón de la app. Esta pestaña muestra:

- **Código QR único** — La vendedora lo escanea en la tienda para registrar tus compras.
- **Nivel actual**: Bronze, Silver o Gold (ver detalles más abajo).
- **Total de puntos acumulados**.
- **Pares comprados**.
- **Barra de progreso al siguiente nivel** con "te faltan X puntos / X pares".
- **Últimas 5 compras** con fecha, producto y puntos ganados (con ícono que distingue compras online 🌐 vs en tienda 🏪).
- **Botón compartir**: comparte tu nivel y puntos por WhatsApp, email, etc.
- **Botón de chat Hilo** (esquina superior): abre la asistente.

### Perfil

- **Foto de avatar**: tap para verla en grande, o tocar el ícono cámara para cambiarla.
- **Nombre, teléfono, email**.
- **Mini tarjeta de lealtad** (resumen del nivel y puntos).
- **Accesos rápidos** en grid:
  - **Mis Compras** — historial completo de pedidos.
  - **Seguimiento** — estado de envíos y compras pendientes.
  - **Referir** — código de referida y lista de invitadas.
  - **Beneficios** — estadísticas de gasto y compras.
- **Última orden** — primer producto + número de orden + fecha.
- **Selector de país** — cambiar país de envío/moneda.
- **Cerrar sesión**.

### Mis Compras

Historial completo, agrupado por mes. Cada compra muestra:
- ID de orden
- Fecha
- Productos comprados con cantidad y precio
- Puntos ganados

### Seguimiento

Tres secciones:

1. **Pedidos online (WooCommerce)** con estado:
   - Pendiente de pago / Procesando / En espera / Enviado / Entregado / Cancelado / Reembolsado / Falló
   - Si tienen guía de envío: número de seguimiento + link para rastrear en la web del courier.

2. **Compras en tienda física** — registradas por vendedoras vía QR.

3. **Compras pendientes de reclamar** — códigos que recibiste en bazar/tienda pero no has reclamado todavía.

### Reclamar una compra (Código de venta)

Cuando una vendedora registra una venta en bazar/tienda sin escanear tu QR (por ejemplo, si no traes la app abierta), te dan un **código de 6 caracteres** (ej. `AB3D5M`). Para acumular esos puntos:

1. Ir a Perfil → Mis Compras → "Reclamar código".
2. Ingresar el código (6 cajitas, una letra/número por casilla).
3. Confirmar.
4. Aparece "¡Puntos reclamados!" con el total nuevo y si subiste de nivel.

Los caracteres son seguros sin confusiones: no se usan **0, 1, I, L, O, S, Z**.

### Referidos

- **Tu código**: 8 caracteres alfanuméricos (ej. `AB34CD56`).
- Botón **Copiar** y botón **Compartir**.
- **Cómo funciona**:
  1. Compartís tu código con una amiga.
  2. Ella lo ingresa al registrarse en la app.
  3. Cuando ella hace su primera compra, **te dan 2× los puntos de esa compra como bonus**.
- **Mis Referidas**: lista de personas que usaron tu código con estado (Sin compra aún / Procesando / 2× aplicado) y fecha del bonus si ya cobraste.

### Beneficios (Estadísticas)

- Total gastado de por vida.
- Número total de órdenes.
- Ticket promedio.
- Comparativo: este mes vs. mes anterior.
- Tendencia de los últimos 6 meses.
- Lista de transacciones.

### Hilo — Asistente AI

Botón flotante naranja con burbuja de chat, visible en casi todas las pantallas.

- **Chat conversacional** con IA entrenada en la marca, productos y programa de lealtad.
- Le podés preguntar:
  - "Recomiéndame ballerinas elegantes para una boda"
  - "Cuántos puntos tengo"
  - "Qué descuentos tienen ahora"
  - "Cuántos puntos me faltan para Silver"
- Cuando recomienda productos, aparecen **tarjetas con imagen, precio y botones** para agregarlos al wishlist directamente.

---

## Para Vendedoras

### Acceso

- Login con PIN asignado por el admin.
- Cada vendedora está vinculada a un canal (tienda o bazar).

### Pantalla principal

- Saludo: "Hola, {nombre}".
- Etiqueta del canal asignado (ej. "Tienda Roma · TIENDA" o "Bazar Polanco · BAZAR").
- **Contador de ventas del día** — tap para ver el detalle.
- **Botón principal "Registrar Venta"** (oro grande).
- **Botón "Mi Inventario"** — ver stock del canal.

### Registrar una venta

Flujo de 3 pasos:

#### Paso 1 — Productos
- Lista del inventario del canal con: nombre, talla, color, precio, stock disponible.
- Tap en un producto → se agrega al carrito.
- Botones +/- para cambiar cantidad.
- Vista del carrito con subtotal en tiempo real.

#### Paso 2 — Cliente
Dos opciones:

- **Escanear QR de la tarjeta de lealtad** — la cámara abre, apuntar al QR de la app del cliente. Auto-completa teléfono y nombre.
- **Ingresar teléfono manualmente** — número de WhatsApp con código de país.

#### Paso 3 — Confirmar
- Revisión del pedido: items, totales, datos del cliente.
- Tap "Confirmar venta".

#### Resultado
- Aparece un **código de 6 caracteres** (ej. `AB3D5M`).
- La vendedora se lo dicta/anota al cliente.
- El cliente puede reclamar sus puntos desde la app (sección Reclamar) ingresando ese código.
- Opciones: "Nueva venta" o "Salir".

### Mi inventario

- Vista de solo lectura del stock asignado a tu canal.
- Por cada producto: nombre, talla, color, precio, stock restante.

### Ventas del día

- Tap en el contador del home.
- Lista de todas las ventas registradas hoy en tu canal.
- Por venta: cliente (teléfono), items, total, hora.

---

## Para Administradores

### Acceso

- El usuario debe tener `role = 'admin'` en la base de datos de Supabase.
- Acceso desde Perfil → "Panel de administración".

### Resumen global

Al entrar al panel se ve:
- **Total de ventas** registradas en la app (todos los canales).
- **Total de pares vendidos**.
- **Ingreso total** en moneda local.

### Gestión de canales

Un **canal** es un punto de venta físico (una tienda permanente o un bazar temporal).

- **Crear canal** (+): nombre, tipo (tienda/bazar), ubicación, activo sí/no.
- **Lista de canales** con tarjeta por cada uno:
  - Ícono según tipo (Tienda 🏪 o Bazar 🛍️).
  - Nombre + ubicación.
  - Estado (verde = activo, gris = inactivo).
  - Stats: pares vendidos · stock restante · ingreso.
  - Barra de stock visual (qué porcentaje del inventario está vendido).
- Tap en un canal → editar y ver detalle.

### Plantilla de bazar

Para bazares que se montan rápido, hay una **plantilla precargada** con productos típicos para no tener que crear el inventario desde cero. Botón visible al crear un canal de tipo bazar.

### Gestión de vendedoras

- **Crear vendedora** (+): nombre, PIN (numérico), canal asignado, activo sí/no.
- **Lista** con cada vendedora mostrando nombre, PIN enmascarado (`****`), canal asignado, y estado.

### Reportes

- Por canal: detalle de ventas, ingresos, productos más vendidos.
- Por vendedora: ventas registradas, ingresos generados.

---

## Sistema de Puntos y Niveles

### Cómo ganar puntos

- **1 punto por cada 100 MXN gastados** (equivalente para otras monedas, ver más abajo).
- Aplica para todas las compras: online en fuxiaballerinas.com, en tienda física, o en bazares.

### Niveles

| Nivel | Requisitos | Beneficios |
|---|---|---|
| **Bronze** 🥉 | Default al registrarse | Acumulación de puntos |
| **Silver** 🥈 | 300+ puntos **o** 3+ pares comprados | Beneficios silver (descuentos especiales) |
| **Gold** 🥇 | 900+ puntos **o** 9+ pares comprados | Beneficios premium |

El nivel se actualiza automáticamente cuando se llega al umbral, en cualquiera de las dos métricas (lo que primero ocurra).

### Equivalencia entre monedas

Como 1 punto = 1 peso mexicano:
- **MXN**: 100 pesos = 1 punto
- **USD**: ~6 USD = 100 puntos (al tipo de cambio ~17 MXN/USD)
- **COP**: ~15,000 COP = 100 puntos (~150 COP/MXN)

(Las tasas se ajustan cuando cambien notablemente.)

---

## Sistema de Referidos

### Cómo funciona

1. Cada cliente tiene un **código único** de 8 caracteres al registrarse.
2. Lo comparte con amigas.
3. Cuando una amiga se registra ingresando ese código, queda **vinculada** como referida.
4. Cuando la referida hace su **primera compra** (en cualquier canal), el referente recibe **2× los puntos de esa compra** como bonus extra.

### Estados de una referida

- **Sin compra aún** — Se registró pero no ha comprado.
- **Procesando** — Hizo una compra, pero el bonus aún no se acreditó (puede tomar hasta 24 hrs).
- **2× aplicado** — Bonus cobrado, con fecha exacta.

### Visibilidad

En `Perfil → Referir`:
- Tu código + botones de compartir/copiar.
- Total de bonus ganados acumulados.
- Lista de todas tus referidas con su estado.

---

## Países y moneda

### Resolución automática

Al abrir la app, decide el país así:

1. **Si elegiste país manualmente** en el selector del perfil → usa ese.
2. Si no, **detecta la región del dispositivo** (configuración del sistema operativo). Mexicanos con celular en Mexico → MXN. Gringos → USD. Etc.
3. Si la región del device no es uno de los países soportados → cae a USD (estándar internacional).

### Cambiar país manualmente

`Perfil → Selector de país` → escoger uno de los 11 soportados. Esto:
- Cambia los precios a la moneda local.
- Define el envío.
- Se guarda en tu perfil y se sincroniza entre dispositivos.

### Países y monedas

| País | Moneda | País | Moneda |
|---|---|---|---|
| 🇲🇽 México | MXN | 🇨🇴 Colombia | COP |
| 🇺🇸 Estados Unidos | USD | 🇨🇦 Canadá | USD |
| 🇬🇹 Guatemala | USD | 🇸🇻 El Salvador | USD |
| 🇨🇱 Chile | USD | 🇦🇷 Argentina | USD |
| 🇵🇦 Panamá | USD | 🇨🇷 Costa Rica | USD |
| 🇵🇪 Perú | USD | | |

---

## Preguntas frecuentes

**No me llegó el código de WhatsApp al registrarme.**
Verificá que pusiste bien el número con el código de país (ej. +52 para México). Esperá 30 segundos y volvé a pedirlo desde la pantalla de verificación.

**Hice una compra en tienda y no se sumaron los puntos.**
Si la vendedora **no escaneó tu QR**, te tuvo que haber dado un código de 6 letras/números. Andá a Mis Compras → Reclamar código e ingresá ese código.

**Veo precios en USD pero vivo en México.**
Andá a Perfil → Selector de país y elegí México. Eso fuerza MXN incluso si tu teléfono tiene idioma inglés u otra región.

**Cambié de teléfono. ¿Pierdo mis puntos?**
No. Al instalar la app en el nuevo teléfono e iniciar sesión con el mismo número de WhatsApp, todos tus puntos, compras y wishlist se sincronizan.

**Mi código de referida no aparece.**
Aparece en Perfil → Referir. Si decís que no, verificá tener internet y reiniciá la app. Si persiste, contactá soporte.

**¿Las referidas reciben algo también?**
Por ahora solo el referente recibe el bonus 2x. Las referidas reciben los puntos normales de su compra como siempre.

**¿Cuándo se acredita el bonus por referida?**
Hasta 24 horas después de la primera compra de la referida. Si pasaron más de 24 hrs y no se acreditó, contactar soporte.

**¿La app funciona sin internet?**
No. Necesita conexión para mostrar productos, precios actualizados, registrar compras y sincronizar tu perfil. Algunas pantallas (tarjeta de lealtad, perfil básico) muestran datos cacheados si no hay conexión, pero las compras y el chat sí requieren red.

**¿Cómo se cambia el avatar de perfil?**
Perfil → tap en el ícono de cámara sobre tu foto actual → elegir desde la galería del celular. Se sube y queda guardado en tu perfil.

**¿Puedo borrar mi cuenta?**
Por ahora no desde la app. Solicítalo a soporte por WhatsApp o email — el equipo de Fuxia procesa la baja conforme a la política de privacidad.

---

## Soporte

- **WhatsApp**: el mismo número de la tienda principal.
- **Email**: ver política de privacidad en la app (Perfil → Privacidad).
- **Web**: fuxiaballerinas.com

---

*Manual generado el 20 de mayo de 2026. Para cambios y nuevas funciones consultar el [BACKLOG.md](./BACKLOG.md).*
