// sync-clientes-dto — refresca public.clientes_dto (dto_vol por cliente) desde el maestro
// de LK (customers.dto_vol). Idempotente. Lo dispara pg_cron cada 14 dias (job sync-clientes-dto-14d).
// Secrets (ya existentes en el proyecto, los usa arca-wsfe): WEB_SERVICE_KEY = service_role de
// LK, WEB_SUPABASE_URL = url de LK. SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY los inyecta Supabase.
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

Deno.serve(async (_req: Request): Promise<Response> => {
  try {
    if (!LK_KEY) return json({ ok: false, error: "falta WEB_SERVICE_KEY" }, 501);
    // 1) leer TODO customers de LK, paginado (PostgREST corta en 1000/pagina)
    // deno-lint-ignore no-explicit-any
    const all: any[] = [];
    let offset = 0;
    while (true) {
      const url = LK_URL + "/rest/v1/customers?select=cod_cliente,dto_vol&order=cod_cliente.asc" +
        "&limit=" + PAGE + "&offset=" + offset;
      const r = await fetch(url, { headers: { apikey: LK_KEY, Authorization: "Bearer " + LK_KEY } });
      if (!r.ok) return json({ ok: false, error: "LK REST " + r.status, detail: (await r.text()).slice(0, 300) }, 502);
      // deno-lint-ignore no-explicit-any
      const page: any[] = await r.json();
      all.push(...page);
      if (page.length < PAGE) break;
      offset += PAGE;
      if (offset > 100000) break; // guarda anti-loop
    }
    // dedup por cod_cliente y normalizar
    const seen = new Map<string, number>();
    for (const x of all) {
      if (!x || x.cod_cliente == null) continue;
      seen.set(String(x.cod_cliente), Number(x.dto_vol) || 0);
    }
    if (!seen.size) return json({ ok: false, error: "LK devolvio 0 clientes" }, 502);
    const nowIso = new Date().toISOString();
    const upserts = Array.from(seen, function ([cod_cliente, dto_vol]) {
      return { cod_cliente, dto_vol, actualizado: nowIso };
    });
    // 2) upsert en Virgilio (merge-duplicates por PK cod_cliente)
    const w = await fetch(SB_URL + "/rest/v1/clientes_dto?on_conflict=cod_cliente", {
      method: "POST",
      headers: {
        apikey: SB_KEY, Authorization: "Bearer " + SB_KEY,
        "Content-Type": "application/json",
        Prefer: "resolution=merge-duplicates,return=minimal",
      },
      body: JSON.stringify(upserts),
    });
    if (!w.ok) return json({ ok: false, error: "Virgilio upsert " + w.status, detail: (await w.text()).slice(0, 300) }, 502);
    return json({ ok: true, sincronizados: upserts.length, ts: nowIso });
  } catch (e) {
    return json({ ok: false, error: String((e as Error)?.message || e).slice(0, 300) }, 500);
  }
});
