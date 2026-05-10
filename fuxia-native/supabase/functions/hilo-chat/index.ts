import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// ── Fuxia KB ─────────────────────────────────────────────────────────────────
const KB: { keywords: string[]; answer: string; escalate?: boolean }[] = [
  // Producto
  {
    keywords: ['lluvia', 'agua', 'impermeable', 'mojarse', 'mojar'],
    answer: 'Nuestras flats no son impermeables porque son de piel real. Para días de lluvia te recomendamos usar otro tipo de calzado y guardar tus Fuxia para días secos. 🌂',
  },
  {
    keywords: ['talla', 'medida', 'número', 'numero', 'tallas'],
    answer: 'Manejamos tallas del 22 al 26 MX (equivalente al 35-41 EU). En la web puedes ver nuestra guía de tallas detallada. ¿Quieres que te ayude a encontrar tu talla?',
  },
  {
    keywords: ['material', 'piel', 'cuero', 'vegan', 'vegano', 'sintetico', 'sintético'],
    answer: 'Trabajamos con piel genuina de alta calidad en la mayoría de nuestros modelos. Algunos estilos tienen opciones en piel sintética. En la descripción de cada producto está especificado el material.',
  },
  {
    keywords: ['precio', 'costo', 'cuanto', 'cuánto', 'vale', 'cuesta'],
    answer: 'Nuestros modelos van desde $1,500 hasta $3,500 MXN dependiendo del estilo y material. Puedes ver todos los precios actualizados en la tienda. ¿Te interesa algún modelo en particular?',
  },
  {
    keywords: ['colores', 'colores disponibles', 'variantes'],
    answer: 'Cada modelo tiene sus propios colores. Puedes verlos directamente en la página de cada producto. ¿Tienes algún modelo o color en mente?',
  },
  // Hilo Lealtad
  {
    keywords: ['hilo', 'lealtad', 'programa', 'rewards', 'puntos hilo', 'programa hilo'],
    answer: 'Hilo es nuestro programa de lealtad 💛 Acumulas 1 punto por cada peso MXN que gastas. Los puntos se canjean por descuentos, accesos a preventas y regalos exclusivos. Es gratuito y ya estás inscrita al registrarte en la app.',
  },
  {
    keywords: ['registro', 'inscribir', 'inscribirme', 'unirme', 'unirse', 'como me uno'],
    answer: 'Es gratis. Solo descarga la app de Fuxia, regístrate con tu número de teléfono y automáticamente quedas inscrita en el programa Hilo. Si ya has comprado antes con ese correo, tus compras anteriores cuentan. 🎉',
  },
  {
    keywords: ['cuantos puntos', 'cuántos puntos', 'ganar puntos', 'acumular', 'puntos gano'],
    answer: 'Ganas 1 punto Hilo por cada peso MXN que gastas. Por ejemplo, una compra de $1,800 MXN te da 1,800 puntos. En lanzamientos especiales hay multiplicadores 2x o 3x. ✨',
  },
  {
    keywords: ['canjear', 'usar puntos', 'redimir', 'descuento', 'como uso'],
    answer: 'En el checkout puedes aplicar tus puntos: 100 puntos = $10 MXN de descuento. También puedes canjearlos por accesos a preventas, regalos en pedidos y experiencias exclusivas.',
  },
  {
    keywords: ['bronze', 'silver', 'gold', 'nivel', 'tier', 'bronce', 'plata', 'oro'],
    answer: 'El programa Hilo tiene 3 niveles:\n🥉 Bronze: 0–299 pts\n🥈 Silver: 300–899 pts (3 pares)\n🥇 Gold: 900+ pts (9 pares)\n\nSuibr de nivel te da beneficios adicionales como envío gratis y acceso anticipado a nuevas colecciones.',
  },
  // Envíos
  {
    keywords: ['envio', 'envío', 'entrega', 'shipping', 'llega', 'cuanto tarda', 'cuánto tarda'],
    answer: 'Enviamos a toda la República Mexicana. Los tiempos son:\n📦 CDMX y área metro: 2-3 días hábiles\n🚚 Interior de la República: 3-5 días hábiles\nInternacional (Colombia, EEUU y más): 7-14 días.',
  },
  {
    keywords: ['rastrear', 'rastreo', 'tracking', 'donde esta', 'dónde está', 'seguimiento'],
    answer: 'Puedes rastrear tu pedido desde la sección "Seguimiento" en la app, o con el número de guía que te enviamos por WhatsApp/correo cuando tu pedido salió.',
  },
  {
    keywords: ['gratis', 'envio gratis', 'envío gratis', 'sin costo envio'],
    answer: 'El envío gratis aplica para pedidos mayores a $2,500 MXN en México. Los miembros Gold también tienen envío gratis en todos sus pedidos. 💛',
  },
  // Devoluciones
  {
    keywords: ['devolucion', 'devolución', 'cambio', 'regreso', 'regresar', 'reembolso'],
    answer: 'Aceptamos cambios dentro de los 15 días de recibido el pedido, siempre que el artículo esté sin usar y con etiquetas. Para iniciar un cambio escríbenos por WhatsApp o a hola@fuxiaballerinas.com.',
  },
  // Pagos
  {
    keywords: ['pago', 'pagar', 'tarjeta', 'transferencia', 'oxxo', 'paypal', 'metodo de pago'],
    answer: 'Aceptamos tarjetas de crédito y débito (Visa, Mastercard, Amex), transferencia bancaria, OXXO y PayPal. Todos los pagos son procesados de forma segura.',
  },
  // Contacto
  {
    keywords: ['whatsapp', 'telefono', 'teléfono', 'contacto', 'hablar con', 'persona', 'humano', 'asesor'],
    answer: 'Puedes escribirnos por WhatsApp al +52 55 XXXX XXXX o por correo a hola@fuxiaballerinas.com. Respondemos de lunes a sábado de 9am a 7pm. 😊',
    escalate: true,
  },
];

// ── Matcher ───────────────────────────────────────────────────────────────────
function findAnswer(message: string): { answer: string; escalate: boolean } {
  const lower = message.toLowerCase();
  // Score each KB entry
  let best: (typeof KB)[0] | null = null;
  let bestScore = 0;
  for (const entry of KB) {
    const score = entry.keywords.reduce((acc, kw) => acc + (lower.includes(kw) ? 1 : 0), 0);
    if (score > bestScore) {
      bestScore = score;
      best = entry;
    }
  }
  if (best && bestScore > 0) {
    return { answer: best.answer, escalate: !!best.escalate };
  }
  // Fallback
  return {
    answer: 'No tengo la respuesta exacta para eso 😊 Escríbenos por WhatsApp o a hola@fuxiaballerinas.com y con gusto te ayudamos.',
    escalate: true,
  };
}

// ── Handler ───────────────────────────────────────────────────────────────────
serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: cors });
  }

  try {
    const { message } = await req.json();
    if (!message || typeof message !== 'string') {
      return new Response(JSON.stringify({ error: 'message required' }), {
        status: 400,
        headers: { ...cors, 'Content-Type': 'application/json' },
      });
    }

    const { answer, escalate } = findAnswer(message.trim());

    return new Response(JSON.stringify({ response: answer, escalate }), {
      headers: { ...cors, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...cors, 'Content-Type': 'application/json' },
    });
  }
});
