import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import webpush from "npm:web-push@3.6.7";

/* =============================================================================
   gv-popup-push — Web Push de los pop-ups de sistema de Luis (v31.08, 15/10/2026).

   La llama SÓLO el trigger trg_gv_popup_push (GV_Popup_Aviso, con la service_role).
   Recibe {aviso_id, dispositivo, sub, titulo, texto}, firma con la VAPID (privada en Vault,
   gv_popup_vapid_priv()) y manda el push a la suscripción del dispositivo destino (el último
   activo de Luis). El resultado (201 / 404 / 410 / error) queda en GV_Popup_Aviso.push_estado y
   GV_Popup_Disp.push_ult_estado; con 404/410 la suscripción venció y se descarta.
   sql/gv_popup_push_v3108.sql
   ============================================================================= */

const SB_URL = Deno.env.get("SUPABASE_URL")!;
const SRK = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const VAPID_PUBLIC = "BBpCCbG1A6f1dz7qZ4A8Wi6rnU7wX6tzZbI4ZOTknJUEJumBL5TY0l4u44GWMeIduyvLb5F0k5xf0ZCEmnl8k0E";
let vapidPriv: string | null = null;

async function rpc(fn: string, body: unknown) {
  const r = await fetch(`${SB_URL}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: { apikey: SRK, Authorization: `Bearer ${SRK}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const t = await r.text();
  if (!r.ok) throw new Error(`${fn} HTTP ${r.status}: ${t.slice(0, 200)}`);
  return t ? JSON.parse(t) : null;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return new Response("POST", { status: 405 });
  // Sólo la service_role (el trigger). El gateway ya validó la firma del JWT (verify_jwt); acá se exige el rol.
  let rol = "";
  try {
    let p = (req.headers.get("authorization") || "").replace(/^Bearer /, "").split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
    p += "===".slice((p.length + 3) % 4);
    rol = JSON.parse(atob(p)).role || "";
  } catch (_e) { /* sin JWT */ }
  if (rol !== "service_role") return new Response("no", { status: 403 });
  let b: { aviso_id?: number; dispositivo?: string; sub?: webpush.PushSubscription; titulo?: string; texto?: string };
  try { b = await req.json(); } catch { return new Response("json", { status: 400 }); }
  if (!b.aviso_id || !b.dispositivo || !b.sub?.endpoint) return new Response("faltan datos", { status: 400 });

  let estado = "error";
  try {
    if (!vapidPriv) vapidPriv = await rpc("gv_popup_vapid_priv", {});
    webpush.setVapidDetails("mailto:loekemeyer.n8n@gmail.com", VAPID_PUBLIC, vapidPriv!);
    const payload = JSON.stringify({ titulo: b.titulo || "Aviso de sistema", texto: b.texto || "", aviso_id: b.aviso_id });
    const r = await webpush.sendNotification(b.sub, payload, { TTL: 3600, urgency: "high" });
    estado = String(r.statusCode || 201);
  } catch (e) {
    const sc = (e as { statusCode?: number }).statusCode;
    estado = sc ? String(sc) : ("error: " + String((e as Error).message || e)).slice(0, 180);
  }
  try { await rpc("gv_popup_push_resultado", { p_aviso: b.aviso_id, p_dispositivo: b.dispositivo, p_estado: estado }); } catch (_e) { /* el registro no frena */ }
  return new Response(JSON.stringify({ estado }), { headers: { "Content-Type": "application/json" } });
});
