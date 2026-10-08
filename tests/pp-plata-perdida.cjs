/* v28.64 — lee rpc/gv_plata_perdida y esconde los códigos sin precio.
   v28.63 — «Plata perdida de facturar» se quedaba en «Calculando…»: ppRender usaba yr/d1/d2 sin declarar
   (ReferenceError). Corre openPlataPerdida con la vista mockeada y mira que dibuje el total. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const txt = await p.evaluate(async () => {
    const y = String(new Date().getFullYear());
    const rows = [{ np: "LK 0001", cod: "505", cod_raw: "505", cajas: 2, ped: 5, ent: 3, fecha: y + "-09-10", cod_cliente: "100", precio_unit: 1000, uxb: 12, descripcion: "Cuchillo", precio_ok: true, vendedor: "3", razon_social: "Cliente X" },
      { np: "LK 0002", cod: "999", cod_raw: "999", cajas: 7, ped: 7, ent: 0, fecha: y + "-09-10", cod_cliente: "100", precio_unit: 0, uxb: 1, descripcion: "SinPrecio", precio_ok: false, vendedor: "3", razon_social: "Cliente X" }];
    window.fetch = async (u) => ({ ok: true, status: 200, json: async () => (String(u).indexOf("rpc/gv_plata_perdida") >= 0 ? rows : []), headers: { get: () => null } });
    window.requireSupervisor = () => true;
    await openPlataPerdida();
    await new Promise((r) => setTimeout(r, 300));
    return document.getElementById("ppBody").innerText;
  });
  const pass = !/Calculando/.test(txt) && /24\.000/.test(txt) && !/999|sin precio/i.test(txt) && !errs.length;
  console.log("pp-plata-perdida:", JSON.stringify(txt.slice(0, 200)), errs.join("|"), pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
