/* v29.35 (Thomas, D43): en Recibir insumos aparecen TODOS los componentes de GP2 del rubro (lo válido es GP2).
   (a) el componente de GP2 que falta en Virgilio aparece con su código y nombre de GP2;
   (b) elegirlo lo da de alta (gv_insumo_desde_gp2) y recién ahí abre la cantidad, con el código devuelto;
   (c) la bolsa ya vinculada a GP2 aparece aunque no tenga lugar en el Mapa;
   (d) mismo código y mismo rubro en Virgilio sin vincular: no se duplica (se vincula al elegirlo);
   (e) el movimiento sale con el código que dio la base;
   (f) sin respuesta de GP2, la pantalla es la de siempre. Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 390, height: 844 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    window.alert = function () {};
    const CATS = [["plastico","Plásticos"],["fleje","Flejes"],["partes_plasticas","Partes plásticas"],["partes_crudo","Crudo"]];
    window.insLoadMeta = async function () { INS_CATS = CATS.map(function (c) { return { k: c[0], lbl: c[1], unis: [], desc: "" }; }); };
    window.insFetchCatalogo = async function () { return [
      { cod: "PP 2630", nombre: "PP 2630 (Polipropileno)", categoria: "plastico", ubicacion: "AF01" },
      { cod: "NY NUEVO", nombre: "Nylon nuevo", categoria: "plastico", ubicacion: "" },
      { cod: "G11", nombre: "Mgo Plano 501 p/Dobl", categoria: "partes_crudo", ubicacion: "" },
      { cod: "Mgo Pelador 505", nombre: "Mgo Pelador 505", categoria: "partes_plasticas", ubicacion: "" }
    ]; };
    window.stockFetchSaldos = async function () { return {}; };
    window.insFetchSaldosXUni = async function () { return {}; };
    let gp2 = [
      { categoria: "partes_plasticas", comp_id: 239, codigo: "PC1A", nombre: "Mgo Pelapapa 505 Calado", unidad: "unidad", cod_virgilio: null },
      { categoria: "plastico", comp_id: 742, codigo: "2405", nombre: "PP 2630 (Polipropileno)", unidad: "kg", cod_virgilio: "PP 2630" },
      { categoria: "plastico", comp_id: 750, codigo: "2495", nombre: "Nylon nuevo", unidad: "kg", cod_virgilio: "NY NUEVO" },
      { categoria: "partes_crudo", comp_id: 4, codigo: "G11", nombre: "Mgo Plano 501 p/Dobl", unidad: "unidad", cod_virgilio: null }
    ];
    window.insFetchGp2Ri = async function () { return gp2; };
    const llamadas = [];
    const _f = window.fetch;
    window.fetch = async function (url, opt) {
      if (/gv_insumo_desde_gp2/.test(String(url))) {
        const body = JSON.parse(opt.body); llamadas.push(body.p_comp_id);
        return new Response(JSON.stringify(body.p_comp_id === 239 ? "PC1A" : "G11"), { status: 200, headers: { "Content-Type": "application/json" } });
      }
      return _f.apply(this, arguments);
    };
    const out = {};
    window._insRiCat = "partes_plasticas";
    await showInsumoModal("RI", "104");
    const ip = _ins.items.findIndex(function (x) { return x.gp2Comp === 239; });
    const html = document.getElementById("insBody").innerHTML;
    out.a = ip >= 0 && _ins.items[ip].cod === "" && /PC1A/.test(html) && /Mgo Pelapapa 505 Calado/.test(html);
    insOpenQty(ip);
    const antes = _ins.qty;
    await new Promise(function (res) { setTimeout(res, 50); });
    out.b = antes === null && llamadas[0] === 239 && _ins.items[ip].cod === "PC1A" && _ins.qty === ip;
    out.c = _ins.items.some(function (x) { return x.cod === "NY NUEVO"; });
    const g11 = _ins.items.filter(function (x) { return x.cod === "G11" || x.gp2Cod === "G11"; });
    out.d = g11.length === 1 && g11[0].cod === "G11" && g11[0].gp2Comp === 4;
    _ins.items[ip].qty = 3; _ins.items[ip].unidad = "Uni";
    let mov = null; const _sm = window.stockMove; window.stockMove = function (rows) { mov = rows; };
    insCloseQty(); await insConfirmar(); window.stockMove = _sm;
    out.e = !!mov && mov[0] && mov[0].cod_art === "PC1A" && mov[0].delta === 3;
    gp2 = null; window._insRiCat = "partes_plasticas";
    await showInsumoModal("RI", "104");
    out.f = !_ins.items.some(function (x) { return x.gp2Comp && !x.cod; }) && !_ins.items.some(function (x) { return x.cod === "NY NUEVO"; });
    return out;
  });
  const pass = r.a && r.b && r.c && r.d && r.e && r.f && errs.length === 0;
  console.log("ins-ri-gp2-catalogo:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
