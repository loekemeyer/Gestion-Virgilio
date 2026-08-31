// sync-precios-venta — refresca precios_venta y cob_uxb_lk desde:
//   1. LK products + loke_products (WEB_SERVICE_KEY)
//   2. Chef products (CHEF_KEY — publishable key, lectura pública)
// Idempotente. Lo dispara pg_cron (job sync-precios-venta).
// Secrets (ya existentes, los usa arca-wsfe y sync-clientes-dto):
//   WEB_SERVICE_KEY    = service_role de LK
//   WEB_SUPABASE_URL   = url de LK
//   CHEF_SUPABASE_URL  = url de Chef (default hardcoded)
//   CHEF_KEY           = publishable key de Chef (default hardcoded)
//   SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY los inyecta Supabase.
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

interface Product { cod: string; list_price: number | null; uxb: number | null; description: string | null }

async function fetchAll(baseUrl: string, key: string, table: string, select: string): Promise<Product[]> {
  const all: Product[] = [];
  let offset = 0;
  while (true) {
    const url = `${baseUrl}/rest/v1/${table}?select=${select}&order=cod.asc&limit=${PAGE}&offset=${offset}`;
    const r = await fetch(url, { headers: { apikey: key, Authorization: `Bearer ${key}` } });
    if (!r.ok) throw new Error(`REST ${table}@${baseUrl.split("//")[1]?.slice(0,12)} ${r.status}: ${(await r.text()).slice(0, 300)}`);
    const page: Product[] = await r.json();
    all.push(...page);
    if (page.length < PAGE) break;
    offset += PAGE;
    if (offset > 100000) break;
  }
  return all;
}

async function upsert(table: string, conflict: string, rows: Record<string, unknown>[]): Promise<number> {
  if (!rows.length) return 0;
  const batchSize = 500;
  let total = 0;
  for (let i = 0; i < rows.length; i += batchSize) {
    const batch = rows.slice(i, i + batchSize);
    const w = await fetch(`${SB_URL}/rest/v1/${table}?on_conflict=${conflict}`, {
      method: "POST",
      headers: {
        apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}`,
        "Content-Type": "application/json",
        Prefer: "resolution=merge-duplicates,return=minimal",
      },
      body: JSON.stringify(batch),
    });
    if (!w.ok) throw new Error(`Virgilio upsert ${table} ${w.status}: ${(await w.text()).slice(0, 300)}`);
    total += batch.length;
  }
  return total;
}

Deno.serve(async (_req: Request): Promise<Response> => {
  try {
    if (!LK_KEY) return json({ ok: false, error: "falta WEB_SERVICE_KEY" }, 501);

    const nowIso = new Date().toISOString();

    // ── 1) LK products ──
    const lkProducts = await fetchAll(LK_URL, LK_KEY, "products", "cod,list_price,uxb,description");

    // ── 2) Chef products (catálogo separado, códigos distintos) ──
    let chefProducts: Product[] = [];
    let chefError = "";
    if (CHEF_KEY) {
      try {
        chefProducts = await fetchAll(CHEF_URL, CHEF_KEY, "products", "cod,list_price,uxb,description");
      } catch (e) {
        // Chef falla → seguir con LK solo; logear el error
        chefError = String((e as Error)?.message || e).slice(0, 200);
      }
    }

    // ── 3) Merge → precios_venta ──
    // LK y Chef tienen rangos de código distintos; si coinciden, Chef gana
    // (es el catálogo más reciente para ese código).
    const preciosMap = new Map<string, { precio_unit: number; uxb: number | null; descripcion: string }>();
    for (const p of lkProducts) {
      const cod = (p.cod || "").trim();
      if (!cod || !p.list_price || p.list_price <= 0) continue;
      preciosMap.set(cod, {
        precio_unit: p.list_price,
        uxb: p.uxb ?? null,
        descripcion: (p.description || "").slice(0, 200),
      });
    }
    for (const p of chefProducts) {
      const cod = (p.cod || "").trim();
      if (!cod || !p.list_price || p.list_price <= 0) continue;
      preciosMap.set(cod, {
        precio_unit: p.list_price,
        uxb: p.uxb ?? null,
        descripcion: (p.description || "").slice(0, 200),
      });
    }
    const preciosRows = Array.from(preciosMap, ([cod, v]) => ({
      cod, precio_unit: v.precio_unit, uxb: v.uxb, descripcion: v.descripcion, actualizado: nowIso,
    }));
    const nPrecios = await upsert("precios_venta", "cod", preciosRows);

    // ── 4) cob_uxb_lk — uxb de LK products ∪ loke_products ──
    const lokeProducts = await fetchAll(LK_URL, LK_KEY, "loke_products", "cod,list_price,uxb,description");
    const uxbMap = new Map<string, number>();
    for (const p of [...lkProducts, ...lokeProducts]) {
      const cod = (p.cod || "").trim();
      if (!cod || !p.uxb) continue;
      uxbMap.set(cod, p.uxb);
    }
    const uxbRows = Array.from(uxbMap, ([cod, uxb]) => ({ cod, uxb }));
    const nUxb = await upsert("cob_uxb_lk", "cod", uxbRows);

    return json({
      ok: true,
      precios_venta: nPrecios,
      precios_lk: lkProducts.filter(p => (p.cod || "").trim() && p.list_price && p.list_price > 0).length,
      precios_chef: chefProducts.filter(p => (p.cod || "").trim() && p.list_price && p.list_price > 0).length,
      chef_error: chefError || undefined,
      cob_uxb_lk: nUxb,
      ts: nowIso,
    });
  } catch (e) {
    return json({ ok: false, error: String((e as Error)?.message || e).slice(0, 300) }, 500);
  }
});
