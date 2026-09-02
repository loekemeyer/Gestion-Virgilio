// sync-clientes-dto — refresca public.clientes_dto (dto_vol por cliente) desde los DOS padrones:
//   1. LK    customers.dto_vol (WEB_SERVICE_KEY, service_role de LK)  -> empresa='lk'
//   2. Chef  customers.dto_vol (CHEF_KEY, publishable key de Chef)    -> empresa='chef'
// Idempotente. Lo dispara pg_cron cada 14 dias (job sync-clientes-dto-14d).
// clientes_dto tiene PK compuesta (cod_cliente, empresa): las numeraciones de LK y Chef son
// INDEPENDIENTES (mismo codigo = otro cliente en cada empresa), asi que el dto se resuelve por
// (codigo, empresa). El join de facturacion deriva la empresa de la NP (^9 = lk, resto = chef).
// Secrets (ya existentes, los usan arca-wsfe / sync-precios-venta): WEB_SERVICE_KEY = service_role
// de LK, WEB_SUPABASE_URL = url de LK, CHEF_SUPABASE_URL / CHEF_KEY = url + publishable key de Chef.
// SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY los inyecta Supabase.
// verify_jwt = OFF (endpoint interno idempotente; solo pulls -> upsert). Deploy manual/MCP.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const LK_URL = Deno.env.get("WEB_SUPABASE_URL") || "https://kwkclwhmoygunqmlegrg.supabase.co";
const LK_KEY = Deno.env.get("WEB_SERVICE_KEY") || "";
const CHEF_URL = Deno.env.get("CHEF_SUPABASE_URL") || "https://nkhzocgdpwtgrmwleihr.supabase.co";
const CHEF_KEY = Deno.env.get("CHEF_KEY") || "sb_publishable_aThHtJLBKytg9k_6UdH2Eg_Use7f1zH";
const SB_URL = Deno.env.get("SUPABASE_URL") || "";
const SB_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const PAGE = 1000;

function json(b: unknown, s = 200): Response {
  return new Response(JSON.stringify(b), { status: s, headers: { "Content-Type": "application/json" } });
}

interface Cust { cod_cliente: string | number | null; dto_vol: number | null }

// Lee TODO customers de un padron (paginado; PostgREST corta en 1000/pagina) y
// devuelve el mapa cod_cliente -> dto_vol (dedup, normalizado).
async function fetchDtos(baseUrl: string, key: string): Promise<Map<string, number>> {
  const seen = new Map<string, number>();
  let offset = 0;
  while (true) {
    const url = baseUrl + "/rest/v1/customers?select=cod_cliente,dto_vol&order=cod_cliente.asc" +
      "&limit=" + PAGE + "&offset=" + offset;
    const r = await fetch(url, { headers: { apikey: key, Authorization: "Bearer " + key } });
    if (!r.ok) throw new Error("REST " + r.status + ": " + (await r.text()).slice(0, 200));
    const page: Cust[] = await r.json();
    for (const x of page) {
      if (!x || x.cod_cliente == null) continue;
      seen.set(String(x.cod_cliente), Number(x.dto_vol) || 0);
    }
    if (page.length < PAGE) break;
    offset += PAGE;
    if (offset > 100000) break; // guarda anti-loop
  }
  return seen;
}

Deno.serve(async (_req: Request): Promise<Response> => {
  try {
    if (!LK_KEY) return json({ ok: false, error: "falta WEB_SERVICE_KEY" }, 501);

    const nowIso = new Date().toISOString();

    // ── 1) LK (obligatorio) ──
    const lk = await fetchDtos(LK_URL, LK_KEY);
    if (!lk.size) return json({ ok: false, error: "LK devolvio 0 clientes" }, 502);

    // ── 2) Chef (best-effort: si falla, se sigue con LK y se logea) ──
    let chef = new Map<string, number>();
    let chefError = "";
    if (CHEF_KEY) {
      try {
        chef = await fetchDtos(CHEF_URL, CHEF_KEY);
      } catch (e) {
        chefError = String((e as Error)?.message || e).slice(0, 200);
      }
    }

    // ── 3) Filas con empresa; PK compuesta (cod_cliente, empresa) ──
    const upserts: { cod_cliente: string; empresa: string; dto_vol: number; actualizado: string }[] = [];
    for (const [cod_cliente, dto_vol] of lk) upserts.push({ cod_cliente, empresa: "lk", dto_vol, actualizado: nowIso });
    for (const [cod_cliente, dto_vol] of chef) upserts.push({ cod_cliente, empresa: "chef", dto_vol, actualizado: nowIso });

    // ── 4) upsert en Virgilio (merge-duplicates por PK compuesta) ──
    const batchSize = 500;
    let total = 0;
    for (let i = 0; i < upserts.length; i += batchSize) {
      const batch = upserts.slice(i, i + batchSize);
      const w = await fetch(SB_URL + "/rest/v1/clientes_dto?on_conflict=cod_cliente,empresa", {
        method: "POST",
        headers: {
          apikey: SB_KEY, Authorization: "Bearer " + SB_KEY,
          "Content-Type": "application/json",
          Prefer: "resolution=merge-duplicates,return=minimal",
        },
        body: JSON.stringify(batch),
      });
      if (!w.ok) return json({ ok: false, error: "Virgilio upsert " + w.status, detail: (await w.text()).slice(0, 300) }, 502);
      total += batch.length;
    }

    return json({ ok: true, sincronizados: total, lk: lk.size, chef: chef.size, chef_error: chefError || undefined, ts: nowIso });
  } catch (e) {
    return json({ ok: false, error: String((e as Error)?.message || e).slice(0, 300) }, 500);
  }
});
