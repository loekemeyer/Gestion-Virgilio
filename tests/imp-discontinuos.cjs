/* v24.49 — solapa 🚫 Discontinuos de Importación (Thomas): lista los Importados con activo = false
   (lee activo=eq.false; Pedidos sigue leyendo activo=eq.true). Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
const fail = (m) => { console.error("✗ " + m); process.exitCode = 1; };
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1280, height: 900 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  let pedido = "";
  await p.route("**/rest/v1/**", (r) => {
    const u = r.request().url();
    if (/gv_importados_ordenes/.test(u)) { pedido = u; return r.fulfill({ status: 200, contentType: "application/json",
      body: JSON.stringify([{ cod_art: "938E", marca: "LK", proveedor: "Fujian", descripcion: "Espumadera Nylon", stock_total: 0, pedido_curso: 0 },
                            { cod_art: "733E", marca: "CH", proveedor: "Kangli", descripcion: "Sacacorcho", stock_total: 24, pedido_curso: 0 }]) }); }
    if (/Articulos_Discontinuados/.test(u)) return r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify([{ cod: "733E", motivo: "discontinuo (Thomas)" }]) });
    return r.fulfill({ status: 200, contentType: "application/json", body: "[]" });
  });
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    await openImpDisc();
    const trs = [...document.querySelectorAll("#stkPopBody tbody tr")];
    const tab = [...document.querySelectorAll("#stkPopBody button")].find((x) => /Discontinuos/.test(x.textContent));
    return { cods: trs.map((t) => t.cells[0].textContent.trim()), m733: (trs.find((t) => /733E/.test(t.cells[0].textContent)) || { cells: [] }).cells[6]?.textContent || "", emp: trs.map((t) => t.cells[2].textContent.trim()).join(","), tab: !!tab };
  });
  if (!/activo=eq\.false/.test(decodeURIComponent(pedido))) fail("lee activo=eq.false: " + pedido);
  if (r.cods.join(",") !== "733E,938E") fail("lista ordenada por código: " + r.cods);
  if (!/discontinuo \(Thomas\)/.test(r.m733)) fail("motivo de Articulos_Discontinuados: " + r.m733);
  if (r.emp !== "CH,LK") fail("empresa: " + r.emp);
  if (!r.tab) fail("falta la solapa en _impTabsHtml");
  if (errs.length) fail("errores JS: " + errs.join(" | "));
  await b.close();
  if (!process.exitCode) console.log("✓ imp-discontinuos: la solapa lista los importados dados de baja");
})();
