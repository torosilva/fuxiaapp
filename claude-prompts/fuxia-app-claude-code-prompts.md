# Fuxia App — Arquitectura + Prompts para Claude Code
> Sistema de lealtad con tarjeta QR, historial de compras y recompensas por niveles  
> Stack: React Native (TypeScript) · WooCommerce REST API · Supabase

---

## Contexto del proyecto

- **Repo:** https://github.com/torosilva/fuxiaapp
- **Stack actual:** React Native + TypeScript (carpeta `fuxia-native`)
- **Backend ecommerce:** WooCommerce en fuxiaballerinas.com
- **Objetivo:** Tarjeta de lealtad con QR, seguimiento de compras por cliente, recompensas por nivel (Bronce / Plata / Oro)

---

## Modelo de puntos definido

| Regla | Valor |
|---|---|
| Puntos por compra | 1 punto por cada $50 MXN gastados |
| Bonus por par completo | +10 puntos extra por cada par de zapatos |
| Nivel Bronce | 0–5 pares ó 0–500 puntos |
| Nivel Plata | 6–12 pares ó 501–1,200 puntos |
| Nivel Oro | 13+ pares ó 1,201+ puntos |
| Recompensa Bronce → Plata | 1 accesorio gratis (valor hasta $300 MXN) |
| Recompensa Plata → Oro | 1 par de flats gratis (modelo básico) |
| Recompensa especial Oro | 1 par de flats premium gratis al llegar a 2,000 puntos |

---

## Arquitectura del sistema

```
[App React Native]
       ↕ REST
[Supabase Backend]
  ├── customers
  ├── loyalty_cards  (QR único por cliente)
  ├── transactions   (sincronizadas desde WC)
  ├── purchase_items (detalle de cada par comprado)
  ├── rewards        (canjes y recompensas)
  ├── qr_scans       (registro de escaneos en tienda)
  └── tier_config    (tabla de configuración de niveles)
       ↕ Webhook + REST API
[WooCommerce fuxiaballerinas.com]
```

---

## PROMPTS PARA CLAUDE CODE
> Copiar y pegar cada prompt directamente en Claude Code en orden

---

### PROMPT 1 — Configuración de Supabase y esquema de base de datos

```
Estoy construyendo el backend de una app de lealtad para Fuxia Ballerinas (tienda de zapatos LATAM).
El proyecto está en /fuxia-native y usa React Native con TypeScript.

Necesito configurar Supabase como backend. Por favor:

1. Instala las dependencias necesarias:
   - @supabase/supabase-js
   - react-native-url-polyfill (requerido para Supabase en React Native)

2. Crea el archivo src/lib/supabase.ts con la configuración del cliente Supabase.
   Usa variables de entorno: SUPABASE_URL y SUPABASE_ANON_KEY

3. Crea el archivo database/schema.sql con las siguientes tablas:

-- customers: vinculado a WooCommerce
CREATE TABLE customers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone TEXT UNIQUE NOT NULL,  -- identificador principal en LATAM
  name TEXT NOT NULL,
  email TEXT,
  country TEXT DEFAULT 'MX',  -- MX, CO, GT, SV, CR, PA, HN
  wc_customer_id INTEGER,      -- ID en WooCommerce
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- loyalty_cards: una por cliente, contiene el QR
CREATE TABLE loyalty_cards (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id UUID REFERENCES customers(id) ON DELETE CASCADE,
  qr_code TEXT UNIQUE NOT NULL,  -- formato: FX-{customer_id_short}-{checksum}
  total_points INTEGER DEFAULT 0,
  pairs_count INTEGER DEFAULT 0,
  tier TEXT DEFAULT 'bronze' CHECK (tier IN ('bronze', 'silver', 'gold')),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- tier_config: configuración de niveles
CREATE TABLE tier_config (
  tier TEXT PRIMARY KEY,
  min_pairs INTEGER NOT NULL,
  min_points INTEGER NOT NULL,
  reward_description TEXT,
  reward_sku TEXT
);

-- transactions: sincronizadas desde WooCommerce via webhook
CREATE TABLE transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  loyalty_card_id UUID REFERENCES loyalty_cards(id),
  wc_order_id INTEGER UNIQUE,
  amount DECIMAL(10,2) NOT NULL,
  currency TEXT DEFAULT 'MXN',
  points_earned INTEGER NOT NULL,
  pairs_in_order INTEGER DEFAULT 0,
  channel TEXT DEFAULT 'web' CHECK (channel IN ('web', 'store', 'app')),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- purchase_items: detalle de cada par comprado
CREATE TABLE purchase_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  transaction_id UUID REFERENCES transactions(id),
  sku TEXT NOT NULL,
  product_name TEXT NOT NULL,
  size TEXT,
  color TEXT,
  category TEXT,
  quantity INTEGER DEFAULT 1,
  unit_price DECIMAL(10,2)
);

-- rewards: canjes y recompensas ganadas
CREATE TABLE rewards (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  loyalty_card_id UUID REFERENCES loyalty_cards(id),
  type TEXT CHECK (type IN ('tier_upgrade', 'points_redemption', 'special')),
  threshold_points INTEGER,
  product_sku TEXT,
  description TEXT,
  redeemed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- qr_scans: log de escaneos en tienda
CREATE TABLE qr_scans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  loyalty_card_id UUID REFERENCES loyalty_cards(id),
  store_id TEXT,
  staff_id TEXT,
  channel TEXT CHECK (channel IN ('store', 'web')),
  scanned_at TIMESTAMPTZ DEFAULT NOW()
);

-- Datos iniciales de niveles
INSERT INTO tier_config VALUES
  ('bronze', 0, 0, 'Accesorio gratis (hasta $300 MXN)', 'REWARD-BRONZE'),
  ('silver', 6, 501, '1 par de flats básico gratis', 'REWARD-SILVER'),
  ('gold', 13, 1201, '1 par de flats premium gratis', 'REWARD-GOLD');

4. Crea una función Supabase Edge Function en supabase/functions/calculate-points/index.ts
   que reciba { amount, pairs_count } y devuelva { points_earned } usando estas reglas:
   - 1 punto por cada $50 MXN
   - +10 puntos bonus por cada par (pairs_count)
   - Ejemplo: $350 MXN con 2 pares = 7 + 20 = 27 puntos

5. Crea una función calculate-tier en supabase/functions/calculate-tier/index.ts
   que reciba { total_points, pairs_count } y devuelva { tier, next_tier, points_to_next, pairs_to_next }
```

---

### PROMPT 2 — Generador de QR único por cliente

```
En el proyecto Fuxia App (React Native + TypeScript + Supabase), necesito implementar
la generación y visualización del QR de lealtad de cada cliente.

1. Instala: react-native-qrcode-svg expo-camera

2. Crea src/utils/qrGenerator.ts con:
   - Función generateQRCode(customerId: string): string
     Formato: "FX-{primeros 8 chars del UUID}-{timestamp base36}-{checksum}"
     Ejemplo: "FX-a3f8b2c1-lx4k2m-7f"
   - Función validateQRCode(qrCode: string): boolean
   - Función extractCustomerId(qrCode: string): string | null

3. Crea src/components/LoyaltyCard.tsx — la tarjeta visual con:
   - QR code renderizado con react-native-qrcode-svg
   - Nombre de la clienta
   - Nivel actual (Bronce/Plata/Oro) con color de fondo correspondiente:
     Bronce: #CD7F32, Plata: #C0C0C0, Oro: #FFD700
   - Total de puntos y pares acumulados
   - Barra de progreso hacia el siguiente nivel
   - Logo de Fuxia Ballerinas en la parte superior
   - El QR debe funcionar offline (los datos están en el componente, no en red)

4. Crea src/screens/CardScreen.tsx que muestre la LoyaltyCard y abajo:
   - Botón "Compartir tarjeta" (usando Share API de React Native)
   - Texto "Muéstrala en tienda para acumular puntos"
   - Historial de los últimos 5 movimientos de puntos

5. La tarjeta debe ser visualmente parecida a una tarjeta bancaria:
   proporción 85.6mm × 54mm (ratio 1.585), bordes redondeados,
   fondo degradado en el color del tier.
```

---

### PROMPT 3 — Integración con WooCommerce via Webhook

```
Necesito conectar la app Fuxia con WooCommerce en fuxiaballerinas.com.
La integración debe ser bidireccional: WooCommerce notifica a Supabase cuando hay
una nueva orden, y la app puede ver el historial de compras.

1. Crea supabase/functions/woocommerce-webhook/index.ts — Edge Function que:
   - Recibe POST de WooCommerce en /woocommerce-webhook
   - Valida la firma HMAC-SHA256 del header x-wc-webhook-signature
   - Procesa el evento order.completed:
     a. Busca al cliente por email o billing_phone en la tabla customers
     b. Si no existe, crea el cliente automáticamente
     c. Calcula puntos: Math.floor(order.total / 50) + (items_count * 10)
     d. Cuenta cuántos pares hay en la orden (cada line_item con category 'zapatos')
     e. Inserta en transactions con channel='web'
     f. Inserta cada line_item en purchase_items con sku, nombre, talla (meta 'pa_size'), color (meta 'pa_color')
     g. Actualiza loyalty_cards: total_points += points, pairs_count += pairs
     h. Recalcula el tier y lo actualiza
     i. Si el tier subió, inserta en rewards con type='tier_upgrade'

2. Crea src/services/woocommerceService.ts con:
   - getPurchaseHistory(customerId: string): Promise<Transaction[]>
     Llama a GET /wp-json/wc/v3/orders?customer={wc_customer_id}&per_page=20
   - getProductDetails(sku: string): Promise<Product>
   - syncCustomerFromWC(wcCustomerId: number): Promise<Customer>

3. Crea src/hooks/usePurchaseHistory.ts — hook React que:
   - Primero carga desde Supabase (cache local, rápido)
   - En background sincroniza con WooCommerce si hay órdenes nuevas
   - Devuelve { purchases, isLoading, lastSync }

4. Agrega en README.md las instrucciones para configurar el webhook en WooCommerce:
   WooCommerce → Ajustes → Avanzado → Webhooks → Agregar webhook
   - Nombre: Fuxia Loyalty Sync
   - Estado: Activo
   - Tema: Pedido completado
   - URL de entrega: https://{tu-proyecto}.supabase.co/functions/v1/woocommerce-webhook
   - Versión API: WP REST API Integration v3
```

---

### PROMPT 4 — Pantalla de historial de compras (vista cliente)

```
En la app Fuxia (React Native + TypeScript), crea la pantalla de historial de compras
que muestra a la clienta todo lo que ha comprado con detalles de cada par.

1. Crea src/screens/PurchaseHistoryScreen.tsx:
   - Header: "Mis zapatos" con contador total de pares
   - Lista de compras agrupadas por fecha (mes y año)
   - Cada compra muestra:
     * Fecha del pedido
     * Lista de productos: nombre, color, talla, imagen del producto (desde WC)
     * Puntos ganados en esa compra
     * Canal: 🌐 Online / 🏪 En tienda
   - Al tocar una compra, expande para ver todos los items
   - Estado vacío amigable si no hay compras: "Tus compras aparecerán aquí"

2. Crea src/components/PurchaseCard.tsx — card individual de compra con:
   - Imagen del producto (con fallback al logo de Fuxia si no carga)
   - Chip de talla y color
   - Badge de puntos ganados (+27 puntos)
   - Animación suave de expansión/colapso

3. Crea src/screens/ProductDetailScreen.tsx — cuando la clienta toca un par:
   - Imagen grande del producto
   - Nombre, descripción, talla y color comprados
   - Fecha de compra
   - Botón "Comprar de nuevo" → abre fuxiaballerinas.com/producto/{slug} en WebView
   - Sección "También te puede gustar" con 3 productos del mismo modelo en otros colores
     (consulta WooCommerce por category y excluye el SKU ya comprado)

4. Usa React Navigation con stack navigator. La navegación debe ser:
   CardScreen → PurchaseHistoryScreen → ProductDetailScreen
```

---

### PROMPT 5 — Escáner QR para vendedoras en tienda

```
En la app Fuxia necesito una pantalla especial para las vendedoras en tienda física.
Esta pantalla les permite escanear el QR de la clienta y ver su perfil completo.

1. Crea src/screens/StoreScanner.tsx:
   - Pantalla protegida: solo accesible con PIN de 4 dígitos (configurable por tienda)
   - Cámara que escanea QR usando expo-camera o react-native-vision-camera
   - Al leer un QR válido (formato FX-*):
     a. Muestra el perfil de la clienta en un bottom sheet:
        - Nombre y foto de perfil (inicial si no hay foto)
        - Nivel actual con color del tier
        - Puntos acumulados y pares totales
        - Sus últimas 3 compras con los modelos comprados
        - Talla más frecuente (calculada del historial)
        - Botón "Registrar compra en tienda" → lleva a formulario
     b. Registra el escaneo en la tabla qr_scans con store_id y timestamp

2. Crea src/screens/StoreRegisterSale.tsx — para cuando la venta fue en tienda física:
   - Input de monto de venta (teclado numérico)
   - Selector de productos vendidos (busca por nombre/SKU en WooCommerce)
   - Preview de puntos que ganará: "{X} puntos por esta compra"
   - Botón "Confirmar venta" → inserta en transactions con channel='store'
   - Muestra animación de celebración si sube de tier

3. Crea src/components/CustomerProfileSheet.tsx — bottom sheet reutilizable con:
   - Animación de entrada desde abajo (500ms, easing ease-out)
   - Fondo semi-transparente con blur
   - Indicador de nivel con barra de progreso animada
   - Lista horizontal de los modelos comprados (thumbnails)

4. Agrega lógica de detección de fraude básica en src/utils/fraudDetection.ts:
   - Si el mismo QR se escanea más de 3 veces en 10 minutos desde la misma tienda → alerta
   - Si se intentan agregar puntos por monto > $10,000 MXN en una sola venta → requiere confirmación de manager
```

---

### PROMPT 6 — Registro de usuario con número de teléfono

```
En la app Fuxia, el registro debe ser por número de teléfono (no email) usando OTP via SMS.
En LATAM la gente cambia de email pero no de número. Usar Supabase Auth con Twilio.

1. Crea src/screens/OnboardingScreen.tsx — flujo de 3 pasos:
   Paso 1: "¿En qué país estás?"
   - Selector visual de banderas: 🇲🇽 México · 🇨🇴 Colombia · 🇬🇹 Guatemala
     🇸🇻 El Salvador · 🇨🇷 Costa Rica · 🇵🇦 Panamá · 🇭🇳 Honduras
   - Al seleccionar, precarga el código de país en el input de teléfono
   
   Paso 2: "Tu número de WhatsApp"
   - Input con código de país (+52, +57, etc.) + número
   - Botón "Enviar código" → llama a supabase.auth.signInWithOtp({ phone })
   - Texto pequeño: "Te enviaremos un código por SMS"
   
   Paso 3: Verificación OTP
   - 6 inputs de un dígito cada uno (se enfocan automáticamente)
   - Countdown de 60 segundos para reenviar
   - Al completar → supabase.auth.verifyOtp({ phone, token, type: 'sms' })
   - Si es primera vez → redirige a completar perfil (nombre)
   - Si ya tiene cuenta → redirige a CardScreen

2. Crea src/screens/CompleteProfileScreen.tsx:
   - Input de nombre completo
   - Opción de agregar email (opcional, para recibir facturas)
   - Checkbox "Ya soy cliente de fuxiaballerinas.com"
     Si marca → pide su email de WooCommerce para vincular el historial anterior
   - Al guardar → crea registro en customers + genera loyalty_card con QR único

3. Crea src/hooks/useAuth.ts:
   - Maneja el estado de autenticación con Supabase
   - Persiste la sesión con AsyncStorage
   - Expone: { user, customer, loyaltyCard, isLoading, signOut }

4. Protege todas las rutas excepto Onboarding usando un RootNavigator
   que revise el estado de auth antes de renderizar la navegación principal.
```

---

### PROMPT 7 — Notificaciones push para recompensas

```
En la app Fuxia, implementa notificaciones push para avisar a la clienta cuando:
- Gana puntos por una compra
- Sube de nivel (de Bronce a Plata, o de Plata a Oro)
- Le falta poco para subir de nivel (cuando está a <50 puntos o <1 par del siguiente)
- Su recompensa está lista para canjear

1. Instala expo-notifications y configura para iOS y Android

2. Crea src/services/notificationService.ts con:
   - registerForPushNotifications(): guarda el token en Supabase tabla push_tokens
   - scheduleLocalNotification(title, body, data): para notificaciones inmediatas
   
3. Crea supabase/functions/send-push-notification/index.ts:
   Edge Function que se activa por database trigger cuando:
   - loyalty_cards.total_points aumenta → envía "¡Ganaste X puntos!"
   - loyalty_cards.tier cambia → envía "¡Subiste a nivel {tier}! Tu recompensa te espera"
   - loyalty_cards.total_points está a 50 del siguiente umbral → "Te faltan 50 puntos para subir a {siguiente_tier}"
   
   Usar Expo Push API: POST https://exp.host/--/api/v2/push/send

4. Los mensajes deben estar en español con el nombre de la clienta:
   "¡Hola {nombre}! Ganaste 27 puntos por tu compra 🎉"
   "¡{nombre}, ya eres nivel Plata! Tu par de flats gratis te espera 👟"
   "¡Casi llegas a Oro! Solo te faltan 48 puntos, {nombre} ✨"
```

---

## Orden de ejecución recomendado

1. Prompt 1 → Base de datos (fundamento de todo)
2. Prompt 6 → Registro/auth (necesitas usuarios antes que nada)
3. Prompt 2 → QR y tarjeta visual (el corazón del producto)
4. Prompt 3 → Webhook WooCommerce (datos reales de compras)
5. Prompt 4 → Historial de compras (valor para la clienta)
6. Prompt 5 → Escáner para vendedoras (valor para el negocio)
7. Prompt 7 → Notificaciones (retención y reactivación)

---

## Variables de entorno necesarias (.env)

```
SUPABASE_URL=https://tu-proyecto.supabase.co
SUPABASE_ANON_KEY=eyJ...
SUPABASE_SERVICE_ROLE_KEY=eyJ...  (solo en Edge Functions)
WC_CONSUMER_KEY=ck_...
WC_CONSUMER_SECRET=cs_...
WC_STORE_URL=https://fuxiaballerinas.com
WC_WEBHOOK_SECRET=tu_secreto_hmac
TWILIO_ACCOUNT_SID=AC...
TWILIO_AUTH_TOKEN=...
```

---

## Métricas de éxito de la app (para seguimiento)

| Métrica | Objetivo mes 3 |
|---|---|
| Clientas registradas | 2,000 |
| Tasa de uso del QR en tienda | 40% de transacciones |
| Compra repetida de clientas con app vs sin app | +25% |
| Tasa de apertura de notificaciones push | >30% |
| Tiempo promedio entre compras (app vs sin app) | -20 días |
