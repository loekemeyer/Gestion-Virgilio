/* v24.57 (Thomas: «ocupa mucho espacio de la pantalla») — la cabecera de Pedidos Importación en
   el celular: solapas y proveedores en UNA fila que se desliza, alerta como número (⚠N), Excel y
   «Cargar pedido ya hecho» dentro del menú ⋯, totales + nacionalización en una barra. La tabla
   del primer proveedor tiene que empezar dentro de la primera pantalla (844 px). */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
const fail = (m) => { console.error("✗ " + m); process.exitCode = 1; };
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 390, height: 844 } });
  await p.route("**/rest/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "[]" }));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(() => {
    const provs = ["Frontier", "Fujian", "Kangli", "Ownland", "Becky", "Hugo Wong", "Zhixin"];
    const items = provs.map((pv, i) => { const it = { cod: "9" + i + "0E", prov: pv, key: "9" + i + "0E", desc: "Art " + i, proyUni: 100, objetivoUni: 1000, stockUni: i < 3 ? 50 : 900, enCurso: 0, meses: 10,
      aPedirUni: 950, uniMaster: 50, uxc: 10, fobUni: 1, m3Master: 0.05, det: [{ id: i, curso: 0, marca: "LK" }] }; it.aPedirCajas = 19; return it; });
    _stkPopShell("📦 Pedidos Importación", "stkPopBody", true);
    _stkPop = { kind: "pedImp", data: { items, meses: 10, minUsd: 25000, nac: { modo: "consolidada", valorM3: 110, tn: 0 } }, soloPedir: true, mcOverride: {} };
    _pedImpRender();
    const body = document.getElementById("stkPopBody");
    const tabs = body.querySelector(".imp-tabs"), provRow = body.querySelector(".pedimp-provs");
    const tb = [...tabs.querySelectorAll("button")].map((x) => x.getBoundingClientRect().top);
    const pb = [...provRow.querySelectorAll("button")].map((x) => x.getBoundingClientRect().top);
    const vis = [...body.querySelectorAll("button")].filter((x) => !x.closest("details.pedimp-mas") && /^📥 Excel$|Cargar pedido ya hecho/.test(x.textContent.trim())).map((x) => x.textContent.trim()).join(",");
    const menu = [...body.querySelectorAll("details.pedimp-mas button")].map((x) => x.textContent.trim());
    const tabla = body.querySelector("table");
    return { tabsFila: new Set(tb.map(Math.round)).size, provFila: new Set(pb.map(Math.round)).size, vis, menu,
      badges: [...body.querySelectorAll(".pedimp-provs .pedimp-alerta")].map((x) => x.textContent + "|" + x.title),
      modo: !!body.querySelector("select.pedimp-modo"), consumo: (body.querySelector(".pedimp-consumo") || {}).textContent || "", tablaTop: tabla ? tabla.getBoundingClientRect().top : 9999,
      largoPag: document.documentElement.scrollWidth };
  });
  if (r.tabsFila !== 1) fail("las solapas tienen que ir en UNA fila: " + r.tabsFila);
  if (r.provFila !== 1) fail("los proveedores tienen que ir en UNA fila: " + r.provFila);
  if (r.vis) fail("Excel y «Cargar pedido ya hecho» van adentro del menú ⋯ (hay " + r.vis + " a la vista)");
  if (!r.menu.some((x) => /Excel/.test(x)) || !r.menu.some((x) => /Cargar pedido ya hecho/.test(x))) fail("el menú ⋯ tiene que tener Excel y Cargar pedido ya hecho: " + JSON.stringify(r.menu));
  if (!r.badges.length || !r.badges.every((x) => /^⚠\d+\|\d+ con < 4 meses/.test(x))) fail("alerta compacta ⚠N con el detalle en el title: " + JSON.stringify(r.badges));
  // v24.59 — Frontier: proy 100 u/mes × FOB 1 = u$s 100/mes
  if (!/consumo u\$s 100\/mes/.test(r.consumo)) fail("el encabezado del proveedor muestra el consumo por mes: " + r.consumo);
  if (!r.modo) fail("el modo de nacionalización es un desplegable");
  if (r.tablaTop > 844) fail("la tabla tiene que empezar en la primera pantalla: top " + r.tablaTop);
  if (r.largoPag > 390) fail("la página se desborda de costado: " + r.largoPag);
  if (process.env.SHOT) await p.screenshot({ path: process.env.SHOT });
  await b.close();
  if (!process.exitCode) console.log("✓ pedimp-cabecera-compacta: tabla en y=" + Math.round(r.tablaTop) + " a 390 px");
})();
