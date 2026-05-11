import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// ── Fuxia KB (seed.json) ──────────────────────────────────────────────────────
const KB: { keywords: string[]; answer: string; escalate?: boolean }[] = [
  // Saludos
  {
    keywords: ['hola', 'buenas', 'buenos días', 'buenos dias', 'buenas tardes', 'buenas noches', 'hi', 'hello', 'hey'],
    answer: '¡Hola! 💛 Soy Hilo, tu asistente de Fuxia Ballerinas. Puedo ayudarte con tallas, envíos, devoluciones, el programa de puntos Hilo y más. ¿En qué te puedo ayudar?',
  },
  {
    keywords: ['gracias', 'muchas gracias', 'thanks', 'ok gracias', 'perfecto'],
    answer: '¡Con mucho gusto! 😊 Si tienes más preguntas, aquí estoy. ¡Que disfrutes tus Fuxia!',
  },
  {
    keywords: ['adios', 'adiós', 'bye', 'hasta luego', 'chao'],
    answer: '¡Hasta pronto! 💛 Recuerda que puedes escribirnos cuando quieras.',
  },

  // ── TALLAS ──────────────────────────────────────────────────────────────────
  {
    keywords: ['talla', 'tamaño', 'medir', 'pie', 'size', 'guía de tallas', 'qué talla'],
    answer: 'Te recomiendo medir tu pie por la noche (cuando está más relajado) parada sobre una hoja, marcando el talón y la punta del dedo más largo. La distancia en centímetros corresponde a tu talla mexicana. Si estás entre dos tallas, pide la mayor. También tenemos guía de tallas detallada en cada producto.',
  },
  {
    keywords: ['calce', 'fit', 'tallan grandes', 'tallan chicas'],
    answer: 'Las Fuxia tienen un calce fiel a la talla mexicana. Si normalmente usas 24, pide 24. Para pies anchos te recomiendo subir media talla para mayor comodidad.',
  },
  {
    keywords: ['apretadas', 'cambio de talla', 'talla mayor', 'no me quedaron'],
    answer: 'Si las acabas de recibir y te quedan apretadas, no las uses todavía. Tienes 15 días para hacer cambio por una talla mayor sin costo, siempre que estén sin uso y con caja original. Escríbenos con tu número de pedido.',
  },
  {
    keywords: ['equivalencia', 'americana', 'us 5', 'us 6', 'us 7', 'us 8', 'us 9', 'us 10', 'tabla tallas'],
    answer: 'Tabla de equivalencias:\nMX 22 = US 5\nMX 23 = US 6\nMX 24 = US 7\nMX 25 = US 8\nMX 26 = US 9\nMX 27 = US 10\n\nEsta tabla aplica para la mayoría de nuestros estilos.',
  },
  {
    keywords: ['ancho', 'pie ancho', 'wide'],
    answer: 'Nuestros modelos tienen calce estándar. Para pies anchos te recomiendo subir media talla. Las flats clásicas se adaptan mejor a pies anchos por el diseño suave de la piel.',
  },
  {
    keywords: ['talla chica', 'talla pequeña', 'talla 21', 'talla 22', 'talla más chica'],
    answer: 'Manejamos desde la talla 22 mexicana (US 5). Algunos modelos en edición especial llegan hasta 21. Si necesitas una talla menor a 22, escríbenos directo y revisamos disponibilidad.',
  },
  {
    keywords: ['talla grande', 'talla 27', 'talla 28', 'talla más grande'],
    answer: 'Manejamos hasta la talla 27 mexicana (US 10) en la mayoría de modelos. Si necesitas talla 28, mándanos mensaje porque algunos modelos los hacemos sobre pedido.',
  },
  {
    keywords: ['medias', 'calcetines', 'media talla'],
    answer: 'Si planeas usarlas con medias gruesas o tobilleras, sube media talla. Para calcetín invisible o sin medias, pide tu talla habitual.',
  },
  {
    keywords: ['calculadora', 'calculadora de talla', 'foto pie', 'ai talla'],
    answer: 'En la app puedes tomar foto de tu pie al lado de una hoja tamaño carta y calculamos tu talla. Como respaldo siempre puedes medir manualmente.',
  },

  // ── ENVÍOS ──────────────────────────────────────────────────────────────────
  {
    keywords: ['cuánto tarda', 'cuanto tarda', 'tiempo envío', 'días entrega', 'cuando llega'],
    answer: 'Los envíos en México llegan en 3 a 5 días hábiles. CDMX y zona metropolitana: 1 a 3 días. Recibes tu número de guía por correo y WhatsApp en cuanto sale del almacén.',
  },
  {
    keywords: ['costo envío', 'precio envío', 'precio shipping', 'cuánto cuesta envío', 'envío gratis'],
    answer: 'Envío estándar en México: $150 MXN. Gratis en pedidos arriba de $1,800 MXN. Envío exprés (1-2 días): $280 MXN.',
  },
  {
    keywords: ['estados unidos', 'usa', 'international', 'dhl', 'envío usa'],
    answer: 'Sí, enviamos a Estados Unidos vía DHL Express. Tiempo: 5 a 8 días hábiles. El costo se calcula al checkout según destino. Los aranceles e impuestos son responsabilidad del comprador.',
  },
  {
    keywords: ['canadá', 'canada', 'envío canadá'],
    answer: 'Sí, enviamos a Canadá vía DHL Express. Tiempo: 6 a 10 días hábiles. El costo se calcula al checkout.',
  },
  {
    keywords: ['cambiar dirección', 'modificar dirección', 'cambiar envío'],
    answer: 'Si tu pedido aún no salió del almacén sí podemos cambiar la dirección. Escríbenos cuanto antes con tu número de pedido. Una vez con guía emitida ya no es posible.',
  },
  {
    keywords: ['rastrear', 'rastreo', 'tracking', 'guía', 'número de guía', 'dónde está mi pedido'],
    answer: 'En cuanto sale del almacén te enviamos el número de guía por correo y WhatsApp. Puedes rastrearlo directo en la página de Estafeta o DHL según el caso. También desde la sección Seguimiento en la app.',
  },
  {
    keywords: ['estafeta', 'paquetería', 'qué paquetería'],
    answer: 'En México usamos Estafeta y DHL para envíos express. Para envíos internacionales usamos DHL Express.',
  },

  // ── DEVOLUCIONES ─────────────────────────────────────────────────────────────
  {
    keywords: ['devolver', 'devolución', 'return', 'no me quedaron', 'regresar'],
    answer: 'Tienes 15 días desde que recibes tu pedido para devolverlo, siempre que estén sin uso, con caja original y accesorios. El envío de devolución corre por tu cuenta excepto en el primer cambio de talla.',
  },
  {
    keywords: ['plazo devolución', 'días devolución', 'cuánto tiempo devolver'],
    answer: 'Tienes 15 días naturales desde que recibes tu pedido. Después ya no aceptamos devoluciones, salvo defecto de fábrica.',
  },
  {
    keywords: ['quién paga envío devolución', 'guía retorno', 'envío de regreso'],
    answer: 'El primer cambio de talla por pedido es sin costo, generamos guía. Devoluciones por preferencia personal: el envío corre por tu cuenta. Producto con defecto de fábrica: siempre gratis.',
  },
  {
    keywords: ['reembolso', 'refund', 'dinero de regreso', 'cuándo me regresan'],
    answer: 'Una vez que recibimos tu devolución y verificamos el estado, procesamos el reembolso al método de pago original en 5 a 10 días hábiles. Te avisamos por correo.',
  },
  {
    keywords: ['cambio modelo', 'otro modelo', 'otro estilo', 'cambiar modelo'],
    answer: 'Sí, puedes cambiar de modelo dentro de los 15 días si está sin uso. Si el modelo nuevo tiene precio diferente, ajustamos la diferencia.',
  },
  {
    keywords: ['defectuoso', 'dañado', 'roto', 'calidad', 'falla', 'defecto'],
    answer: 'Lamento que pasara 😞 Mándanos foto del defecto con tu número de pedido a hola@fuxiaballerinas.com y lo resolvemos sin costo: cambio inmediato o reembolso completo, lo que prefieras.',
  },

  // ── PRODUCTO ─────────────────────────────────────────────────────────────────
  {
    keywords: ['materiales', 'piel', 'cuero', 'leather', 'fabricación', 'están hechas'],
    answer: 'Nuestras flats están hechas con piel real de origen colombiano, suela flexible antiderrapante y plantilla acolchonada con memory foam. Cada par se fabrica artesanalmente en talleres familiares en Colombia.',
  },
  {
    keywords: ['cómodas', 'comodidad', 'todo el día', 'trabajo', 'para trabajar'],
    answer: 'Sí, ese es uno de nuestros sellos 💛 La plantilla con memory foam y suela flexible las hacen cómodas hasta 8-10 horas continuas. Muchas clientas las usan para trabajar de pie sin problema.',
  },
  {
    keywords: ['cuidado', 'limpieza', 'mantenimiento', 'cómo cuido', 'como cuido'],
    answer: 'Para mantenerlas bonitas:\n• Limpia con paño seco después de usar\n• Aplica crema para piel cada 2-3 meses\n• Evita mojarlas (si pasa, deja secar al aire lejos del sol)\n• Guárdalas en su bolsa de tela (incluida con cada par)',
  },
  {
    keywords: ['dónde se fabrican', 'origen', 'colombia', 'made in', 'artesanal'],
    answer: 'Cada par se fabrica artesanalmente en talleres familiares en Colombia, principalmente en la región de Antioquia. Trabajamos con maestros zapateros que llevan generaciones en el oficio.',
  },
  {
    keywords: ['sustentable', 'ecológico', 'sostenibilidad', 'medio ambiente'],
    answer: 'Trabajamos con piel de subproducto de la industria alimentaria (no se sacrifican animales para nuestro calzado), procesos artesanales bajo en agua, y empaque 100% reciclable. Estamos en proceso de certificación.',
  },
  {
    keywords: ['vegano', 'sin cuero', 'vegan', 'alternativa vegana'],
    answer: 'Por ahora todos nuestros modelos son de piel real. Estamos evaluando lanzar una línea vegana en 2027 con la misma calidad y comodidad.',
  },
  {
    keywords: ['cuánto duran', 'vida útil', 'duración', 'calidad'],
    answer: 'Con cuidado básico duran de 2 a 4 años de uso regular. La piel real se vuelve más bonita con el tiempo. La suela puede reemplazarse en cualquier zapatería si se desgasta.',
  },
  {
    keywords: ['lluvia', 'agua', 'impermeable', 'mojarse'],
    answer: 'Nuestras flats no son impermeables porque son de piel real. Para días de lluvia te recomendamos otro tipo de calzado y guardar tus Fuxia para días secos. 🌂',
  },

  // ── LEALTAD HILO ─────────────────────────────────────────────────────────────
  {
    keywords: ['hilo', 'programa hilo', 'lealtad', 'rewards', 'cómo funciona hilo'],
    answer: 'Hilo es nuestro programa de lealtad 💛 Ganas 100 puntos por cada par que compras. Al acumular puntos subes de nivel y desbloqueas beneficios como descuentos, envío gratis y hasta un par gratis en Gold. Es gratis y ya estás inscrita al registrarte en la app.',
  },
  {
    keywords: ['unirme', 'inscribirme', 'cómo me uno', 'registrarme en hilo'],
    answer: 'Es gratis. Descarga la app de Fuxia, regístrate con tu teléfono y quedas inscrita automáticamente. Si ya has comprado antes con ese correo, tus compras anteriores cuentan.',
  },
  {
    keywords: ['cuántos puntos gano', 'puntos por compra', 'acumular puntos', 'ganar puntos'],
    answer: 'Ganas 100 puntos Hilo por cada par que compras, sin importar el precio. Además: +50 puntos si refieres a una amiga que compra, y +50 puntos en tu mes de cumpleaños. ✨',
  },
  {
    keywords: ['canjear', 'usar puntos', 'redimir', 'aplicar puntos'],
    answer: 'Tus puntos se convierten en beneficios según tu nivel:\n🥈 Silver (300 pts): 10% de descuento en cada compra + envío gratis\n🥇 Gold (900 pts): 20% en cumpleaños + envío gratis + ¡el par 10 es GRATIS! 🎁',
  },
  {
    keywords: ['vencen', 'expiran', 'vigencia', 'caducan'],
    answer: 'Los puntos Hilo vencen 12 meses después de tu última compra activa. Mientras compres al menos una vez al año, no se vencen.',
  },
  {
    keywords: ['niveles hilo', 'tiers', 'nivel', 'bronze', 'silver', 'gold', 'bronce', 'plata', 'oro', 'nivel hilo'],
    answer: 'El programa Hilo tiene 3 niveles:\n🥉 Bronze: 0–299 pts\n🥈 Silver: 300–899 pts\n🥇 Gold: 900+ pts\n\nSubir de nivel te da beneficios extra como envíos gratis y acceso anticipado a nuevas colecciones.',
  },

  // ── PEDIDOS ──────────────────────────────────────────────────────────────────
  {
    keywords: ['estatus pedido', 'estado de mi pedido', 'mi orden', 'dónde está mi orden'],
    answer: 'Entra a tu cuenta en la app o en fuxia.com y verás el historial con estatus actualizado. También recibes notificaciones por correo y WhatsApp cuando cambia el estatus.',
  },
  {
    keywords: ['cancelar pedido', 'anular', 'cancelar mi orden'],
    answer: 'Si tu pedido aún no salió del almacén, sí podemos cancelarlo con reembolso completo. Una vez con guía emitida ya no es posible cancelar, pero puedes recibirlo y procesarlo como devolución.',
  },
  {
    keywords: ['modificar pedido', 'cambiar pedido', 'agregar al pedido'],
    answer: 'Si aún no sale del almacén podemos modificar talla, modelo o agregar artículos. Escríbenos cuanto antes con tu número de pedido.',
  },
  {
    keywords: ['mayoreo', 'wholesale', 'volumen', 'por mayoreo'],
    answer: 'Sí, manejamos pedidos al mayoreo a partir de 30 pares con precios especiales. Te paso con nuestro equipo comercial para condiciones específicas.',
    escalate: true,
  },

  // ── PAGOS ────────────────────────────────────────────────────────────────────
  {
    keywords: ['métodos de pago', 'cómo pagar', 'formas de pago', 'tarjeta', 'oxxo', 'spei'],
    answer: 'Aceptamos: tarjetas de crédito/débito (Visa, Mastercard, Amex), PayPal, Mercado Pago, transferencia SPEI y pago en OXXO. En la app también puedes pagar con Apple Pay.',
  },
  {
    keywords: ['meses sin intereses', 'msi', 'financiamiento', 'a meses'],
    answer: 'Sí, ofrecemos 3 y 6 meses sin intereses con tarjetas participantes en compras arriba de $1,500 MXN. La opción aparece automáticamente en el checkout si tu tarjeta es elegible.',
  },
  {
    keywords: ['seguro pagar', 'seguridad', 'ssl', 'fraude', 'datos'],
    answer: 'Totalmente seguro. Usamos Stripe y Mercado Pago certificados PCI-DSS. Nunca guardamos tu información de tarjeta. Conexión cifrada con SSL 🔒',
  },
  {
    keywords: ['dólares', 'usd', 'moneda', 'pagar en dólares'],
    answer: 'Para pedidos a Estados Unidos y Canadá el cobro es automáticamente en dólares. Para pedidos en México el cobro es en pesos mexicanos.',
  },

  // ── BAZARES / TIENDA ─────────────────────────────────────────────────────────
  {
    keywords: ['bazar', 'tienda física', 'ver en persona', 'probar', 'dónde comprar físico'],
    answer: 'Estamos en bazares y tiendas compartidas en CDMX y Monterrey frecuentemente. Checa nuestro Instagram @fuxiaballerinas donde anunciamos cada evento. También puedes escribirnos para el calendario más reciente.',
  },
  {
    keywords: ['tienda propia', 'showroom', 'boutique'],
    answer: 'Por ahora somos principalmente una marca online. Estamos en bazares periódicamente y planeamos abrir nuestro primer showroom en CDMX en 2027.',
  },

  // ── MARCA ────────────────────────────────────────────────────────────────────
  {
    keywords: ['fundadores', 'historia', 'quién es fuxia', 'quiénes son'],
    answer: 'Fuxia fue fundada por Mario Silva y Carolina Muñoz. Nació de traer zapatos artesanales colombianos de calidad premium a mujeres latinas que valoran diseño, comodidad y origen ético.',
  },
  {
    keywords: ['instagram', 'tiktok', 'redes sociales', 'seguir', 'newsletter'],
    answer: 'Síguenos en:\n📷 Instagram: @fuxiaballerinas\n🎵 TikTok: @fuxiaballerinas\n📩 Newsletter en fuxiaballerinas.com',
  },
  {
    keywords: ['influencer', 'colaboración', 'creadora', 'embajadora', 'collab'],
    answer: 'Trabajamos con creadoras latinas alineadas con la marca. Si te interesa colaborar, escríbenos a colab@fuxiaballerinas.com con tu perfil y métricas.',
  },

  // ── CONTACTO ─────────────────────────────────────────────────────────────────
  {
    keywords: ['whatsapp', 'teléfono', 'contacto', 'hablar con persona', 'asesor', 'humano'],
    answer: 'Puedes escribirnos a hola@fuxiaballerinas.com o a través de nuestro Instagram @fuxiaballerinas. Respondemos de lunes a sábado de 9am a 7pm. 😊',
    escalate: true,
  },
];

// ── Matcher ───────────────────────────────────────────────────────────────────
function findAnswer(message: string): { answer: string; escalate: boolean } {
  const lower = message.toLowerCase();
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
  return {
    answer: 'Mmm, no estoy segura de cómo ayudarte con eso 😊 Puedes preguntarme sobre tallas, envíos, devoluciones, el programa Hilo o cuidado de tus zapatos. También escríbenos a hola@fuxiaballerinas.com',
    escalate: false,
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
