/**
 * Helpers de cliente para el flujo de aprobación de inventario.
 *
 * Se usa desde /vendedora/inventory (+/- de stock) y /inventory/bulk-add
 * (alta por lote) para pinchar la edge function que manda push a las admin
 * apenas la vendedora crea una solicitud.
 */
import { supabase } from '@/lib/supabase';

const SUPABASE_URL = process.env.EXPO_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY!;

/**
 * Dispara el push a las admins de que hay una nueva solicitud pendiente.
 * Best-effort: si falla, no rompe el flujo — la solicitud ya está en DB y
 * la admin la va a ver la próxima vez que abra el panel.
 */
export async function notifyApprovalPending(requestId: string): Promise<void> {
  try {
    const { data: { session } } = await supabase.auth.getSession();
    await fetch(`${SUPABASE_URL}/functions/v1/notify-approval-pending`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${session?.access_token ?? SUPABASE_ANON_KEY}`,
      },
      body: JSON.stringify({ request_id: requestId }),
    });
  } catch (err) {
    // Silencioso — no vale la pena molestar al usuario si el push falla.
    console.warn('[notifyApprovalPending] failed:', err);
  }
}
