// isis-api — API de salida hacia el ERP ISIS (idea 5547 · ticket 1159666).
//
// Qué hace: expone los PEDIDOS TERMINADOS de Producción Virgilio (las NP que la
// operadora tildó en Facturación) para que ISIS los baje y los facture solo.
// ISIS consulta esta API (request SALIENTE desde su LAN) → del lado del depósito
// no hace falta Windows Server, IIS, IP pública ni abrir puertos.
//
// Endpoints (base: https://<proj>.supabase.co/functions/v1/isis-api):
//   GET  /ping                      → healthcheck
//   GET  /pedidos                   → cabeceras por estado (?estado=&empresa=&desde=&limit=)
//   GET  /pedidos/{np}              → JSON completo del pedido (lo pasa a "entregado")
//   POST /pedidos/{np}/acuse        → ISIS confirma qué hizo con el pedido
//   POST /acuse                     → idem, con la NP en el body
// Todas aceptan también el prefijo /v1 (…/isis-api/v1/pedidos).
//
// Auth: header `X-API-Key: <token>` (o `Authorization: Bearer <token>`).
// En la base se guarda SOLO el SHA-256 del token (tabla isis_api_tokens).
//
// verify_jwt = OFF: la función implementa su propia autenticación por token.
// DDL y RPCs: sql/isis_api.sql. Especificación para ISIS: docs/ISIS-API-ESPECIFICACION.md
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const SB_URL = Deno.env.get("SUPABASE_URL") || "";
const SB_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const VERSION = "1.0";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-api-key, content-type, apikey",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
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

// /functions/v1/isis-api/v1/pedidos/44604 → ["pedidos","44604"]
function segmentos(pathname: string): string[] {
  const p = pathname.split("/").filter(Boolean);
  const i = p.indexOf("isis-api");
  const resto = i >= 0 ? p.slice(i + 1) : p;
  return resto[0] === "v1" ? resto.slice(1) : resto;
}

const NP_RE = /^\d{1,12}$/;

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

  const log = (status: number, np?: string, detalle?: unknown) =>
    rpc("isis_api_log_write", {
      p_token_id: auth!.id, p_nombre: auth!.nombre, p_metodo: req.method,
      p_ruta: ruta, p_np: np ?? null, p_status: status, p_ms: Date.now() - t0,
      p_ip: ip, p_detalle: detalle ?? null,
    }).catch(() => {});

  try {
    // ── GET /ping ──────────────────────────────────────────────────────
    if (req.method === "GET" && (seg.length === 0 || seg[0] === "ping")) {
      await log(200);
      return json({
        ok: true,
        servicio: "Producción Virgilio — API pedidos terminados",
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
      const ESTADOS = ["pendiente", "entregado", "procesado", "error", "anulado"];
      if (!ESTADOS.includes(estado)) {
        await log(400);
        return fail(400, "estado_invalido", `estado debe ser uno de: ${ESTADOS.join(", ")}`);
      }
      const pedidos = await rpc<unknown[]>("isis_api_pendientes", {
        p_estado: estado,
        p_empresa: empresa || null,
        p_desde: desde || null,
        p_limit: Number.isFinite(limit) ? limit : 100,
      });
      await log(200, undefined, { estado, total: pedidos.length });
      return json({ ok: true, estado, total: pedidos.length, pedidos });
    }

    // ── GET /pedidos/{np} ──────────────────────────────────────────────
    if (req.method === "GET" && seg[0] === "pedidos" && seg.length === 2) {
      const np = seg[1];
      if (!NP_RE.test(np)) {
        await log(400, np);
        return fail(400, "np_invalida", "La NP debe ser numérica.");
      }
      const marcar = url.searchParams.get("marcar") !== "false";
      const pedido = await rpc<unknown>("isis_api_pedido", { p_np: np, p_marcar: marcar });
      if (!pedido) {
        await log(404, np);
        return fail(404, "no_encontrado", `La NP ${np} no está publicada como pedido terminado.`);
      }
      await log(200, np, { marcar });
      return json({ ok: true, pedido });
    }

    // ── POST /pedidos/{np}/acuse  |  POST /acuse ───────────────────────
    const esAcuseRuta = seg[0] === "pedidos" && seg.length === 3 && seg[2] === "acuse";
    if (req.method === "POST" && (esAcuseRuta || seg[0] === "acuse")) {
      let body: Record<string, unknown> = {};
      try {
        body = await req.json();
      } catch {
        await log(400);
        return fail(400, "json_invalido", "El cuerpo debe ser JSON.");
      }
      const np = String(esAcuseRuta ? seg[1] : (body.np ?? "")).trim();
      if (!NP_RE.test(np)) {
        await log(400, np);
        return fail(400, "np_invalida", "Falta la NP o no es numérica.");
      }
      const resultado = String(body.resultado ?? "").toLowerCase();
      if (resultado !== "ok" && resultado !== "error") {
        await log(400, np);
        return fail(400, "resultado_invalido", 'El campo "resultado" debe ser "ok" o "error".');
      }
      const r = await rpc<{ ok: boolean; error?: string; duplicado?: boolean }>("isis_api_acuse", {
        p_np: np,
        p_resultado: resultado,
        p_nro: body.nro_comprobante ? String(body.nro_comprobante) : null,
        p_cae: body.cae ? String(body.cae) : null,
        p_error: body.error_detalle ? String(body.error_detalle) : null,
      });
      if (!r?.ok) {
        await log(404, np, r);
        return fail(404, "no_encontrado", r?.error || "No se pudo registrar el acuse.");
      }
      await log(200, np, r);
      return json(r);
    }

    await log(404);
    return fail(404, "ruta_desconocida", `Ruta no reconocida: ${req.method} ${ruta}`);
  } catch (e) {
    console.error("isis-api", e);
    await log(500, undefined, { error: String(e).slice(0, 300) });
    return fail(500, "error_interno", "Error interno. Reintentar más tarde.");
  }
});
