/* Regresión v7.08 / idea 7917 — Insumos (RI/EI): navegación por categorías.
   MISMA FORMA que la Recepción de Mercadería (recepcion.js): pantalla 1 = grilla de
   CATEGORÍAS en botones cuadrados → pantalla 2 = grilla de los INSUMOS de esa categoría
   → pop-up de cantidad. "‹ Atrás" vuelve. Este test fija el contrato:
     · pantalla 1 muestra una tarjeta por categoría con su conteo, sin listar insumos
     · 'a depurar' tiene su tarjeta (con aviso al entrar) pero no cuenta como "en uso"
     · entrar a una categoría muestra SOLO sus insumos, y los flejes por MEDIDA
     · tocar un insumo abre el pop-up; cargar cantidad marca la tarjeta y la categoría
     · Atrás vuelve a las categorías conservando lo cargado (se manda todo junto)
     · buscar desde la pantalla 1 mira TODO (incluso lo a depurar)
     · la unidad por defecto sale de la categoría salvo que ya haya saldo en una sola
     · el alta nace con categoría y abre el pop-up
   Sin red (fetch mockeado). */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}
(async () => {
  const root = path.join(__dirname, "..");
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 390, height: 844 } });
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(root, "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    const posted = [];
    function J(data) {
      return Promise.resolve({ ok: true, status: 200, headers: { get: function () { return null; } }, json: function () { return Promise.resolve(data); } });
    }
    const CAT = [
      { cod: "22", nombre: "121 X 1,20", sector: null, categoria: "fleje", ubicacion: "V2 Ad" },
      { cod: "5", nombre: "38 X 0,55", sector: null, categoria: "fleje", ubicacion: "R4At" },
      { cod: "2745", nombre: "168 X 0,80", sector: null, categoria: "fleje", ubicacion: "V10 At" },
      { cod: "PP", nombre: "POLIPROPILENO (2630)", sector: null, categoria: "plastico", ubicacion: "AF1" },
      { cod: "2955", nombre: "Cuchilla 505 Ac Inox", sector: null, categoria: "inox", ubicacion: "X20" },
      { cod: "505C·CUCHILLA CHINA", nombre: "CUCHILLA CHINA", sector: "505c", categoria: "depurar", ubicacion: null }
    ];
    window.fetch = function (url, opt) {
      url = String(url);
      if (opt && String(opt.method || "").toUpperCase() === "POST" && url.indexOf("/Insumos") >= 0) {
        try { posted.push(JSON.parse(opt.body)); } catch (_e) {}
        return J({});
      }
      if (url.indexOf("/Insumos") >= 0) return J(CAT);
      if (url.indexOf("vista_saldos_insumos_x_unidad") >= 0) {
        return J([
          { cod_art: "PP", unidad: "Bolsas", saldo: 151 },
          { cod_art: "22", unidad: "kg", saldo: 1483.95 },
          { cod_art: "505C·CUCHILLA CHINA", unidad: "Uni", saldo: -16000 }
        ]);
      }
      if (url.indexOf("vista_saldos_stock") >= 0) {
        return J([
          { cod_art: "PP", descripcion: "POLIPROPILENO (2630)", insumos: 151 },
          { cod_art: "22", descripcion: "121 X 1,20", insumos: 1483.95 },
          { cod_art: "505C·CUCHILLA CHINA", descripcion: "CUCHILLA CHINA", insumos: -16000 }
        ]);
      }
      return J([]);
    };

    await showInsumoModal("EI", "104");
    const nCats = function () { return document.querySelectorAll("#insBody .ins-catbtn").length; };
    const nItems = function () { return document.querySelectorAll("#insBody .ins-itbtn:not(.add)").length; };
    const cods = function () { return Array.prototype.map.call(document.querySelectorAll("#insBody .ins-itbtn:not(.add) .ins-itcod"), function (e) { return e.textContent.trim().replace(/^📍\s*/, ""); }); };
    const catTxt = function () { return Array.prototype.map.call(document.querySelectorAll("#insBody .ins-catbtn"), function (e) { return e.textContent.replace(/\s+/g, " ").trim(); }); };

    // 1) PANTALLA 1: una tarjeta por categoría, ningún insumo listado
    out.cats = catTxt();
    out.nCats = nCats();                                                    // 4 (fleje, plástico, inox, depurar)
    out.sinItemsEnP1 = nItems() === 0;
    out.hayDep = out.cats.some(function (t) { return /A depurar/.test(t); });
    out.enUso = /5 insumos en uso/.test(document.getElementById("insBody").textContent);   // no cuenta el depurar
    out.finDisabled = document.querySelector("#insBody .ins-fin").disabled === true;

    // 2) Unidad por defecto POR CATEGORÍA; si ya hay saldo en UNA unidad, gana esa (7382)
    const byCod = {}; _ins.items.forEach(function (it) { byCod[it.cod] = it; });
    out.uni2745 = byCod["2745"].unidad;      // "Kg"  (fleje, sin saldo)
    out.uniPP = byCod["PP"].unidad;          // "Bolsas" (saldo en 1 sola unidad)
    out.uni2955 = byCod["2955"].unidad;      // "Uni" (inox)

    // 3) Entrar a "fleje": SOLO flejes, ordenados por MEDIDA (38 → 121 → 168) + Atrás
    insSetCat("fleje");
    out.nFleje = nItems();                                                  // 3
    out.ordenFleje = cods().join(",");                                      // "5,22,2745"
    out.hayAtras = !!document.querySelector("#insBody .ins-back");
    out.tituloFleje = (document.querySelector("#insBody .ins-bar-t") || {}).textContent;
    out.ubicEnBoton = /V2 Ad/.test(document.getElementById("insBody").innerHTML);
    out.hayBotonAgregar = !!document.querySelector("#insBody .ins-itbtn.add");

    // 4) Tocar un insumo abre el POP-UP de cantidad; cargar marca el botón
    insOpenQty(_ins.items.indexOf(byCod["22"]));
    out.popupAbierto = !!document.querySelector("#insBody .ins-qov");
    out.popupCod = (document.querySelector("#insBody .ins-qcod") || {}).textContent;   // "22"
    out.popupStock = /1483\.95/.test((document.querySelector("#insBody .ins-qov") || {}).textContent || "");
    insChg(_ins.items.indexOf(byCod["22"]), 3);
    out.qtyTrasChg = byCod["22"].qty;                                       // 3
    insCloseQty();
    out.popupCerrado = !document.querySelector("#insBody .ins-qov");
    out.botonMarcado = !!document.querySelector("#insBody .ins-itbtn.on");
    out.finHabilitado = document.querySelector("#insBody .ins-fin").disabled === false;
    out.finCuenta = /\(1\)/.test(document.querySelector("#insBody .ins-fin").textContent);

    // 5) Atrás → vuelve a las categorías, la de fleje queda marcada y NO se pierde lo cargado
    insBack();
    out.volvioAP1 = nCats() > 0 && nItems() === 0;
    out.flejeMarcada = !!document.querySelector("#insBody .ins-catbtn.hasq");
    out.catCargados = /1 cargado/.test(document.getElementById("insBody").textContent);
    out.qtySobrevive = byCod["22"].qty;                                     // 3

    // 6) Buscar desde la pantalla 1 mira TODO (incluso lo 'a depurar')
    _ins.filtro = "cuchilla"; insRender();
    out.rowsBusca = nItems();                                               // 2 (2955 + el depurar)
    out.buscaTraeDep = document.getElementById("insBody").innerHTML.indexOf("CUCHILLA CHINA") >= 0;
    insBack();

    // 7) Entrar a 'a depurar' muestra el aviso
    insSetCat("depurar");
    out.avisoDep = !!document.querySelector("#insBody .ins-depw");
    out.nDep = nItems();                                                    // 1
    out.sinAgregarEnDep = !document.querySelector("#insBody .ins-itbtn.add");
    insBack();

    // 8) El alta nace con la categoría de la pantalla donde estás y abre el pop-up
    insSetCat("plastico");
    _ins.creando = true; insRender();
    document.getElementById("insNewId").value = "1234567";
    document.getElementById("insNewNom").value = "Nylon nuevo";
    await insCrear();
    const nue = _ins.items.filter(function (it) { return it.cod === "1234567"; })[0];
    out.altaCat = nue ? nue.cat : null;                                     // "plastico"
    out.altaUni = nue ? nue.unidad : null;                                  // "Bolsas"
    out.altaPosteoCat = (posted[0] || {}).categoria;                        // "plastico"
    out.altaAbrePopup = !!document.querySelector("#insBody .ins-qov");
    insCloseQty();

    // 9) El movimiento lleva la UBICACIÓN física y la unidad del ítem
    let mov = null;
    const _sm = window.stockMove; window.stockMove = function (rows) { mov = rows; };
    window.alert = function () {};
    insConfirmar();
    window.stockMove = _sm;
    out.movN = mov ? mov.length : 0;                                        // 1 (sólo el 22)
    out.movUbic = mov && mov[0] ? mov[0].ubicacion : null;                  // "V2 Ad"
    // "kg" en minúscula: el 22 ya tiene saldo en esa unidad y la idea 7382 manda sobre
    // el default de la categoría — no le cambiamos la unidad a un saldo que ya existe.
    out.movUni = mov && mov[0] ? mov[0].unidad : null;                      // "kg"
    out.movDelta = mov && mov[0] ? mov[0].delta : null;                     // -3 (EI)

    // 10) nada se sale del ancho del celular (390px)
    out.overflow = document.documentElement.scrollWidth - document.documentElement.clientWidth;
    return out;
  });

  const pass =
    r.nCats === 4 && r.sinItemsEnP1 === true && r.hayDep === true && r.enUso === true && r.finDisabled === true &&
    r.uni2745 === "Kg" && r.uniPP === "Bolsas" && r.uni2955 === "Uni" &&
    r.nFleje === 3 && r.ordenFleje === "5,22,2745" && r.hayAtras === true &&
    /Fleje/.test(r.tituloFleje || "") && r.ubicEnBoton === true && r.hayBotonAgregar === true &&
    r.popupAbierto === true && r.popupCod === "22" && r.popupStock === true && r.qtyTrasChg === 3 &&
    r.popupCerrado === true && r.botonMarcado === true && r.finHabilitado === true && r.finCuenta === true &&
    r.volvioAP1 === true && r.flejeMarcada === true && r.catCargados === true && r.qtySobrevive === 3 &&
    r.rowsBusca === 2 && r.buscaTraeDep === true &&
    r.avisoDep === true && r.nDep === 1 && r.sinAgregarEnDep === true &&
    r.altaCat === "plastico" && r.altaUni === "Bolsas" && r.altaPosteoCat === "plastico" && r.altaAbrePopup === true &&
    r.movN === 1 && r.movUbic === "V2 Ad" && r.movUni === "kg" && r.movDelta === -3 &&
    r.overflow === 0 &&
    errs.length === 0;
  console.log("ins-categorias:", JSON.stringify(r));
  console.log("  pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit(pass ? 0 : 1);
})();
