/* v26.79 (Luis, 05/10/2026) — tocar el rótulo «Est. Madre» de Stocks:
   1.º toque: saca los que tienen 0 y ordena de MAYOR a menor (▼)
   2.º toque: de MENOR a mayor (▲), siguen afuera los 0
   3.º toque: vuelve al estándar (todos, con el orden de siempre)
   v26.81 (Luis, 05/10/2026) — las DEMÁS columnas tienen cuatro toques:
   1.º sólo filtra > 0 (✓, orden de siempre) · 2.º mayor→menor (▼) · 3.º menor→mayor (▲) · 4.º estándar.
   Y pasar de una columna a otra arranca de cero en la nueva (no arrastra el orden).
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
    const fila = (cod, gond, exc) => ({ cod, descripcion: "Art " + cod, linea: "LK", terminado: gond, excedente: exc || 0,
      separar_pedidos: 0, a_facturar: 0, a_guardar: 0, racks: 0, racks_ch: 0, para_envasar: 0,
      insumos_dep: 0, stock_total: gond + (exc || 0), cajas_pedidas: 0 });
    const rows = [fila("501", 5), fila("502", 7), fila("503", 9), fila("504", 4), fila("505", 2), fila("506", 0, 3)];
    stkRender = function () {};   // la pantalla no está abierta: se mide el HTML que arma stkBodyStocks
    _stk = { movs: [], viewRows: rows, cutoff: 0, dem: {}, cap: [], fcs: {}, gConf: [], filtro: "",
             openArt: null, soloNeg: false, proy: { "501": 10, "502": 0, "503": 50, "504": 3, "505": 0, "506": 0 } };
    const orden = (h) => (h.match(/data-stk-cod="([^"]+)"/g) || []).map((s) => s.slice(14, -1));
    const rotulo = (h, k) => { const m = h.match(new RegExp("onclick=\"stkToggleFilCol\\('" + k + "'\\)\"[^>]*>([\\s\\S]*?)</th>")); return m ? m[1] : ""; };
    const toque = (k) => { stkToggleFilCol(k); const h = stkBodyStocks(); return { o: orden(h), rot: rotulo(h, k) }; };
    const out = {};
    let h = stkBodyStocks(); out.std = orden(h);
    // Est. Madre: 3 toques
    out.p1 = toque("_proy"); out.p2 = toque("_proy"); out.p3 = toque("_proy");
    // Góndola: 4 toques
    out.g1 = toque("terminado"); out.g2 = toque("terminado"); out.g3 = toque("terminado"); out.g4 = toque("terminado");
    // de Est. Madre (▼) a Góndola: Góndola arranca en su 1.º toque (sólo filtra), sin el orden de Est. Madre
    toque("_proy"); out.x = toque("terminado"); out.xOrd = _stk.colOrd || "";
    return out;
  });
  const eq = (a, x) => JSON.stringify(a) === JSON.stringify(x);
  const sinMarca = (s) => s.indexOf("▼") < 0 && s.indexOf("▲") < 0 && s.indexOf("✓") < 0;
  const chk = {
    estandarTieneLos6: r.std.length === 6,
    madre1MayorAMenorSinCeros: eq(r.p1.o, ["503", "501", "504"]) && r.p1.rot.indexOf("▼") >= 0,
    madre2MenorAMayorSinCeros: eq(r.p2.o, ["504", "501", "503"]) && r.p2.rot.indexOf("▲") >= 0,
    madre3VuelveAlEstandar: eq(r.p3.o, r.std) && sinMarca(r.p3.rot),
    gond1SoloFiltra: eq(r.g1.o, ["501", "502", "503", "504", "505"]) && r.g1.rot.indexOf("✓") >= 0,
    gond2MayorAMenor: eq(r.g2.o, ["503", "502", "501", "504", "505"]) && r.g2.rot.indexOf("▼") >= 0,
    gond3MenorAMayor: eq(r.g3.o, ["505", "504", "501", "502", "503"]) && r.g3.rot.indexOf("▲") >= 0,
    gond4VuelveAlEstandar: eq(r.g4.o, r.std) && sinMarca(r.g4.rot),
    otraColumnaArrancaDeCero: r.xOrd === "" && eq(r.x.o, ["501", "502", "503", "504", "505"]) && r.x.rot.indexOf("✓") >= 0
  };
  const pass = Object.values(chk).every(Boolean) && errs.length === 0;
  console.log("stk-est-madre-orden:", JSON.stringify(chk), pass ? "" : JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
