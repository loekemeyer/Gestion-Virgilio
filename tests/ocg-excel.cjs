/* v26.90-26.92 (Luis, 05/10) — Generar las OCs: botón «⬇ Excel» que baja TODOS los artículos
   (también los de a pedir 0), una fila por artículo y proveedor, con la columna Proveedor, y con
   el formato de su foto: encabezados cortos en 2 renglones centrados, Arial 10, columnas al ancho
   del dato, filtro y primera fila congelada. Corre ocgDescargarExcel con el SheetJS real
   (vendor/), baja el archivo y lo abre. Sale 1 si falla. */
const path = require("path");
const fs = require("fs");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }
const root = path.join(__dirname, "..");
const XLSX = require(path.join(root, "vendor", "xlsx.full.min.js"));
(async () => {
  const b = await chromium.launch();
  const ctx = await b.newContext({ acceptDownloads: true });
  const p = await ctx.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(root, "index.html"), { waitUntil: "domcontentloaded" });
  await p.addScriptTag({ path: path.join(root, "vendor", "xlsx.full.min.js") });
  const boton = await p.evaluate(() => {
    const sub = (cod, prov, prop, falta) => ({ cod, desc: "Art " + cod, prov, max: 10, fuente: "proy", indice: 1.5, proy: 20, demanda: 5, stock: 3, falta, cap: 50, maxTot: 100, demandaTot: 50, stockTot: 30, uni: 12, ncaja: null, prop, sinProv: prov === "(sin proveedor)" });
    const items = [sub("505", "Lucho", 50, 384), sub("505", "Garcia", 50, 384), sub("506", "(sin proveedor)", 100, 9), sub("507", "Garcia", 100, 900)];
    const all = items.concat([sub("508", "Lucho", 100, 0)]);
    _oc = { view: "gen", genMode: "art", genFiltro: "", gen: { items, itemsAll: all, fecha: "2026-10-05" } };
    ocRender = function () {};
    pppLoadXlsx = () => Promise.resolve(window.XLSX);
    return ocBodyGen().indexOf('onclick="ocgDescargarExcel()"') >= 0;
  });
  const [dl] = await Promise.all([p.waitForEvent("download", { timeout: 10000 }), p.evaluate(() => ocgDescargarExcel())]);
  const file = await dl.path();
  const nombre = dl.suggestedFilename();
  const buf = fs.readFileSync(file);
  await b.close();
  const wb = XLSX.read(buf, { type: "buffer" });
  const a = XLSX.utils.sheet_to_json(wb.Sheets[wb.SheetNames[0]], { header: 1 });
  const cfb = XLSX.CFB.read(buf, { type: "buffer" });
  const txt = (re) => { const i = cfb.FullPaths.findIndex((x) => re.test(x)); return i < 0 ? "" : Buffer.from(cfb.FileIndex[i].content).toString(); };
  const st = txt(/\/xl\/styles\.xml$/), sh = txt(/\/xl\/worksheets\/sheet1\.xml$/);
  const anchoDesc = (sh.match(/<col min="3" max="3" width="([\d.]+)"/) || [])[1];
  const chk = {
    boton,
    headerProveedor: a[0] && a[0][0] === "Proveedor" && a[0][3] === "A pedir" && a[0][5] === "E.M. (cj/m)",
    unaFilaPorProveedor: a.length === 6,
    incluyeCero: a.length === 6 && a[4][1] === "508" && a[4][3] === 0,
    orden: a.length === 6 && a[1][0] === "Garcia" && a[1][1] === "507" && a[2][0] === "Garcia" && a[3][0] === "Lucho" && a[5][0] === "(sin proveedor)",
    cajas: a.length === 6 && a[1][3] === 900 && a[3][3] === 384,
    arial10: /<name val="Arial"\/>/.test(st) && /<sz val="10"\/>/.test(st),
    encabezadoAjustado: /wrapText="1"/.test(st) && /<c r="A1" s="1"/.test(sh) && /<c r="J1" s="1"/.test(sh),
    datosSinEstilo: !/<c r="A2" s="1"/.test(sh),
    congelada: /state="frozen"/.test(sh),
    filtro: /<autoFilter /.test(sh),
    anchoSegunDato: anchoDesc != null && Number(anchoDesc) < 15,
    nombre: /^OCs a generar \d{4}-\d\d-\d\d/.test(nombre || ""),
    sinErrores: errs.length === 0
  };
  const mal = Object.keys(chk).filter((k) => !chk[k]);
  console.log(mal.length ? "ocg-excel: FALLA " + mal.join(", ") + (errs.length ? " · " + errs.join(" | ") : "") : "ocg-excel: OK (" + Object.keys(chk).length + " chequeos)");
  process.exit(mal.length ? 1 : 0);
})();
