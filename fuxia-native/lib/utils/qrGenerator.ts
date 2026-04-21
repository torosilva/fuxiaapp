const QR_PREFIX = 'FX';

function computeChecksum(value: string): string {
  let sum = 0;
  for (let i = 0; i < value.length; i++) {
    sum = (sum + value.charCodeAt(i) * (i + 1)) & 0xffff;
  }
  return sum.toString(16).padStart(2, '0').slice(-2);
}

export function generateQRCode(customerId: string): string {
  const shortId = customerId.replace(/-/g, '').slice(0, 8);
  const timestamp = Date.now().toString(36);
  const payload = `${shortId}-${timestamp}`;
  const checksum = computeChecksum(payload);
  return `${QR_PREFIX}-${payload}-${checksum}`;
}

export function validateQRCode(qrCode: string): boolean {
  const parts = qrCode.split('-');
  // FX-{shortId}-{timestamp}-{checksum}
  if (parts.length !== 4 || parts[0] !== QR_PREFIX) return false;
  const [, shortId, timestamp, checksum] = parts;
  if (shortId.length !== 8) return false;
  const expected = computeChecksum(`${shortId}-${timestamp}`);
  return checksum === expected;
}

export function extractCustomerShortId(qrCode: string): string | null {
  if (!validateQRCode(qrCode)) return null;
  const parts = qrCode.split('-');
  return parts[1];
}
