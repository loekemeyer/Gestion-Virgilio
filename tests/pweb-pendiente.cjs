/* Regresión (v12.89): "A Programar" sólo muestra pedidos PENDIENTES PARA GESTIÓN.

   Regla del dueño (2026-09-04): pendiente = pedido de la página con fecha >= gestion_desde
   que Producción/ISIS no conozca. Vive en UNA RPC de Virgilio (gv_pedidos_web_excluidos)
   que también usa el job de las 00:01; esta pantalla le pasa (empresa, order_id, cod,
   fecha_recep) de cada pedido y saca los que devuelve. Reemplaza al filtro "no enviado
   a compras" (v12.88), que dejaba afuera el limbo (enviado a ISIS pero que Producción
   todavía no tiene), y eso es de Gestión.

   Verifica que:
   (a) la pantalla llame a la RPC con UN registro por pedido (no por bloque) y con
       empresa, order_id, cod y fecha_recep,
   (b) los pedidos que la RPC devuelve (por cualquier motivo) no aparezcan,
   (c) los demás sí, con el agrupado por pedido intacto (bloques, np_total, m³),
   (d) si la RPC falla, la pantalla falle en vez de mostrar todo (falla cerrado). */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    const rpcCalls = [];
    let rpcFalla = false;
    const json = (o, ok) => ({ ok: ok !== false, status: ok === false ? 500 : 200, json: async () => o, text: async () => JSON.stringify(o),
                               headers: { get: () => "0-3/4" } });
    window.pwebLkToken = async () => "tok";
    window.facAuthWriteHeaders = async () => ({ apikey: "x", Authorization: "Bearer x", "Content-Type": "application/json" });
    window.fetch = async (url, opts) => {
      const u = String(url);
      if (u.indexOf("rpc/gv_pedidos_web_excluidos") >= 0) {
        rpcCalls.push(JSON.parse(opts.body));
        if (rpcFalla) return json({ message: "boom" }, false);
        return json([
          { empresa: "lk", order_id: 1300, motivo: "anterior_al_cambio" },
          { empresa: "lk", order_id: 1300, motivo: "en_produccion" },
          { empresa: "lk", order_id: 1310, motivo: "en_produccion" }
        ]);
      }
      if (u.indexOf("v_pedidos_web_np") >= 0) return json([
        { empresa: "lk", order_id: 1348, np_idx: 1, cod: "4109", razon_social: "Di Leo", fecha_recep: "2026-09-04", direccion: "Bragado 5742 - Mataderos", lineas: 18, cajas: 20, items: [], m3: 0.5,  m3_parcial: false, localidad: "", zona_expreso: "Zona 1" },
        { empresa: "lk", order_id: 1348, np_idx: 2, cod: "4109", razon_social: "Di Leo", fecha_recep: "2026-09-04", direccion: "Bragado 5742 - Mataderos", lineas: 4,  cajas: 5,  items: [], m3: 0.1,  m3_parcial: false, localidad: "", zona_expreso: "Zona 1" },
        { empresa: "lk", order_id: 1300, np_idx: 1, cod: "4188", razon_social: "Orfali", fecha_recep: "2026-08-20", direccion: "Juncal 2869 - Martinez",  lineas: 3,  cajas: 3,  items: [], m3: 0.2,  m3_parcial: false, localidad: "", zona_expreso: "Zona 6" },
        { empresa: "lk", order_id: 1310, np_idx: 1, cod: "2533", razon_social: "Osa",    fecha_recep: "2026-09-03", direccion: "Rivadavia 100 - Caballito", lineas: 2, cajas: 2,  items: [], m3: 0.05, m3_parcial: false, localidad: "", zona_expreso: "Zona 2" },
        { empresa: "lk", order_id: 1350, np_idx: 1, cod: "1651", razon_social: "Inc SA", fecha_recep: "2026-09-04", direccion: "Corrientes 500 - Centro", lineas: 2, cajas: 2,  items: [], m3: 0.05, m3_parcial: false, localidad: "", zona_expreso: "Zona 2" }
      ]);
      return json([]);
    };
    _apr.emp = "lk";
    const peds = await aprTraerPedidos();
    out.rpcLlamadas = rpcCalls.length;
    const body = rpcCalls[0] || {};
    const pp = (body.p_pedidos || []);
    out.unoPorPedido = pp.length === 4 && new Set(pp.map(x => x.order_id)).size === 4;
    const p1348 = pp.find(x => x.order_id === 1348) || {};
    out.campos = p1348.empresa === "lk" && p1348.cod === "4109" && p1348.fecha_recep === "2026-09-04";
    out.ids = peds.map(x => x.order_id).sort().join(",");
    const g = peds.find(x => x.order_id === 1348);
    out.bloques1348 = g ? g.bloques.length : null;
    out.npTotal1348 = g ? g.np_total : null;
    out.m31348      = g ? g.m3 : null;

    // (d) falla cerrado
    rpcFalla = true;
    let fallo = false;
    try { await aprTraerPedidos(); } catch (_e) { fallo = true; }
    out.fallaCerrado = fallo;
    return out;
  });

  const checks = [
    ["la pantalla llama a la RPC una vez",                     r.rpcLlamadas === 1],
    ["con un registro por PEDIDO (4), no por bloque (5)",      r.unoPorPedido === true],
    ["y con empresa, cod y fecha_recep",                       r.campos === true],
    ["los excluidos (1300 y 1310) no aparecen",                r.ids === "1348,1350"],
    ["el pedido partido conserva sus 2 bloques",               r.bloques1348 === 2],
    ["y np_total = 2",                                         r.npTotal1348 === 2],
    ["y el m³ se suma (0.5 + 0.1)",                            r.m31348 === 0.6],
    ["si la RPC falla, la pantalla falla (no muestra todo)",   r.fallaCerrado === true],
    ["sin errores de página",                                  errs.length === 0]
  ];
  let bad = 0;
  for (const [name, ok] of checks) { console.log((ok ? "  ok   " : "  FALLA") + " · " + name); if (!ok) bad++; }
  if (bad) console.log("  detalle:", JSON.stringify(r));
  if (errs.length) console.log("  pageerror: " + errs.join(" | "));
  console.log(bad ? "pweb-pendiente: " + bad + " FALLA(S)" : "pweb-pendiente: OK (" + checks.length + " chequeos)");
  await b.close();
  process.exit(bad ? 1 : 0);
})();
