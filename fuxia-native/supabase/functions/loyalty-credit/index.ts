// ═══════════════════════════════════════════════════════════════════
// Fuxia Loyalty — Edge Function: loyalty-credit
// Acredita puntos a un número de WhatsApp SIN pedido asociado.
// Escrita contra el esquema real: customers / loyalty_cards / transactions
//
// Archivo: supabase/functions/loyalty-credit/index.ts
//
// Contrato:
//   POST  https://tgzgiwfzddsghnxgkcqd.supabase.co/functions/v1/loyalty-credit
//   Header: x-fuxia-secret: <FUXIA_CREDIT_SECRET>
//   Body:   { "telefono": "5512345678", "pais": "MX", "puntos": 100,
//             "motivo": "popup-bienvenida", "email": "ella@correo.com" }
//
//   200 → { ok:true, estado:"acreditado"|"pendiente"|"duplicado", telefono, puntos }
//   4xx → { ok:false, error:"..." }
//
// Despliegue:
//   supabase functions deploy loyalty-credit --no-verify-jwt
//   supabase secrets set FUXIA_CREDIT_SECRET="$(openssl rand -hex 32)"
//
//   --no-verify-jwt es obligatorio: quien llama es WordPress, que no
//   tiene JWT de Supabase. La autenticación la da el header secreto.
//
// Comportamiento de los triggers (verificado 20 sep 2026):
//   - NINGÚN trigger suma points_earned a total_points. Insertar en
//     transactions NO mueve el saldo, por eso esta función llama a
//     fx_add_points (ver loyalty-credit-setup.sql, PASO 1).
//   - trg_update_purchase_stats solo actúa si pairs_in_order > 0.
//     Aquí va en 0, así que el regalo no cuenta como compra ni infla
//     el contador de pares.
//   - update_loyalty_tier recalcula el nivel solo al mover total_points
//     (>= 300 silver, >= 900 gold).
// ═══════════════════════════════════════════════════════════════════

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const MAX_PUNTOS = 500; // tope de seguridad por llamada

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "content-type, x-fuxia-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function responder(cuerpo: unknown, status = 200) {
  return new Response(JSON.stringify(cuerpo), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

/** Normaliza a E.164, como se guarda en customers.phone (+525554548607) */
function normalizarTelefono(entrada: string, pais: string): string | null {
  if (!entrada) return null;
  const lada = pais === "CO" ? "57" : "52";
  const tieneMas = entrada.trim().startsWith("+");
  const d = entrada.replace(/\D/g, "");
  if (!d) return null;

  if (tieneMas) return "+" + d;
  if (d.length === 10) return "+" + lada + d;                          // 10 dígitos MX/CO
  if (d.length > 10 && (d.startsWith("52") || d.startsWith("57"))) return "+" + d;
  if (d.length === 11 && d.startsWith("1")) return "+" + lada + d.slice(1); // MX viejo 1+10
  return null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return responder({ ok: false, error: "Usa POST" }, 405);

  // ── 1. Autenticación ──
  const secreto = Deno.env.get("FUXIA_CREDIT_SECRET");
  if (!secreto) return responder({ ok: false, error: "FUXIA_CREDIT_SECRET no configurado" }, 500);
  if (req.headers.get("x-fuxia-secret") !== secreto) {
    return responder({ ok: false, error: "No autorizado" }, 401);
  }

  // ── 2. Validar entrada ──
  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return responder({ ok: false, error: "JSON inválido" }, 400);
  }

  const pais = String(body.pais ?? "MX").toUpperCase() === "CO" ? "CO" : "MX";
  const moneda = pais === "CO" ? "COP" : "MXN";
  const telefono = normalizarTelefono(String(body.telefono ?? ""), pais);
  const puntos = Number(body.puntos ?? 0);
  const motivo = String(body.motivo ?? "popup-bienvenida").slice(0, 120);
  const email = body.email ? String(body.email).slice(0, 190) : null;

  if (!telefono) return responder({ ok: false, error: "Teléfono inválido" }, 400);
  if (!Number.isInteger(puntos) || puntos <= 0 || puntos > MAX_PUNTOS) {
    return responder({ ok: false, error: `puntos debe ser entero entre 1 y ${MAX_PUNTOS}` }, 400);
  }

  // Idempotencia: si el pop-up reintenta, no se acredita dos veces
  const idemKey = String(body.idem_key ?? `${motivo}:${telefono}`).slice(0, 200);

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  // ── 3. ¿Ya se registró este crédito antes? ──
  const { data: previo } = await supabase
    .from("pending_credits")
    .select("id, points, applied_at")
    .eq("idem_key", idemKey)
    .maybeSingle();

  if (previo) {
    return responder({
      ok: true,
      estado: "duplicado",
      mensaje: "Ese crédito ya estaba registrado",
      telefono,
      puntos: previo.points,
      aplicado: previo.applied_at !== null,
    });
  }

  // ── 4. ¿Ya tiene cuenta en la app? ──
  const { data: cliente, error: errCliente } = await supabase
    .from("customers")
    .select("id, country")
    .eq("phone", telefono)
    .maybeSingle();

  if (errCliente) {
    return responder({ ok: false, error: "Error consultando customers: " + errCliente.message }, 500);
  }

  // ── 5a. Tiene cuenta → transacción directa sobre su tarjeta ──
  if (cliente) {
    const { data: tarjeta, error: errTarjeta } = await supabase
      .from("loyalty_cards")
      .select("id")
      .eq("customer_id", cliente.id)
      .maybeSingle();

    if (errTarjeta) {
      return responder({ ok: false, error: "Error consultando loyalty_cards: " + errTarjeta.message }, 500);
    }

    if (tarjeta) {
      const monedaCliente = (cliente.country ?? pais) === "CO" ? "COP" : "MXN";

      // amount = 0 porque no hay compra. points_earned queda como registro.
      const { error: errMov } = await supabase.from("transactions").insert({
        loyalty_card_id: tarjeta.id,
        wc_order_id: null,
        amount: 0,
        currency: monedaCliente,
        points_earned: puntos,
        pairs_in_order: 0,        // no es un par comprado: no infla pairs_count
        channel: "popup",         // así se puede excluir de métricas de venta
        status: "completed",
        notes: motivo,
      });

      if (errMov) {
        return responder({ ok: false, error: "Error insertando la transacción: " + errMov.message }, 500);
      }

      // La transacción no mueve el saldo: hay que sumarlo aparte.
      // fx_add_points lo hace atómico y dispara el recálculo de tier.
      const { data: nuevoTotal, error: errSuma } = await supabase.rpc("fx_add_points", {
        p_card_id: tarjeta.id,
        p_points: puntos,
      });

      if (errSuma) {
        return responder({
          ok: false,
          error: "Transacción creada pero el saldo NO se actualizó: " + errSuma.message,
          pista: "¿Corriste el PASO 1 del SQL (fx_add_points)?",
          revisar_transaccion_de: telefono,
        }, 500);
      }

      await supabase.from("pending_credits").insert({
        phone: telefono, points: puntos, motivo, origen: "popup",
        idem_key: idemKey, email, country: pais, applied_at: new Date().toISOString(),
      });

      return responder({
        ok: true,
        estado: "acreditado",
        mensaje: "Puntos acreditados a una cuenta existente",
        telefono,
        puntos,
        total_points: nuevoTotal,
      });
    }
    // Cliente sin tarjeta: cae al pendiente y el trigger la aplicará al crearse
  }

  // ── 5b. Sin cuenta todavía → queda apartado a ese número ──
  const { error: errPend } = await supabase.from("pending_credits").insert({
    phone: telefono, points: puntos, motivo, origen: "popup",
    idem_key: idemKey, email, country: pais, applied_at: null,
  });

  if (errPend) {
    return responder({ ok: false, error: "Error guardando el pendiente: " + errPend.message }, 500);
  }

  return responder({
    ok: true,
    estado: "pendiente",
    mensaje: "Sin cuenta todavía: los puntos quedan apartados a ese número",
    telefono,
    puntos,
    moneda,
  });
});
