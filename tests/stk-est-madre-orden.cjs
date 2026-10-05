/* v26.79 (Luis, 05/10/2026) — tocar el rótulo «Est. Madre» de Stocks:
   1.º toque: saca los que tienen 0 y ordena de MAYOR a menor (▼)
   2.º toque: de MENOR a mayor (▲), siguen afuera los 0
   3.º toque: vuelve al estándar (todos, con el orden de siempre)
   Y tocar otra columna después no arrastra el orden de Est. Madre.
   Corre stkBodyStocks + stkToggleFilCol de verdad. Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(() => {
    const fila = (cod, gond) => ({ cod, descripcion: "Art " + cod, linea: "LK", terminado: gond, excedente: 0,
      separar_pedidos: 0, a_facturar: 0, a_guardar: 0, racks: 0, racks_ch: 0, para_envasar: 0,
      insumos_dep: 0, stock_total: gond, cajas_pedidas: 0 });
    const rows = [fila("501", 5), fila("502", 7), fila("503", 9), fila("504", 4), fila("505", 2)];
    stkRender = function () {};   // la pantalla no está abierta: se mide el HTML que arma stkBodyStocks
    _stk = { movs: [], viewRows: rows, cutoff: 0, dem: {}, cap: [], fcs: {}, gConf: [], filtro: "",
             openArt: null, soloNeg: false, proy: { "501": 10, "502": 0, "503": 50, "504": 3, "505": 0 } };
    const orden = (h) => (h.match(/data-stk-cod="([^"]+)"/g) || []).map((s) => s.slice(14, -1));
    const rotulo = (h) => { const m = h.match(/onclick="stkToggleFilCol\('_proy'\)"[^>]*>([\s\S]*?)<\/th>/); return m ? m[1] : ""; };
    const out = {};
    let h = stkBodyStocks(); out.std = orden(h); out.stdRot = rotulo(h);
    stkToggleFilCol("_proy"); h = stkBodyStocks(); out.t1 = orden(h); out.t1Rot = rotulo(h);
    stkToggleFilCol("_proy"); h = stkBodyStocks(); out.t2 = orden(h); out.t2Rot = rotulo(h);
    stkToggleFilCol("_proy"); h = stkBodyStocks(); out.t3 = orden(h); out.t3Rot = rotulo(h);
    stkToggleFilCol("_proy"); stkToggleFilCol("terminado"); h = stkBodyStocks();
    out.otra = orden(h); out.otraOrd = _stk.proyOrd || ""; out.otraRot = rotulo(h);
    return out;
  });
  const eq = (a, x) => JSON.stringify(a) === JSON.stringify(x);
  const chk = {
    estandarTieneLos5: r.std.length === 5,
    toque1MayorAMenorSinCeros: eq(r.t1, ["503", "501", "504"]) && r.t1Rot.indexOf("▼") >= 0,
    toque2MenorAMayorSinCeros: eq(r.t2, ["504", "501", "503"]) && r.t2Rot.indexOf("▲") >= 0,
    toque3VuelveAlEstandar: eq(r.t3, r.std) && r.t3Rot.indexOf("▼") < 0 && r.t3Rot.indexOf("▲") < 0,
    otraColumnaNoArrastraOrden: r.otraOrd === "" && eq(r.otra, r.std) && r.otraRot.indexOf("▼") < 0
  };
  const pass = Object.values(chk).every(Boolean) && errs.length === 0;
  console.log("stk-est-madre-orden:", JSON.stringify(chk), JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
