// Supabase Edge Function del proyecto LK (kwkclwhmoygunqmlegrg): gv-est-madre
// Deploy: verify_jwt = false (la identidad es el JWT de GESTIÓN, que la plataforma de LK no
// sabe validar; se valida acá, contra la base de Gestión). Fuente: Gestión Virgilio,
// admin/supabase/gv-est-madre/index.ts — mismo lugar que admin-login-otp.
//
// v25.72 — Tomás Beviglia, 01/10/2026: "me pide código para ver la Est. Madre, que no me lo
// pida en Gestión Virgilio. La página LK dejala como está".
//
// La pestaña EST. MADRE de Stock y Compras embebe admin/admin.html#estadistica-madre (el espejo
// del panel de LK) y hasta la v25.67 entraba con el puente de sesión del admin de LK: si el mail
// no era loekemeyer.n8n@, o si el puente fallaba (el 01/10 a las 12:14 Gestión dio 521), el
// iframe pedía el código OTP. Esta puerta reemplaza esa sesión SÓLO para la Est. Madre:
//   1. acepta pedidos sólo desde Gestión (GitHub Pages y Vercel, por CORS);
//   2. el Authorization trae el JWT del supervisor en GESTIÓN, y la base de Gestión dice si es
//      supervisor (public.es_supervisor_virgilio(): los 3 mails fijos + Supervisores_Virgilio);
//   3. devuelve, con service_role de LK, lo ÚNICO que lee la Est. Madre. El navegador no elige
//      columnas, filtros ni tablas: cada nombre tiene su consulta fija. Todo lo demás, 403.
// No se crea ninguna sesión de admin de LK: el panel LK (Panel Web LK) sigue con su código.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const ORIGENES = new Set(["https://loekemeyer.github.io", "https://gestion-virgilio.vercel.app"]);

// Base de Gestión: sólo para preguntar si el JWT es de un supervisor. Clave pública por diseño.
const VIRGILIO_URL = "https://hrxfctzncixxqmpfhskv.supabase.co";
const VIRGILIO_KEY = "sb_publishable_BqpAgZH6ty-9wft10_YMhw_0rcIPuWT";

const LK_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SRV = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

// Lo que lee de LK la Est. Madre (est-madre.js, el módulo ÚNICO de LK y Gestión, v25.79).
// Consulta fija por nombre. La lista de artículos y la Est Madre no pasan por acá: salen de
// stocks_carga_rapida de Gestión, que el módulo lee con la clave pública de Gestión.
const TABLAS: Record<string, string> = {
  "products": "products?select=cod,description,uxb,active,category&order=cod.asc",
  "loke_products": "loke_products?select=cod,description,uxb&order=cod.asc",
  // Ventas por mes en cajas, por (artículo, empresa). La función deja pasar a service_role
  // (además de los admins de LK): esta puerta ya validó que el JWT es de un supervisor.
  "rpc/get_estadistica_madre_mensual":
    "rpc/get_estadistica_madre_mensual?select=item,empresa,meses&order=item.asc,empresa.asc",
};
// El detalle de una celda (mostrarDetalleVentaMadre): no tiene chequeo de admins adentro.
const RPC_DETALLE = "rpc/get_estadistica_madre_detail";

function cors(origin: string | null): Record<string, string> {
  const h: Record<string, string> = {
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Vary": "Origin",
  };
  if (origin && ORIGENES.has(origin)) h["Access-Control-Allow-Origin"] = origin;
  return h;
}

function json(body: unknown, status: number, origin: string | null): Response {
  return new Response(JSON.stringify(body), {
    status, headers: { ...cors(origin), "Content-Type": "application/json" },
  });
}

// token -> vence (ms). Una carga de la Est. Madre son 3 pedidos: sin esto, 3 viajes a Gestión.
const vistos = new Map<string, number>();

// true = supervisor · false = no lo es / token vencido · null = Gestión no contestó.
async function esSupervisor(tok: string): Promise<boolean | null> {
  const v = vistos.get(tok);
  if (v && v > Date.now()) return true;
  let r: Response;
  try {
    r = await fetch(`${VIRGILIO_URL}/rest/v1/rpc/es_supervisor_virgilio`, {
      method: "POST", body: "{}",
      headers: { apikey: VIRGILIO_KEY, Authorization: `Bearer ${tok}`, "Content-Type": "application/json" },
    });
  } catch (_) { return null; }
  if (r.status === 401 || r.status === 403) return false;
  if (!r.ok) { console.error(`[gv-est-madre] gestion ${r.status} ${(await r.text()).slice(0, 160)}`); return null; }
  const es = await r.json().catch(() => false);
  if (es !== true) return false;
  if (vistos.size > 300) vistos.clear();
  vistos.set(tok, Date.now() + 120_000);
  return true;
}

const srvHeaders = () => ({ apikey: SRV, Authorization: `Bearer ${SRV}` });

// PostgREST corta en 1000 filas sin avisar: se pagina hasta una página corta.
async function leerTodo(q: string): Promise<unknown[]> {
  const out: unknown[] = [];
  for (let off = 0; off < 100_000; off += 1000) {
    const r = await fetch(`${LK_URL}/rest/v1/${q}&limit=1000&offset=${off}`, { headers: srvHeaders() });
    if (!r.ok) throw new Error(`LK ${r.status}: ${(await r.text()).slice(0, 200)}`);
    const page = await r.json();
    if (!Array.isArray(page)) throw new Error("LK devolvió algo que no es una lista");
    out.push(...page);
    if (page.length < 1000) break;
  }
  return out;
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("origin");
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors(origin) });
  if (req.method !== "POST") return json({ message: "método no permitido" }, 405, origin);
  if (!origin || !ORIGENES.has(origin)) return json({ message: "origen no permitido" }, 403, origin);

  let body: { path?: string; args?: Record<string, unknown> } = {};
  try { body = await req.json(); } catch (_) { return json({ message: "pedido inválido" }, 400, origin); }
  const path = String(body.path ?? "");
  if (!(path in TABLAS) && path !== RPC_DETALLE) {
    return json({ message: "La Est. Madre de Gestión no lee " + path.slice(0, 60) }, 403, origin);
  }

  const tok = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "").trim();
  if (!tok) return json({ message: "Sin sesión de Gestión: volvé a entrar a Gestión Virgilio." }, 401, origin);
  const sup = await esSupervisor(tok);
  if (sup === null) return json({ message: "Gestión no contesta. Probá de nuevo en un minuto." }, 502, origin);
  if (!sup) return json({ message: "Sólo supervisores de Gestión (o la sesión venció: recargá Gestión)." }, 403, origin);

  try {
    if (path === RPC_DETALLE) {
      const a = body.args ?? {};
      const item = typeof a.p_item_code === "string" ? a.p_item_code.trim().slice(0, 40) : "";
      const ym = typeof a.p_ym === "string" && /^\d{4}-\d{2}$/.test(a.p_ym) ? a.p_ym : "";
      if (!item || !ym) return json({ message: "parámetros inválidos" }, 400, origin);
      const r = await fetch(`${LK_URL}/rest/v1/${RPC_DETALLE}`, {
        method: "POST",
        headers: { ...srvHeaders(), "Content-Type": "application/json" },
        body: JSON.stringify({ p_item_code: item, p_ym: ym }),
      });
      const t = await r.text();
      return new Response(t, { status: r.status, headers: { ...cors(origin), "Content-Type": "application/json" } });
    }
    return json(await leerTodo(TABLAS[path]), 200, origin);
  } catch (e) {
    console.error("[gv-est-madre]", path, e);
    return json({ message: "No se pudo leer la Est. Madre: " + String((e as Error).message ?? e).slice(0, 200) }, 502, origin);
  }
});
