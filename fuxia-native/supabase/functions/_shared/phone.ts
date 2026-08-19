// Normaliza teléfonos a E.164 usando el país del pedido (billing.country).
// Antes se asumía +52 para todo número de 10 dígitos: un número colombiano
// como 3112548055 quedaba como +523112548055 — inexistente, y encima puede
// ser el número real de alguien más en México. Devuelve null si no valida,
// a propósito: mejor sin teléfono que con uno inventado.
import { parsePhoneNumberFromString } from 'https://esm.sh/libphonenumber-js@1.11.17';

export function normalizePhone(raw?: string | null, country?: string | null): string | null {
  if (!raw) return null;
  const trimmed = String(raw).trim();
  let digits = trimmed.replace(/\D/g, '');
  if (!digits) return null;
  // Legado MX: móviles con el "1" viejo tras el 52 (Twilio aún los manda así).
  if (digits.length === 13 && digits.startsWith('521')) digits = `52${digits.slice(3)}`;
  const region = /^[a-z]{2}$/i.test(country ?? '') ? String(country).toUpperCase() : undefined;
  const attempts: Array<[string, string | undefined]> = [];
  if (trimmed.startsWith('+')) attempts.push([`+${digits}`, undefined]);
  if (region) attempts.push([digits, region]);
  attempts.push([`+${digits}`, undefined]);
  for (const [value, hint] of attempts) {
    const parsed = parsePhoneNumberFromString(value, hint as never);
    if (parsed && parsed.isValid()) return parsed.number;
  }
  return null;
}
