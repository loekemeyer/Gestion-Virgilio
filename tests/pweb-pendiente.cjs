/* Regresión (v12.88): "A Programar" sólo muestra pedidos PENDIENTES = no enviados a compras.

   Un pedido que ya salió a ISIS por el mail de las 12:30 (`enviado_a_compras`) lo
   entrega Producción. Si aparece acá, el supervisor lo programa de nuevo y sale dos
   veces. Medido el 2026-09-04: sin el filtro, 355 de 365 NP de 30 días ya estaban
   entregadas. La regla vive en el backend (gv_pedidos_web_np_lk / _chef, que usa el
   job); esta pantalla lee la vista cruda de LK y la duplica.

   Verifica que:
   (a) para LK, la consulta a v_pedidos_web_np pida la columna enviado_a_compras,
   (b) un pedido con enviado_a_compras=true no aparezca en la lista,
   (c) uno con false y uno con null (Chef viejo) sí aparezcan,
   (d) el agrupado por pedido siga igual (bloques, np_total, m³). */
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
    const urls = [];
    const json = (o) => ({ ok: true, status: 200, json: async () => o, text: async () => JSON.stringify(o),
                           headers: { get: () => "0-2/3" } });
    window.pwebLkToken = async () => "tok";
    window.fetch = async (url) => {
      const u = String(url); urls.push(u);
      if (u.indexOf("v_pedidos_web_np") >= 0) return json([
        { empresa: "lk", order_id: 1348, np_idx: 1, cod: "4109", razon_social: "Di Leo",  fecha_recep: "2026-09-03", direccion: "Bragado 5742 - Mataderos", lineas: 18, cajas: 20, items: [], m3: 0.5, m3_parcial: false, localidad: "", zona_expreso: "Zona 1", enviado_a_compras: false },
        { empresa: "lk", order_id: 1348, np_idx: 2, cod: "4109", razon_social: "Di Leo",  fecha_recep: "2026-09-03", direccion: "Bragado 5742 - Mataderos", lineas: 4,  cajas: 5,  items: [], m3: 0.1, m3_parcial: false, localidad: "", zona_expreso: "Zona 1", enviado_a_compras: false },
        { empresa: "lk", order_id: 1300, np_idx: 1, cod: "4188", razon_social: "Orfali",  fecha_recep: "2026-08-20", direccion: "Juncal 2869 - Martinez",  lineas: 3,  cajas: 3,  items: [], m3: 0.2, m3_parcial: false, localidad: "", zona_expreso: "Zona 6", enviado_a_compras: true },
        { empresa: "lk", order_id: 1350, np_idx: 1, cod: "2533", razon_social: "Osa",     fecha_recep: "2026-09-04", direccion: "Rivadavia 100 - Caballito", lineas: 2, cajas: 2,  items: [], m3: 0.05, m3_parcial: false, localidad: "", zona_expreso: "Zona 2", enviado_a_compras: null }
      ]);
      return json([]);
    };
    _apr.emp = "lk";
    const peds = await aprTraerPedidos();
    const lkUrl = urls.find(u => u.indexOf("v_pedidos_web_np") >= 0) || "";
    out.pideColumna = lkUrl.indexOf("enviado_a_compras") >= 0;
    out.ids = peds.map(x => x.order_id).sort().join(",");
    const p1348 = peds.find(x => x.order_id === 1348);
    out.bloques1348 = p1348 ? p1348.bloques.length : null;
    out.npTotal1348 = p1348 ? p1348.np_total : null;
    out.m31348      = p1348 ? p1348.m3 : null;
    return out;
  });

  const checks = [
    ["la consulta a LK pide enviado_a_compras",            r.pideColumna === true],
    ["el enviado a compras (1300) no aparece",             r.ids === "1348,1350"],
    ["el pedido partido conserva sus 2 bloques",           r.bloques1348 === 2],
    ["y np_total = 2",                                     r.npTotal1348 === 2],
    ["y el m³ se suma (0.5 + 0.1)",                        r.m31348 === 0.6],
    ["sin errores de página",                              errs.length === 0]
  ];
  let bad = 0;
  for (const [name, ok] of checks) { console.log((ok ? "  ok   " : "  FALLA") + " · " + name); if (!ok) bad++; }
  if (bad) console.log("  detalle:", JSON.stringify(r));
  if (errs.length) console.log("  pageerror: " + errs.join(" | "));
  console.log(bad ? "pweb-pendiente: " + bad + " FALLA(S)" : "pweb-pendiente: OK (" + checks.length + " chequeos)");
  await b.close();
  process.exit(bad ? 1 : 0);
})();
