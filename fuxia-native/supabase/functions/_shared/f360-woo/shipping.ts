// CRM C7 (Mario 2026-10-08): where a PAID online order ships, for the customer's ficha and demographic analysis.
// Only these fields leave the order (no payment data, no IP, no notes). Shipping address first, billing as fallback.
const MX_STATES: Record<string, string> = {
  AG: 'Aguascalientes', BC: 'Baja California', BS: 'Baja California Sur', CM: 'Campeche', CS: 'Chiapas', CH: 'Chihuahua',
  CX: 'Ciudad de México', CMX: 'Ciudad de México', DF: 'Ciudad de México', CO: 'Coahuila', CL: 'Colima', DG: 'Durango',
  GT: 'Guanajuato', GR: 'Guerrero', HG: 'Hidalgo', JA: 'Jalisco', JAL: 'Jalisco', EM: 'Estado de México', MEX: 'Estado de México',
  MI: 'Michoacán', MO: 'Morelos', NA: 'Nayarit', NL: 'Nuevo León', OA: 'Oaxaca', PU: 'Puebla', QT: 'Querétaro', QR: 'Quintana Roo',
  SL: 'San Luis Potosí', SI: 'Sinaloa', SO: 'Sonora', TB: 'Tabasco', TM: 'Tamaulipas', TL: 'Tlaxcala', VE: 'Veracruz',
  YU: 'Yucatán', ZA: 'Zacatecas',
};
export type OrderShipping = { id: number; status: string; created_at: string | null; name: string | null; phone: string | null; email: string | null;
  street: string | null; neighborhood: string | null; city: string | null; state: string | null; postal_code: string | null; country: string | null };

const str = (x: unknown) => (typeof x === 'string' && x.trim() ? x.trim() : null);

export function orderShipping(o: Record<string, unknown>): OrderShipping {
  const b = (o.billing ?? {}) as Record<string, unknown>;
  const s = (o.shipping ?? {}) as Record<string, unknown>;
  const ship = str(s.address_1) ? s : b;                         // pick ONE address, never mix two
  const country = (str(ship.country) ?? str(b.country))?.toUpperCase() ?? null;
  const rawState = str(ship.state);
  const state = rawState && country === 'MX' ? (MX_STATES[rawState.toUpperCase()] ?? rawState) : rawState;
  const name = [str(ship.first_name) ?? str(b.first_name), str(ship.last_name) ?? str(b.last_name)].filter(Boolean).join(' ') || null;
  const created = str(o.date_created_gmt);
  return {
    id: Number(o.id), status: String(o.status ?? ''), created_at: created ? `${created.replace(' ', 'T')}Z`.replace(/Z+$/, 'Z') : null,
    name, phone: str(s.phone) ?? str(b.phone), email: str(b.email),
    street: str(ship.address_1), neighborhood: str(ship.address_2), city: str(ship.city), state, postal_code: str(ship.postcode), country,
  };
}
