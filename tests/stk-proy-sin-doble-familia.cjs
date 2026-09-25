/* Regresion v22.71 (Luis, 25/09/2026) — "580E figura en 0" y el 580 salía 108.
   Desde la v22.68 la familia la suma el BACKEND (gv_proyeccion_articulo): el principal trae lo
   suyo + sus secundarios y el secundario su venta propia. El front la volvía a sumar con la
   semilla EQUIV_FAMILIAS y borraba al secundario (580 = 58,50 + 49 = 108; 580E = "—").
   A) candado: openStockAdmin no consolida familias sobre el mapa de proyección.
   B) ocgFetchProyeccion lee gv_proyeccion_articulo, deja afuera al secundario y NO suma de nuevo.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const src = String(openStockAdmin);
    const sinConsolidar = !/EQUIV_FAMILIAS\.forEach/.test(src);
    const orig = window.fetch;
    let url = "";
    window.fetch = async (u) => { url = String(u); return { ok: true, json: async () => [
      { cod: "580", proy_cajas_mes: 58.5, es_secundario: false },
      { cod: "580E", proy_cajas_mes: 49, es_secundario: true },
      { cod: "437E", proy_cajas_mes: 36.67, es_secundario: false },
      { cod: "29", proy_cajas_mes: 13.67, es_secundario: true } ] }; };
    const m = await ocgFetchProyeccion();
    window.fetch = orig;
    return { sinConsolidar, leeVistaUnica: /gv_proyeccion_articulo/.test(url),
      p580: m["580"] === 58.5, sinSec: !("580E" in m) && !("29" in m), p437: m["437E"] === 36.67 };
  });
  const pass = Object.values(r).every(Boolean) && errs.length === 0;
  console.log("stk-proy-sin-doble-familia:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
