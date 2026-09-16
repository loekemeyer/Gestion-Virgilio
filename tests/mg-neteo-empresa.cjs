/* Regresión v18.86 — "Mover a Góndola" mostraba cajas que NO existen.

   El 16/09 la pantalla ofrecía 475 cajas en 10 códigos (026 70 · 027 53 · 031 133 · 103 73 ·
   312 7 · 562 54 · 564 17 · 735 41 · 859 21 · 862 6) que en la base sumaban CERO. El saldo
   estaba PARTIDO POR EMPRESA: entraron a A Guardar como LK/CH y salieron como 'Mixto', así
   que el − no cancelaba al +, y la lista de MG leía la fila positiva del desglose en vez del
   total.

   Dos causas, las dos acá:
     a) `vista_saldos_stock.clave` trae el código CRUDO ("026", o "438E LK" para los duales) y
        `gv_saldos_stock_emp.cod` lo trae PELADO ("26", "438E"): el desglose nunca se enganchaba
        y encima se INVENTABA un artículo nuevo con la clave pelada. Sin empresa en el renglón,
        el guardado salía con `empresa: null` → el server lo marcaba 'Mixto'.
     b) la lista listaba el desglose sin mirar el total.

   Chequea:
     1) `_emp` se cuelga del artículo que existe ("026"), no de uno inventado ("26");
     2) un dual ("438E LK" / "438E CH") recibe cada empresa en SU clave;
     3) total 0 con desglose +70/−70 → NO hay renglón (el bug de las 475 cajas);
     4) un desglose que no cierra contra el total → UN renglón, con el total y SIN empresa
        (la resuelve el trigger `zz_normalizar_empresa` v18.86 en el server);
     5) un desglose que SÍ cierra (LK 30 + CH 20 = 50) → dos renglones con su empresa;
     6) la lectura de `gv_saldos_stock_emp` lleva `order=` (pagina con Range: sin orden
        estable se repiten filas de una página y se saltean otras).
   Sale 1 si falla. */
const path = require("path");
const fs = require("fs");
const src = fs.readFileSync(path.join(__dirname, "..", "index.html"), "latin1");

const fallas = [];
// ---- 6) estático ----
{
  const i = src.indexOf("/rest/v1/gv_saldos_stock_emp");
  const arg = i < 0 ? "" : src.slice(i, src.indexOf(";", i));
  if (i < 0) fallas.push("no se encuentra la lectura de gv_saldos_stock_emp");
  else if (!/order=/.test(arg)) {
    fallas.push("la lectura de gv_saldos_stock_emp no lleva `order=`: supaFetchAll pagina con " +
      "Range y sin orden estable repite y saltea filas");
  }
}
if (fallas.length) {
  console.log("mg-neteo-empresa: ✗ FAIL\n  - " + fallas.join("\n  - "));
  process.exit(1);
}

let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.log("mg-neteo-empresa: estático ✓ OK (sin Playwright para la parte en vivo)"); process.exit(0); }
}

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/*.supabase.co/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    window.alert = function () {};

    /* Los dos feeds, con la asimetría de claves REAL de producción.
       - 026: entró LK 70, salió Mixto −70 → total 0. Es el caso de las 475 cajas.
       - 438E: dual, clave con sufijo de empresa en una vista y pelada en la otra.
       - 700: desglose que NO cierra contra el total (LK 10 pero el total dice 25).
       - 800: desglose sano, LK 30 + CH 20 = 50. */
    const saldosView = [
      { clave: "026",     cod_art: "026",  descripcion: "Abrelata", a_guardar: 0,  terminado: 188 },
      { clave: "438E LK", cod_art: "438E", descripcion: "Dual LK",  a_guardar: 12, terminado: 5 },
      { clave: "438E CH", cod_art: "438E", descripcion: "Dual CH",  a_guardar: 8,  terminado: 3 },
      { clave: "700",     cod_art: "700",  descripcion: "Descuadre", a_guardar: 25, terminado: 0 },
      { clave: "800",     cod_art: "800",  descripcion: "Sano",     a_guardar: 50, terminado: 0 }
    ];
    const empView = [
      { cod: "26",   empresa: "LK",    a_guardar: 70,  terminado: 125 },
      { cod: "26",   empresa: "Mixto", a_guardar: -70, terminado: 63 },
      { cod: "438E", empresa: "LK",    a_guardar: 12,  terminado: 5 },
      { cod: "438E", empresa: "CH",    a_guardar: 8,   terminado: 3 },
      { cod: "700",  empresa: "LK",    a_guardar: 10,  terminado: 0 },
      { cod: "800",  empresa: "LK",    a_guardar: 30,  terminado: 0 },
      { cod: "800",  empresa: "CH",    a_guardar: 20,  terminado: 0 }
    ];
    window.supaFetchAll = async function (endpoint) {
      if (/gv_saldos_stock_emp/.test(endpoint)) return empView.map((x) => Object.assign({}, x));
      if (/vista_saldos_stock/.test(endpoint)) return saldosView.map((x) => Object.assign({}, x));
      return [];
    };
    window.supaFetchAllSafe = window.supaFetchAll;

    // ---- 1 y 2) el enganche del desglose ----
    const m = await stockFetchSaldos();
    out.noInventa26   = !m["26"];
    out.enganchaEn026 = !!(m["026"] && m["026"]._emp && m["026"]._emp.LK &&
                           m["026"]._emp.LK.a_guardar === 70 && m["026"]._emp.Mixto &&
                           m["026"]._emp.Mixto.a_guardar === -70);
    out.dualLK = !!(m["438E LK"] && m["438E LK"]._emp && m["438E LK"]._emp.LK &&
                    m["438E LK"]._emp.LK.a_guardar === 12 && !m["438E LK"]._emp.CH);
    out.dualCH = !!(m["438E CH"] && m["438E CH"]._emp && m["438E CH"]._emp.CH &&
                    m["438E CH"]._emp.CH.a_guardar === 8 && !m["438E CH"]._emp.LK);

    // ---- 3, 4 y 5) la lista que ve el operario ----
    window.loadArtNombres    = async function () { return {}; };
    window.ocgFetchCapacidad = async function () { return {}; };
    window.ocgFetchCeldas    = async function () { return {}; };
    window.ocgDemanda        = async function () { return {}; };
    window.rkbFetchCxM       = async function () { return { cxm: {} }; };
    window.gvFetchLugares    = async function () { return null; };
    await showMGModal("999");
    await new Promise(function (res) { setTimeout(res, 60); });
    /* `_mg` es un `let` de módulo, no cuelga de window. `mgAskClose()` se lo pasa a
       `opAskClose` como 5º argumento: es la única costura pública que lo expone. */
    let snap = null;
    window.opAskClose = function (_p, _op, _leg, _lbl, s) { snap = s; };
    mgAskClose();
    const items = (snap && snap.items) || [];
    const de = function (c) { return items.filter(function (x) { return x.cod === c; }); };

    out.cero026SinRenglon = de("026").length === 0;                     // ← las 475 cajas
    /* Y el renglón INVENTADO: con la clave pelada, el `if (!m[k])` creaba un artículo "26"
       con desglose (a_guardar 70) y sin total — el que el operario veía en pantalla. */
    out.noRenglonInventado = !items.some(function (x) { return String(x.cod) === "26"; });
    const d700 = de("700");
    out.descuadreUnaFila  = d700.length === 1 && d700[0].disponible === 25 && d700[0].emp === "";
    const d800 = de("800").slice().sort(function (a, b) { return a.emp < b.emp ? -1 : 1; });
    out.sanoSePartio      = d800.length === 2 && d800[0].emp === "CH" && d800[0].disponible === 20 &&
                            d800[1].emp === "LK" && d800[1].disponible === 30;
    out.dualesListados    = de("438E LK").length === 1 && de("438E CH").length === 1;
    return out;
  });

  const malas = Object.keys(r).filter((k) => !r[k]);
  const pass = malas.length === 0 && errs.length === 0;
  console.log("mg-neteo-empresa:", JSON.stringify(r),
    malas.length ? "· fallan: " + malas.join(", ") : "",
    "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit(pass ? 0 : 1);
})();
