// sync-precios-venta — refresca precios_venta (LK), precios_venta_chef (Chef) y
// cob_uxb_lk desde:
//   1. LK products + loke_products (WEB_SERVICE_KEY) → precios_venta + cob_uxb_lk
//   2. Chef products (CHEF_KEY — publishable key, lectura pública) → precios_venta_chef
// v14.44: listas SEPARADAS por empresa (antes merge con "Chef gana", ensuciaba LK).
// v14.47: RECONCILIA — borra de cada mirror lo que ya no está en su catálogo de origen,
//         así precios_venta = catálogo LK exacto y precios_venta_chef = catálogo Chef exacto
//         (antes el upsert sin delete dejaba filas viejas que ensuciaban gv_articulo_empresa).
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

// v14.47: borra las filas que YA NO están en el catálogo de origen (las que no se
// refrescaron en esta corrida → actualizado < cutoff). Deja el mirror = catálogo exacto.
// Sólo se llama si se escribió al menos una fila (guarda contra un pull vacío que
// borraría todo). El cutoff es el nowIso de esta corrida.
async function reconcileStale(table: string, cutoffIso: string): Promise<void> {
  const w = await fetch(`${SB_URL}/rest/v1/${table}?actualizado=lt.${encodeURIComponent(cutoffIso)}`, {
    method: "DELETE",
    headers: { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}`, Prefer: "return=minimal" },
  });
  if (!w.ok) throw new Error(`reconcile ${table} ${w.status}: ${(await w.text()).slice(0, 200)}`);
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

    // ── 3) precios_venta = SÓLO LK · precios_venta_chef = SÓLO Chef ──
    // v14.44 (2026-09-08): LK y Chef son DOS listas separadas. Antes se mergeaban
    // en precios_venta con "si coinciden, Chef gana" → una NP de LK con un código
    // compartido (809E, 437E, 438E) tomaba el precio de Chef (809E 3005 en vez de
    // 4060). Ahora cada lista es de su empresa y la valuación se enruta por empresa
    // (gv_vista_facturacion_neto_items, gv_ppp_np_valor, cobranzas_precios).
    const mapProductos = (prods: Product[]) => {
      const m = new Map<string, { precio_unit: number; uxb: number | null; descripcion: string }>();
      for (const p of prods) {
        const cod = (p.cod || "").trim();
        if (!cod || !p.list_price || p.list_price <= 0) continue;
        m.set(cod, {
          precio_unit: p.list_price,
          uxb: p.uxb ?? null,
          descripcion: (p.description || "").slice(0, 200),
        });
      }
      return Array.from(m, ([cod, v]) => ({
        cod, precio_unit: v.precio_unit, uxb: v.uxb, descripcion: v.descripcion, actualizado: nowIso,
      }));
    };
    const preciosRows = mapProductos(lkProducts);
    const nPrecios = await upsert("precios_venta", "cod", preciosRows);
    // Reconciliar: sacar de precios_venta lo que ya no está en el catálogo de LK
    // (guarda: sólo si el pull trajo filas, para no vaciar la tabla si LK falla).
    if (preciosRows.length) await reconcileStale("precios_venta", nowIso);

    // Chef → precios_venta_chef (antes se cargaba a mano, ver sql/cobranzas_chef_sync.sql).
    const preciosChefRows = mapProductos(chefProducts);
    const nPreciosChef = preciosChefRows.length ? await upsert("precios_venta_chef", "cod", preciosChefRows) : 0;
    if (preciosChefRows.length) await reconcileStale("precios_venta_chef", nowIso);

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
      precios_venta_chef: nPreciosChef,
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
