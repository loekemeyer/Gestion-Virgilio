// gv-sync-padron-direcciones — trae el padron de direcciones de entrega
// Proyecto VIRGILIO (hrxfctzncixxqmpfhskv) · verify_jwt = false
//
// Llena `GV_Clientes_Direcciones` con el padron entero:
//   · LK    -> LK/customers + LK/customer_delivery_addresses          (WEB_SERVICE_KEY)
//   · Chef  -> Chef/customers + Chef/customer_delivery_addresses      (CHEF_SERVICE_KEY)
//
// Chef NO se lee por el espejo de LK: `chef_customers` y `chef_customer_delivery_addresses`
// son tablas FOREIGN (postgres_fdw contra Chef) y el service_role de LK no tiene user mapping
// (42704). Por eso se va directo al proyecto de Chef, igual que sync-clientes-dto.
//
// Es idempotente: upsert por (empresa, cod, slot). No borra.
//
// v14.20 — CORRECCION IMPORTANTE. Dueno: "no entrego en ninguno del interior".
//
// `localidad` y `provincia` son del CLIENTE, no de la direccion de entrega. Un cliente de
// Rosario tiene direccion_entrega = "Las Casas 3553" y localidad = Rosario, pero la entrega
// es en "LAS CASAS 3553, Boedo" — la misma calle y altura, en CABA: el deposito del expreso.
// Medido sobre las 573 filas de "interior" con dato de expreso: 93% misma calle y altura, y
// el 100% con barrio de CABA. Pegar la calle con la localidad del cliente y preguntarle a
// Nominatim por "Las Casas 3553, Rosario, Santa Fe" no encuentra nada, que es exactamente por
// que fallaban todas.
//
// Entonces: NO existe una entrega en el interior. El barrio de entrega sale de `zona_expreso`
// (Boedo, Barracas, Pompeya, Soldati...), con `localidad` de respaldo, y `amba` queda en true.
//
// v20.43 (Luis, 2026-09-21) — ademas del padron de direcciones, trae el CUIT del cliente.
// El padron de ISIS (el Excel de Config. Cuarentena) no tiene a los clientes NUEVOS: se dieron
// de alta en la pagina y todavia no estan. Medido: LK 1.259 de 1.259 clientes con CUIT y Chef
// 760 de 765. Lo lee gv_cuarentena_cuit_lote como respaldo del padron de ISIS.
//
// ⚠ El CUIT va a DOS lugares y no es redundancia: `GV_Clientes_Direcciones` tiene una fila por
// DIRECCION, y un cliente recien dado de alta puede no haber cargado ninguna — medido, llenar
// solo esa tabla recuperaba 2 de los 35 clientes nuevos que faltaban. Por eso ademas va a
// `GV_Cliente_Cuit`, que tiene una fila por CLIENTE.

// v20.45 (Luis, 2026-09-21) - ademas trae la ETIQUETA de la sucursal (`label`), que es la
// llave EXACTA contra el pedido: el pedido web guarda esa misma etiqueta en
// `sheets_payload.sucursal_entrega`, y la direccion que llega a la PPP la lleva entre
// parentesis ("Exp. Snaider - PERGAMINO 3751, Soldati (San Martin 1801- Puerto Rico)").
// Sin ella, un cliente con sucursales en DOS PROVINCIAS no se puede desambiguar y el destino
// del expreso queda en duda: al 21/09 son 119 clientes asi (85 de LK + 34 de Chef).
// La lee `gv_destino_de(empresa, cod, direccion, barrio)`, que es de donde sale el aviso de
// "hay pedido a Misiones" en la Programacion.

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
    if (!r.ok) throw new Error(path.split("?")[0] + " -> HTTP " + r.status + " " + (await r.text()).slice(0, 200));
    const page = await r.json();
    out.push(...page);
    if (page.length < PAGE) break;
    offset += PAGE;
    if (offset > 100000) break;   // guarda anti-loop
  }
  return out;
}

async function upsert(tabla: string, onConflict: string, filas: Record<string, unknown>[]) {
  let escritas = 0;
  for (let i = 0; i < filas.length; i += 500) {
    const lote = filas.slice(i, i + 500);
    const r = await fetch(SB_URL + "/rest/v1/" + tabla + "?on_conflict=" + onConflict, {
      method: "POST",
      headers: {
        apikey: SB_KEY, Authorization: "Bearer " + SB_KEY,
        "Content-Type": "application/json",
        Prefer: "resolution=merge-duplicates,return=minimal",
      },
      body: JSON.stringify(lote),
    });
    if (!r.ok) throw new Error(tabla + " upsert -> HTTP " + r.status + " " + (await r.text()).slice(0, 300));
    escritas += lote.length;
  }
  return escritas;
}

/* Mismo criterio que gv_dir_key(dir, barrio) en Postgres: minusculas, espacios colapsados,
   separados por "|". Tiene que dar EXACTO lo mismo o la direccion se geocodifica dos veces. */
function dirKey(dir: unknown, barrio: unknown) {
  const n = (s: unknown) => String(s ?? "").replace(/\s+/g, " ").trim().toLowerCase();
  return n(dir) + "|" + n(barrio);
}

Deno.serve(async (_req: Request): Promise<Response> => {
  const t0 = Date.now();
  try {
    if (!LK_KEY) return json({ ok: false, error: "falta WEB_SERVICE_KEY" }, 501);

    const filas: Record<string, unknown>[] = [];
    const cuitFilas: Record<string, unknown>[] = [];
    const conteo: Record<string, number> = {};
    const cuits: Record<string, number> = {};
    const avisos: string[] = [];

    // v20.43: se pide tambien el cuit. Si una de las dos paginas no tuviera esa columna,
    // PostgREST contesta 400 y se llevaria puesto el padron entero, asi que se reintenta sin el
    // (mismo patron que direccion_expreso, abajo).
    const CLI_COMPLETO = "customers?select=id,cod_cliente,business_name,cuit";
    const CLI_MINIMO   = "customers?select=id,cod_cliente,business_name";
    const DIR_LABEL    = "customer_delivery_addresses?select=customer_id,slot,label,direccion_entrega,localidad,provincia,cp,zona_expreso,nombre_expreso,direccion_expreso";
    const DIR_COMPLETO = "customer_delivery_addresses?select=customer_id,slot,direccion_entrega,localidad,provincia,cp,zona_expreso,nombre_expreso,direccion_expreso";
    const DIR_MINIMO   = "customer_delivery_addresses?select=customer_id,slot,direccion_entrega,localidad,provincia,cp,zona_expreso";

    for (const emp of [
      { empresa: "lk", base: LK_URL, key: LK_KEY, obligatorio: true },
      { empresa: "chef", base: CHEF_URL, key: CHEF_KEY, obligatorio: false },
    ]) {
      if (!emp.key) { avisos.push(emp.empresa + ": sin clave, se saltea"); conteo[emp.empresa] = 0; continue; }
      let clientes: Record<string, unknown>[], dirs: Record<string, unknown>[];
      try {
        try {
          clientes = await rest(emp.base, emp.key, CLI_COMPLETO);
        } catch (_e) {
          avisos.push(emp.empresa + ": customers sin cuit, se carga el padron sin CUIT");
          clientes = await rest(emp.base, emp.key, CLI_MINIMO);
        }
        try {
          dirs = await rest(emp.base, emp.key, DIR_LABEL);
        } catch (_e1) {
          avisos.push(emp.empresa + ": sin label, la sucursal no se desambigua por etiqueta");
          try {
            dirs = await rest(emp.base, emp.key, DIR_COMPLETO);
          } catch (_e2) {
            avisos.push(emp.empresa + ": sin direccion_expreso, se usa zona_expreso");
            dirs = await rest(emp.base, emp.key, DIR_MINIMO);
          }
        }
      } catch (e) {
        if (emp.obligatorio) throw e;
        avisos.push(emp.empresa + ": " + (e instanceof Error ? e.message : String(e)));
        conteo[emp.empresa] = 0;
        continue;
      }
      const porId = new Map<string, Record<string, unknown>>();
      for (const c of clientes) if (c.id != null) porId.set(String(c.id), c);

      // v20.43: el padron de CUIT va por CLIENTE, tenga o no direccion de entrega cargada.
      let nCuit = 0;
      for (const c of clientes) {
        if (c.cod_cliente == null) continue;
        const cuit = String(c.cuit ?? "").replace(/\D/g, "") || null;
        if (cuit) nCuit++;
        cuitFilas.push({
          empresa: emp.empresa,
          cod: String(c.cod_cliente),
          cuit,
          razon_social: c.business_name ?? null,
          actualizado_at: new Date().toISOString(),
        });
      }
      cuits[emp.empresa] = nCuit;

      let n = 0;
      for (const d of dirs) {
        const dir = String(d.direccion_entrega ?? "").trim();
        if (!dir) continue;
        const c = porId.get(String(d.customer_id));
        if (!c || c.cod_cliente == null) continue;
        const localidad = String(d.localidad ?? "").trim() || null;
        const zona = String(d.zona_expreso ?? "").trim();
        const dirExp = String(d.direccion_expreso ?? "").trim();
        // El barrio DONDE SE ENTREGA: `zona_expreso` manda. Si no esta, se prueba con lo que
        // viene despues de la coma en `direccion_expreso` ("LAS CASAS 3553, Boedo") y recien
        // al final con la localidad del cliente.
        const barrioEntrega = zona || (dirExp.includes(",") ? dirExp.split(",").slice(1).join(",").trim() : "") || localidad;
        filas.push({
          empresa: emp.empresa,
          cod: String(c.cod_cliente),
          slot: Number(d.slot) || 1,
          razon_social: c.business_name ?? null,
          cuit: String(c.cuit ?? "").replace(/\D/g, "") || null,
          etiqueta: String(d.label ?? "").trim() || null,
          direccion: dir,
          localidad,
          provincia: String(d.provincia ?? "").trim() || null,
          cp: d.cp == null ? null : String(d.cp),
          zona_expreso: zona || null,
          barrio_entrega: barrioEntrega,
          nombre_expreso: String(d.nombre_expreso ?? "").trim() || null,
          dir_expreso: dirExp || null,
          // El dir_key se arma con el barrio DE ENTREGA, que es contra lo que se geocodifica.
          dir_key: dirKey(dir, barrioEntrega),
          // Todas son AMBA: no se entrega en el interior. Se deja la columna por compatibilidad
          // y para poder detectar si algun dia aparece una excepcion real.
          amba: true,
          actualizado_at: new Date().toISOString(),
        });
        n++;
      }
      conteo[emp.empresa] = n;
    }

    if (!filas.length) return json({ ok: false, error: "el padron vino vacio; no se escribe nada" }, 502);

    const escritas = await upsert("GV_Clientes_Direcciones", "empresa,cod,slot", filas);
    const escritasCuit = cuitFilas.length ? await upsert("GV_Cliente_Cuit", "empresa,cod", cuitFilas) : 0;

    return json({ ok: true, direcciones: filas.length, escritas, clientes_cuit: escritasCuit,
                  por_empresa: conteo, con_cuit: cuits, avisos, ms: Date.now() - t0 });
  } catch (e) {
    return json({ ok: false, error: e instanceof Error ? e.message : String(e) }, 500);
  }
});
