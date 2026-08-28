// sync-precios-venta — refresca precios_venta y cob_uxb_lk desde el maestro de LK
// (products + loke_products). Idempotente. Lo dispara pg_cron (job sync-precios-venta).
// Secrets (ya existentes, los usa arca-wsfe y sync-clientes-dto):
//   WEB_SERVICE_KEY    = service_role de LK
//   WEB_SUPABASE_URL   = url de LK
//   SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY los inyecta Supabase.
// verify_jwt = OFF (endpoint interno idempotente; solo pulls de LK -> upsert). Deploy manual/MCP.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const LK_URL = Deno.env.get("WEB_SUPABASE_URL") || "https://kwkclwhmoygunqmlegrg.supabase.co";
const LK_KEY = Deno.env.get("WEB_SERVICE_KEY") || "";
const SB_URL = Deno.env.get("SUPABASE_URL") || "";
const SB_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const PAGE = 1000;

function json(b: unknown, s = 200): Response {
  return new Response(JSON.stringify(b), { status: s, headers: { "Content-Type": "application/json" } });
}

interface Product { cod: string; list_price: number | null; uxb: number | null; description: string | null }

async function fetchAllLK(table: string, select: string): Promise<Product[]> {
  const all: Product[] = [];
  let offset = 0;
  while (true) {
    const url = `${LK_URL}/rest/v1/${table}?select=${select}&order=cod.asc&limit=${PAGE}&offset=${offset}`;
    const r = await fetch(url, { headers: { apikey: LK_KEY, Authorization: `Bearer ${LK_KEY}` } });
    if (!r.ok) throw new Error(`LK REST ${table} ${r.status}: ${(await r.text()).slice(0, 300)}`);
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

    // 1) precios_venta — products con list_price > 0 y cod no vacío
    const products = await fetchAllLK("products", "cod,list_price,uxb,description");
    const preciosMap = new Map<string, { precio_unit: number; uxb: number | null; descripcion: string }>();
    for (const p of products) {
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

    // 2) cob_uxb_lk — uxb de products ∪ loke_products (todo el padrón LK)
    const lokeProducts = await fetchAllLK("loke_products", "cod,list_price,uxb,description");
    const uxbMap = new Map<string, number>();
    for (const p of [...products, ...lokeProducts]) {
      const cod = (p.cod || "").trim();
      if (!cod || !p.uxb) continue;
      uxbMap.set(cod, p.uxb);
    }
    const uxbRows = Array.from(uxbMap, ([cod, uxb]) => ({ cod, uxb }));
    const nUxb = await upsert("cob_uxb_lk", "cod", uxbRows);

    return json({ ok: true, precios_venta: nPrecios, cob_uxb_lk: nUxb, ts: nowIso });
  } catch (e) {
    return json({ ok: false, error: String((e as Error)?.message || e).slice(0, 300) }, 500);
  }
});
