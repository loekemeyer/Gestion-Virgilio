/* v27.01 (Luis, 05/10) — Órdenes de Compra: (1) botón «⬇ Excel» al abrir una OC (por fecha y por
   tallerista) con, por código: Pedido · Entreg. cajas · Entreg. % · Falta, en el formato optimizado
   (Arial 10, encabezado en 2 renglones, ancho según el dato). (2) Alarma 🚨 en la solapa «Compras
   (OCs)» si hay talleristas con < 50 % entregado en la última OC o artículos con stock ≤ 20 % de la
   Est. Madre. Corre las funciones reales con fetch mockeado. Sale 1 si falla. */
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
  const botones = await p.evaluate(() => {
    const row = (id, prov, cod, cant, rec) => ({ id, fecha: "2026-09-30", rubro: "Art Term", proveedor: prov, codigo: cod, descripcion: "Art " + cod, cantidad: cant, cantidad_recibida: rec, estado: "pendiente" });
    _oc = { view: "fecha", openFecha: "2026-09-30", filtro: "", recepByRow: {}, rows: [row(1, "Martin C", "706", 200, 50), row(2, "Martin C", "707", 100, 100), row(3, "Garcia", "505", 400, 0), row(4, "Garcia", "506", 10, 12)] };
    ocRender = function () {};
    pppLoadXlsx = () => Promise.resolve(window.XLSX);
    const k = Object.keys(ocGroups()).find((x) => x.indexOf("Garcia") === 0);
    _oc.openKey = k; _oc.detEdit = {};
    return { fecha: ocBodyFecha().indexOf('ocDescargarExcelOC(null)') >= 0, det: ocBodyDetail().indexOf('ocDescargarExcelOC(_oc.openKey)') >= 0, key: k };
  });
  const [dl] = await Promise.all([p.waitForEvent("download", { timeout: 10000 }), p.evaluate(() => ocDescargarExcelOC(null))]);
  const buf = fs.readFileSync(await dl.path()); const nombre = dl.suggestedFilename();
  const [dl2] = await Promise.all([p.waitForEvent("download", { timeout: 10000 }), p.evaluate((k) => ocDescargarExcelOC(k), botones.key)]);
  const buf2 = fs.readFileSync(await dl2.path());
  // alarma
  const alarma = await p.evaluate(async () => {
    const orig = supaFetchAll;
    supaFetchAll = async (ep, q) => {
      if (/Ordenes_Compra/.test(ep) && /limit=1/.test(q)) return [{ fecha: "2026-09-30" }];
      if (/Ordenes_Compra/.test(ep)) return [{ proveedor: "Martin C", cantidad: 100, cantidad_recibida: 10 }, { proveedor: "Garcia", cantidad: 100, cantidad_recibida: 90 }];
      if (/vista_generador_oc/.test(ep)) return [{ cod: "207", descripcion: "Ñoquera", proveedor: "Log/ Fabr", proy: 82, stock: 10 }, { cod: "535", proy: 59, stock: 109 }];
      return [];
    };
    _stk = null; await ocAlarmaCargar(true);
    const on = { on: ocAlarmaOn(), tall: _ocAlarma.tall.map((x) => x.prov).join(","), arts: _ocAlarma.arts.map((x) => x.cod).join(","), badge: /🚨 2/.test(ocAlarmaBadge()), banner: /Martin C/.test(ocAlarmaBanner()) && /207/.test(ocAlarmaBanner()) };
    // falla de lectura → sin alarma
    _ocAlarma = null; supaFetchAll = async () => { throw new Error("x"); };
    await ocAlarmaCargar(true);
    on.fallaSinAlarma = !ocAlarmaOn() && ocAlarmaBadge() === "";
    supaFetchAll = orig;
    return on;
  });
  await b.close();
  const a = XLSX.utils.sheet_to_json(XLSX.read(buf, { type: "buffer" }).Sheets["OC"], { header: 1 });
  const a2 = XLSX.utils.sheet_to_json(XLSX.read(buf2, { type: "buffer" }).Sheets["OC"], { header: 1 });
  const cfb = XLSX.CFB.read(buf, { type: "buffer" });
  const txt = (re) => { const i = cfb.FullPaths.findIndex((x) => re.test(x)); return i < 0 ? "" : Buffer.from(cfb.FileIndex[i].content).toString(); };
  const st = txt(/\/xl\/styles\.xml$/), sh = txt(/\/xl\/worksheets\/sheet1\.xml$/);
  const chk = {
    botonFecha: botones.fecha, botonDetalle: botones.det,
    encabezado: a[0].join("|") === "Proveedor|Código|Descripción|Pedido|Entreg. cajas|Entreg. %|Falta",
    todos: a.length === 5,
    garcia505: a[1][0] === "Garcia" && a[1][1] === "505" && a[1][3] === 400 && a[1][4] === 0 && a[1][5] === 0 && a[1][6] === 400,
    pct: a[3][1] === "706" && a[3][4] === 50 && a[3][5] === 25 && a[3][6] === 150,
    deMasSinFaltaNegativa: a[2][1] === "506" && a[2][5] === 120 && a[2][6] === 0,
    soloTallerista: a2.length === 3 && a2[1][0] === "Garcia",
    arial10: /<name val="Arial"\/>/.test(st) && /wrapText="1"/.test(st),
    congelada: /state="frozen"/.test(sh), filtro: /<autoFilter /.test(sh),
    nombre: /^OC 2026-09-30\.xlsx$/.test(nombre),
    alarmaOn: alarma.on && alarma.tall === "Martin C" && alarma.arts === "207",
    badge: alarma.badge, banner: alarma.banner, fallaSinAlarma: alarma.fallaSinAlarma,
    sinErrores: errs.length === 0
  };
  const mal = Object.keys(chk).filter((k) => !chk[k]);
  console.log(mal.length ? "oc-excel-alarma: FALLA " + mal.join(", ") + (errs.length ? " · " + errs.join(" | ") : "") + " " + JSON.stringify({ a, alarma }) : "oc-excel-alarma: OK (" + Object.keys(chk).length + " chequeos)");
  process.exit(mal.length ? 1 : 0);
})();
