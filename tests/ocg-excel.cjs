/* v26.90 (Luis, 05/10) — Generar las OCs: botón «⬇ Excel» que baja lo que se va a generar,
   una fila por artículo y proveedor, con la columna Proveedor. Corre ocgDescargarExcel con
   XLSX mockeado y mira las filas. Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const sub = (cod, prov, prop, falta) => ({ cod, desc: "Art " + cod, prov, max: 10, fuente: "proy", indice: 1.5, proy: 20, demanda: 5, stock: 3, falta, cap: 50, maxTot: 100, demandaTot: 50, stockTot: 30, uni: 12, ncaja: null, prop, sinProv: prov === "(sin proveedor)" });
    const items = [sub("505", "Lucho", 50, 384), sub("505", "Garcia", 50, 384), sub("506", "(sin proveedor)", 100, 9), sub("507", "Garcia", 100, 900)];
    const all = items.concat([sub("508", "Lucho", 100, 0)]);
    _oc = { view: "gen", genMode: "art", genFiltro: "", gen: { items, itemsAll: all, fecha: "2026-10-05" } };
    ocRender = function () {};
    const out = { boton: ocBodyGen().indexOf('onclick="ocgDescargarExcel()"') >= 0 };
    let aoa = null, nombre = null;
    window.pppLoadXlsx = () => Promise.resolve({ utils: { aoa_to_sheet: (a) => { aoa = a; return {}; }, encode_range: () => "A1", book_new: () => ({}), book_append_sheet: () => {} }, writeFile: (_w, n) => { nombre = n; } });
    ocgDescargarExcel();
    await new Promise((res) => setTimeout(res, 50));
    out.aoa = aoa; out.nombre = nombre;
    return out;
  });
  await b.close();
  const a = r.aoa || [];
  const chk = {
    boton: r.boton,
    headerProveedor: a[0] && a[0][0] === "Proveedor",
    unaFilaPorProveedor: a.length === 6,
    incluyeCero: a.length === 6 && a[4][1] === "508" && a[4][3] === 0,
    orden: a.length === 6 && a[1][0] === "Garcia" && a[1][1] === "507" && a[2][0] === "Garcia" && a[3][0] === "Lucho" && a[5][0] === "(sin proveedor)",
    cajas: a.length === 6 && a[1][3] === 900 && a[3][3] === 384,
    nombre: /^OCs a generar \d{4}-\d\d-\d\d/.test(r.nombre || ""),
    sinErrores: errs.length === 0
  };
  const mal = Object.keys(chk).filter((k) => !chk[k]);
  console.log(mal.length ? "ocg-excel: FALLA " + mal.join(", ") + (errs.length ? " · " + errs.join(" | ") : "") : "ocg-excel: OK");
  process.exit(mal.length ? 1 : 0);
})();
