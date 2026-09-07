// ══════════════════════════════════════════════════════════════════════════
// gv-sync-padron-direcciones — trae el padrón de direcciones de entrega
// Proyecto VIRGILIO (hrxfctzncixxqmpfhskv) · verify_jwt = false
// ══════════════════════════════════════════════════════════════════════════
// Lo que pidió el dueño (2026-09-07): *"tenés que tener a todo ubicado. sin
// falta de ninguno, inclusive aunque no hayan mandado pedido"*.
//
// El geocodificador (`gv-geocodificar`) sólo sabía de las direcciones que
// estaban PROGRAMADAS. Un cliente que no pidió esta semana no tenía ubicación,
// y el día que entra su pedido el reparto se arma a ciegas.
//
// Esta función llena `GV_Clientes_Direcciones` con el padrón entero:
//   · LK    → LK/customers + LK/customer_delivery_addresses          (WEB_SERVICE_KEY)
//   · Chef  → Chef/customers + Chef/customer_delivery_addresses      (CHEF_SERVICE_KEY)
//
// ⚠ Chef NO se lee por el espejo de LK. `chef_customers` y
//   `chef_customer_delivery_addresses` son tablas FOREIGN (postgres_fdw contra Chef) y el
//   `service_role` de LK no tiene user mapping: devuelven
//   `42704 user mapping not found for user "service_role", server "chef_db"`.
//   Por eso se va directo al proyecto de Chef, igual que hace `sync-clientes-dto`.
//   Si falta CHEF_SERVICE_KEY, Chef se saltea y LK sigue (best-effort, queda en la respuesta).
//
// Es idempotente: upsert por (empresa, cod, slot). No borra: una dirección que
// desaparece del padrón queda acá, y no molesta —lo único que hace es tener una
// ubicación de más.
//
// ⚠ v14.20 — CORRECCIÓN IMPORTANTE. Dueño: *"no entrego en ninguno del interior"*.
//
// `localidad` y `provincia` son del CLIENTE, no de la dirección de entrega. Un cliente de
// Rosario tiene `direccion_entrega = "Las Casas 3553"` y `localidad = Rosario`, pero la entrega
// es en **"LAS CASAS 3553, Boedo"** — la misma calle y altura, en CABA: el depósito del expreso.
// Medido sobre las 573 filas de "interior" con dato de expreso: **93% misma calle y altura, y
// el 100% con barrio de CABA**. Pegar la calle con la localidad del cliente y preguntarle a
// Nominatim por "Las Casas 3553, Rosario, Santa Fe" no encuentra nada, que es exactamente por
// qué fallaban todas.
//
// Entonces: **no existe una entrega en el interior**. El barrio de entrega sale de
// `zona_expreso` (Boedo, Barracas, Pompeya, Soldati…), con `localidad` de respaldo, y `amba`
// queda en true para todas.
//
// Secrets: WEB_SUPABASE_URL, WEB_SERVICE_KEY (los mismos que usa sync-clientes-dto).
// ══════════════════════════════════════════════════════════════════════════

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const LK_URL = Deno.env.get("WEB_SUPABASE_URL") || "https://kwkclwhmoygunqmlegrg.supabase.co";
const LK_KEY = Deno.env.get("WEB_SERVICE_KEY") || "";
const CHEF_URL = Deno.env.get("CHEF_SUPABASE_URL") || "https://nkhzocgdpwtgrmwleihr.supabase.co";
const CHEF_KEY = Deno.env.get("CHEF_SERVICE_KEY") || "";
const SB_URL = Deno.env.get("SUPABASE_URL") || "";
const SB_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const PAGE = 1000;

function json(b: unknown, s = 200): Response {
  return new Response(JSON.stringify(b), { status: s, headers: { "Content-Type": "application/json" } });
}

async function rest(base: string, key: string, path: string): Promise<Record<string, unknown>[]> {
  const out: Record<string, unknown>[] = [];
  let offset = 0;
  while (true) {
    const sep = path.includes("?") ? "&" : "?";
    const r = await fetch(base + "/rest/v1/" + path + sep + "limit=" + PAGE + "&offset=" + offset,
      { headers: { apikey: key, Authorization: "Bearer " + key } });
    if (!r.ok) throw new Error(path.split("?")[0] + " → HTTP " + r.status + " " + (await r.text()).slice(0, 200));
    const page = await r.json();
    out.push(...page);
    if (page.length < PAGE) break;
    offset += PAGE;
    if (offset > 100000) break;   // guarda anti-loop
  }
  return out;
}

/* Mismo criterio que gv_dir_key(dir, barrio) en Postgres: minúsculas, espacios colapsados,
   separados por "|". Tiene que dar EXACTO lo mismo o la dirección se geocodifica dos veces. */
function dirKey(dir: unknown, barrio: unknown) {
  const n = (s: unknown) => String(s ?? "").replace(/\s+/g, " ").trim().toLowerCase();
  return n(dir) + "|" + n(barrio);
}

Deno.serve(async (_req: Request): Promise<Response> => {
  const t0 = Date.now();
  try {
    if (!LK_KEY) return json({ ok: false, error: "falta WEB_SERVICE_KEY" }, 501);

    const filas: Record<string, unknown>[] = [];
    const conteo: Record<string, number> = {};
    const avisos: string[] = [];

    const CLI = "customers?select=id,cod_cliente,business_name";
    // Chef y LK no tienen exactamente las mismas columnas: `direccion_expreso` existe en LK y
    // puede no estar en Chef. PostgREST devuelve 400 ante una columna desconocida y eso se
    // llevaría puesto el padrón entero de Chef, así que se pide lo completo y, si falla, se
    // reintenta con el mínimo. Sin `direccion_expreso` el barrio sale igual de `zona_expreso`.
    const DIR_COMPLETO = "customer_delivery_addresses?select=customer_id,slot,direccion_entrega,localidad,provincia,cp,zona_expreso,nombre_expreso,direccion_expreso";
    const DIR_MINIMO   = "customer_delivery_addresses?select=customer_id,slot,direccion_entrega,localidad,provincia,cp,zona_expreso";

    for (const emp of [
      { empresa: "lk", base: LK_URL, key: LK_KEY, obligatorio: true },
      { empresa: "chef", base: CHEF_URL, key: CHEF_KEY, obligatorio: false },
    ]) {
      if (!emp.key) { avisos.push(emp.empresa + ": sin clave, se saltea"); conteo[emp.empresa] = 0; continue; }
      let clientes: Record<string, unknown>[], dirs: Record<string, unknown>[];
      try {
        clientes = await rest(emp.base, emp.key, CLI);
        try {
          dirs = await rest(emp.base, emp.key, DIR_COMPLETO);
        } catch (_e) {
          avisos.push(emp.empresa + ": sin direccion_expreso, se usa zona_expreso");
          dirs = await rest(emp.base, emp.key, DIR_MINIMO);
        }
      } catch (e) {
        if (emp.obligatorio) throw e;
        avisos.push(emp.empresa + ": " + (e instanceof Error ? e.message : String(e)));
        conteo[emp.empresa] = 0;
        continue;
      }
      const porId = new Map<string, Record<string, unknown>>();
      for (const c of clientes) if (c.id != null) porId.set(String(c.id), c);

      let n = 0;
      for (const d of dirs) {
        const dir = String(d.direccion_entrega ?? "").trim();
        if (!dir) continue;
        const c = porId.get(String(d.customer_id));
        if (!c || c.cod_cliente == null) continue;
        const localidad = String(d.localidad ?? "").trim() || null;
        const zona = String(d.zona_expreso ?? "").trim();
        const dirExp = String(d.direccion_expreso ?? "").trim();
        // El barrio DONDE SE ENTREGA: `zona_expreso` manda. Si no está, se prueba con lo que
        // viene después de la coma en `direccion_expreso` ("LAS CASAS 3553, Boedo") y recién
        // al final con la localidad del cliente.
        const barrioEntrega = zona || (dirExp.includes(",") ? dirExp.split(",").slice(1).join(",").trim() : "") || localidad;
        filas.push({
          empresa: emp.empresa,
          cod: String(c.cod_cliente),
          slot: Number(d.slot) || 1,
          razon_social: c.business_name ?? null,
          direccion: dir,
          localidad,
          provincia: String(d.provincia ?? "").trim() || null,
          cp: d.cp == null ? null : String(d.cp),
          zona_expreso: String(d.zona_expreso ?? "").trim() || null,
          barrio_entrega: barrioEntrega,
          nombre_expreso: String(d.nombre_expreso ?? "").trim() || null,
          dir_expreso: dirExp || null,
          // El dir_key se arma con el barrio DE ENTREGA, que es contra lo que se geocodifica.
          dir_key: dirKey(dir, barrioEntrega),
          // Todas son AMBA: no se entrega en el interior. Se deja la columna por compatibilidad
          // y para poder detectar si algún día aparece una excepción real.
          amba: true,
          actualizado_at: new Date().toISOString(),
        });
        n++;
      }
      conteo[emp.empresa] = n;
    }

    if (!filas.length) return json({ ok: false, error: "el padrón vino vacío; no se escribe nada" }, 502);

    // Upsert de a 500 (PostgREST se atraganta con lotes muy grandes).
    let escritas = 0;
    for (let i = 0; i < filas.length; i += 500) {
      const lote = filas.slice(i, i + 500);
      const r = await fetch(SB_URL + "/rest/v1/GV_Clientes_Direcciones?on_conflict=empresa,cod,slot", {
        method: "POST",
        headers: {
          apikey: SB_KEY, Authorization: "Bearer " + SB_KEY,
          "Content-Type": "application/json",
          Prefer: "resolution=merge-duplicates,return=minimal",
        },
        body: JSON.stringify(lote),
      });
      if (!r.ok) throw new Error("upsert → HTTP " + r.status + " " + (await r.text()).slice(0, 300));
      escritas += lote.length;
    }

    return json({ ok: true, direcciones: filas.length, escritas, por_empresa: conteo, avisos, ms: Date.now() - t0 });
  } catch (e) {
    return json({ ok: false, error: e instanceof Error ? e.message : String(e) }, 500);
  }
});
