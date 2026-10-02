// Presentation helpers shared by server and client components (Spanish, Mexico City time).
export const pares = (n: number) => `${n} ${n === 1 ? 'par' : 'pares'}`;

export function imageUrl(path: string | null | undefined): string | null {
  if (!path) return null;
  if (/^https?:\/\//.test(path)) return path;
  return `${process.env.NEXT_PUBLIC_SUPABASE_URL}/storage/v1/object/public/product-images/${path}`;
}

export function fecha(iso: string): string {
  const d = new Date(iso);
  const now = new Date();
  const tz = 'America/Mexico_City';
  const day = (x: Date) => x.toLocaleDateString('es-MX', { timeZone: tz });
  const hora = d.toLocaleTimeString('es-MX', { timeZone: tz, hour: 'numeric', minute: '2-digit' });
  if (day(d) === day(now)) return `Hoy, ${hora}`;
  const ayer = new Date(now.getTime() - 86400000);
  if (day(d) === day(ayer)) return `Ayer, ${hora}`;
  return `${d.toLocaleDateString('es-MX', { timeZone: tz, day: 'numeric', month: 'long', year: 'numeric' })}, ${hora}`;
}

/** The system location for pairs travelling between locations. Never available, never sellable. */
export const TRANSIT_NAME = 'En camino';

// "Carolina recibió 11 pares en Bodega CDMX"
export function eventSentence(e: { type: string; actor_name: string; total_pairs: number; lines: { to_location: string | null; from_location: string | null }[] }): string {
  const to = e.lines[0]?.to_location;
  const from = e.lines[0]?.from_location;
  switch (e.type) {
    case 'RECEIPT':
      return `${e.actor_name} recibió ${pares(e.total_pairs)} en ${to ?? '—'}`;
    case 'TRANSFER':
      if (to === TRANSIT_NAME) return `${e.actor_name} envió ${pares(e.total_pairs)} de ${from ?? '—'} · en camino`;
      if (from === TRANSIT_NAME) return `${e.actor_name} recibió ${pares(e.total_pairs)} en ${to ?? '—'}`;
      return `${e.actor_name} movió ${pares(e.total_pairs)} de ${from ?? '—'} a ${to ?? '—'}`;
    case 'RETURN':
      return `${e.actor_name} regresó ${pares(e.total_pairs)} a ${to ?? '—'}`;
    case 'WRITE_OFF':
      return `${e.actor_name} dio de baja ${pares(e.total_pairs)}${from ? ` (${from})` : ''}`;
    case 'SALE':
      return `${e.actor_name} vendió ${pares(e.total_pairs)} de ${from ?? '—'}`;
    default:
      return `${e.actor_name} registró ${pares(e.total_pairs)}`;
  }
}

// Canonical Fuxia sizes are COLOMBIAN sizes (DW1), as used by the online store. Editable per product.
export const DEFAULT_SIZES = ['35', '36', '37', '38', '39', '40'];

export const precio = (n: number | null | undefined) =>
  n == null ? '' : `$${Number(n).toLocaleString('es-MX', { maximumFractionDigits: 2 })}`;

export const MISSING_LABEL: Record<string, string> = {
  precio: 'Precio', categoria: 'Categoría', descripcion: 'Descripción', color: 'Al menos un color', talla: 'Tallas', fotos: 'Fotos de cada color',
};

export const SWATCHES: { name: string; hex: string }[] = [
  { name: 'Negro', hex: '#1C1A17' }, { name: 'Blanco', hex: '#F4F1EA' }, { name: 'Nude', hex: '#D8B9A0' },
  { name: 'Camel', hex: '#B07A4A' }, { name: 'Rojo', hex: '#9E2A2B' }, { name: 'Rosa', hex: '#E3A6B4' },
  { name: 'Azul marino', hex: '#1F2A44' }, { name: 'Dorado', hex: '#B8860B' }, { name: 'Plata', hex: '#B9B9B9' },
  { name: 'Café', hex: '#6B4226' }, { name: 'Chocolate', hex: '#4B2E20' }, { name: 'Taupe', hex: '#8B7D6B' }, { name: 'Vino', hex: '#6D1A2A' },
  { name: 'Verde', hex: '#4A6B3A' }, { name: 'Verde aceituna', hex: '#6B6B2A' }, { name: 'Talco', hex: '#E8DCD0' }, { name: 'Beige', hex: '#D9C3A5' },
  { name: 'Bambi', hex: '#C49A6C' }, { name: 'Caramelo', hex: '#A8662F' }, { name: 'Miel', hex: '#C68E3F' }, { name: 'Ocre', hex: '#C08A2E' },
  { name: 'Leopardo', hex: '#B8864B' }, { name: 'Denim', hex: '#4A6A8A' }, { name: 'Gris', hex: '#8E8E8E' }, { name: 'Bronce', hex: '#8C6A3F' },
];

/** "woo_local:123" → "Pedido #123". */
export const referenceLabel = (type?: string | null, id?: string | null) =>
  type === 'woo_order' && id ? `Pedido en línea #${id.split(':').pop()}` : type === 'transfer' && id ? `Transferencia ${id}` : null;

export const TRANSFER_STATUS: Record<string, string> = {
  requested: 'Solicitada', cancelled: 'Cancelada', in_transit: 'En camino', received: 'Recibida', with_difference: 'Con diferencia', closed: 'Cerrada',
};

export const PAYMENT_LABEL: Record<string, string> = { cash: 'Efectivo', card: 'Tarjeta', transfer: 'Transferencia', other: 'Otro' };
export const dinero = (n: number | null | undefined) => `$${Number(n ?? 0).toLocaleString('es-MX', { minimumFractionDigits: 0, maximumFractionDigits: 2 })}`;

/** Swatch for a colour name from the Fuxia palette: exact name, else the first colour of "X con Y", else the longest
 *  palette name it starts with ("Verde aceituna" → Verde aceituna, "Dorado con ocre" → Dorado). Null = no match. */
export function suggestHex(name: string): string | null {
  const n = (x: string) => x.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().trim();
  const target = n(name);
  const byName = new Map(SWATCHES.map((s) => [n(s.name), s.hex]));
  if (byName.has(target)) return byName.get(target)!;
  const first = target.split(/\s+(con|y)\s+/)[0];
  if (byName.has(first)) return byName.get(first)!;
  const starts = SWATCHES.filter((s) => target.startsWith(n(s.name) + ' ')).sort((a, b) => b.name.length - a.name.length)[0];
  return starts?.hex ?? null;
}
