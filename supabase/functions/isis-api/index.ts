// isis-api — API de salida hacia el ERP ISIS (idea 5547 · ticket TkT115966).
//
// v2.0 (2026-09-08, reunión 04/09): el pedido viaja como JSON y la clave es la
// REFERENCIA (la etiqueta de la NP, "LK 0011"), NO una NP numérica. La NP la pone
// ISIS al facturar. Sin acuse (el vínculo factura↔pedido lo resuelve nuestro parseo).
// ISIS consulta esta API (request SALIENTE desde su LAN) → del lado del depósito no
// hace falta Windows Server, IIS, IP pública ni abrir puertos.
//
// Endpoints (base: https://<proj>.supabase.co/functions/v1/isis-api):
//   GET  /ping                       → healthcheck
//   GET  /pedidos                    → cabeceras por estado (?estado=&empresa=&desde=&limit=)
//   GET  /pedidos/{referencia}       → JSON completo del pedido (lo pasa a "entregado")
// Todas aceptan también el prefijo /v1 y /v2 (…/isis-api/v2/pedidos).
//
// Sólo se ofrecen los pedidos WEB (referencias LK/CH ####): los NP numéricos ya están
// cargados en ISIS y no se le devuelven (evita doble carga). Estados: pendiente /
// entregado / anulado.
//
// Auth: header `X-API-Key: <token>` (o `Authorization: Bearer <token>`).
// En la base se guarda SOLO el SHA-256 del token (tabla isis_api_tokens).
// verify_jwt = OFF: la función implementa su propia autenticación por token.
// DDL y RPCs v2.0: sql/gv_isis_api_v2.sql. Especificación: docs/ISIS-API-ESPECIFICACION.md
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const SB_URL = Deno.env.get("SUPABASE_URL") || "";
const SB_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const VERSION = "2.0";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-api-key, content-type, apikey",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", ...CORS },
  });
}
function fail(status: number, codigo: string, error: string): Response {
  return json({ ok: false, codigo, error }, status);
}

async function sha256Hex(s: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

// Llama una RPC de Postgres con service_role.
async function rpc<T = unknown>(fn: string, args: Record<string, unknown>): Promise<T> {
  const r = await fetch(`${SB_URL}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: {
      apikey: SB_KEY,
      Authorization: `Bearer ${SB_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(args),
  });
  if (!r.ok) throw new Error(`rpc ${fn} ${r.status}: ${(await r.text()).slice(0, 300)}`);
  return (await r.json()) as T;
}

function tokenDeRequest(req: Request): string {
  const k = req.headers.get("x-api-key");
  if (k && k.trim()) return k.trim();
  const a = req.headers.get("authorization") || "";
  const m = a.match(/^Bearer\s+(.+)$/i);
  return m ? m[1].trim() : "";
}

// /functions/v1/isis-api/v2/pedidos/LK%200011 → ["pedidos","LK 0011"]
function segmentos(pathname: string): string[] {
  const p = pathname.split("/").filter(Boolean).map((s) => {
    try { return decodeURIComponent(s); } catch { return s; }
  });
  const i = p.indexOf("isis-api");
  const resto = i >= 0 ? p.slice(i + 1) : p;
  return (resto[0] === "v1" || resto[0] === "v2") ? resto.slice(1) : resto;
}

// Referencia: "LK 0011" / "CH 7" (con o sin espacio), opcionalmente "-bloque".
const REF_RE = /^(LK|CH)\s?\d{1,6}(-\d+)?$/i;

Deno.serve(async (req: Request) => {
  const t0 = Date.now();
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  const url = new URL(req.url);
  const seg = segmentos(url.pathname);
  const ruta = "/" + seg.join("/");
  const ip = req.headers.get("x-forwarded-for") || "";

  // ── autenticación ────────────────────────────────────────────────────
  const token = tokenDeRequest(req);
  if (!token) {
    return fail(401, "sin_token", "Falta el token. Enviar el header X-API-Key.");
  }
  let auth: { id: number; nombre: string; solo_lectura: boolean } | null = null;
  try {
    auth = await rpc("isis_api_token_check", { p_hash: await sha256Hex(token) });
  } catch (e) {
    console.error("token_check", e);
    return fail(503, "backend", "No se pudo validar el token. Reintentar.");
  }
  if (!auth) return fail(401, "token_invalido", "Token inválido o dado de baja.");

  const log = (status: number, ref?: string, detalle?: unknown) =>
    rpc("isis_api_log_write", {
      p_token_id: auth!.id, p_nombre: auth!.nombre, p_metodo: req.method,
      p_ruta: ruta, p_np: ref ?? null, p_status: status, p_ms: Date.now() - t0,
      p_ip: ip, p_detalle: detalle ?? null,
    }).catch(() => {});

  try {
    // ── GET /ping ──────────────────────────────────────────────────────
    if (req.method === "GET" && (seg.length === 0 || seg[0] === "ping")) {
      await log(200);
      return json({
        ok: true,
        servicio: "Producción Virgilio — API pedidos armados (v2.0)",
        version: VERSION,
        cliente: auth.nombre,
        hora: new Date().toISOString(),
      });
    }

    // ── GET /pedidos ───────────────────────────────────────────────────
    if (req.method === "GET" && seg[0] === "pedidos" && seg.length === 1) {
      const estado = (url.searchParams.get("estado") || "pendiente").toLowerCase();
      const empresa = url.searchParams.get("empresa");
      const desde = url.searchParams.get("desde");
      const limit = parseInt(url.searchParams.get("limit") || "100", 10);
      const ESTADOS = ["pendiente", "entregado", "anulado"];
      if (!ESTADOS.includes(estado)) {
        await log(400);
        return fail(400, "estado_invalido", `estado debe ser uno de: ${ESTADOS.join(", ")}`);
      }
      const pedidos = await rpc<unknown[]>("gv_isis_pedidos_lista", {
        p_estado: estado,
        p_empresa: empresa || null,
        p_desde: desde || null,
        p_limit: Number.isFinite(limit) ? limit : 100,
      });
      const total = Array.isArray(pedidos) ? pedidos.length : 0;
      await log(200, undefined, { estado, total });
      return json({ ok: true, estado, total, pedidos });
    }

    // ── GET /pedidos/{referencia} ──────────────────────────────────────
    if (req.method === "GET" && seg[0] === "pedidos" && seg.length === 2) {
      const ref = seg[1];
      if (!REF_RE.test(ref)) {
        await log(400, ref);
        return fail(400, "referencia_invalida", "La referencia debe ser tipo 'LK 0011' o 'CH 0007'.");
      }
      const marcar = url.searchParams.get("marcar") !== "false";
      const pedido = await rpc<unknown>("gv_isis_pedido_json", { p_ref: ref });
      if (!pedido) {
        await log(404, ref);
        return fail(404, "no_encontrado", `La referencia ${ref} no está publicada como pedido armado.`);
      }
      if (marcar) {
        try { await rpc("gv_isis_pedido_marcar_entregado", { p_ref: ref }); } catch (_e) { /* no romper la entrega */ }
      }
      await log(200, ref, { marcar });
      return json({ ok: true, pedido });
    }

    await log(404);
    return fail(404, "ruta_desconocida", `Ruta no reconocida: ${req.method} ${ruta}`);
  } catch (e) {
    console.error("isis-api", e);
    await log(500, undefined, { error: String(e).slice(0, 300) });
    return fail(500, "error_interno", "Error interno. Reintentar más tarde.");
  }
});
