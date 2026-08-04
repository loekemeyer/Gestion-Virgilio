/* Regresión v7.11 / idea 7917 — Insumos (RI/EI): navegación por categorías.
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
      { cod: "2955", nombre: "Cuchilla 505 Ac Inox", sector: null, categoria: "importados", ubicacion: "X20" },
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
    const nCats = function () { return document.querySelectorAll("#insBody .ins-catbtn:not(.add)").length; };
    const nItems = function () { return document.querySelectorAll("#insBody .ins-itbtn:not(.add)").length; };
    const cods = function () { return Array.prototype.map.call(document.querySelectorAll("#insBody .ins-itbtn:not(.add) .ins-itcod"), function (e) { return e.textContent.trim().replace(/^📍\s*/, ""); }); };
    const catTxt = function () { return Array.prototype.map.call(document.querySelectorAll("#insBody .ins-catbtn:not(.add)"), function (e) { return e.textContent.replace(/\s+/g, " ").trim(); }); };

    // 1) PANTALLA 1: una tarjeta por categoría, ningún insumo listado
    out.cats = catTxt();
    out.nCats = nCats();                                                    // 4 (plásticos, flejes, importados, depurar)
    out.sinItemsEnP1 = nItems() === 0;
    out.hayDep = out.cats.some(function (t) { return /A depurar/.test(t); });
    out.enUso = /5 insumos en uso/.test(document.getElementById("insBody").textContent);   // no cuenta el depurar
    out.finDisabled = document.querySelector("#insBody .ins-fin").disabled === true;

    // 2) Unidad por defecto POR CATEGORÍA; si ya hay saldo en UNA unidad, gana esa (7382)
    const byCod = {}; _ins.items.forEach(function (it) { byCod[it.cod] = it; });
    out.uni2745 = byCod["2745"].unidad;      // "Kg"  (fleje, sin saldo)
    out.uniPP = byCod["PP"].unidad;          // "Bolsas" (saldo en 1 sola unidad)
    // "Importados" NO fija unidad: queda vacía a propósito, la elige el operario
    out.uni2955 = byCod["2955"].unidad;      // "" (importados, sin default)

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

    // 8) ALTA DE INSUMO NUEVO — el "+" está junto a las categorías (pantalla 1) y lleva
    //    a una pantalla con categoría / cantidad / unidad / detalle. Sin código: el
    //    operario no tiene por qué saberlo.
    out.hayMasEnP1 = !!document.querySelector("#insBody .ins-catbtn.add");
    document.querySelector("#insBody .ins-catbtn.add").click();
    out.altaAbre = !!document.getElementById("insNvDet") && !!document.getElementById("insNvQty");
    out.altaTitulo = (document.querySelector("#insBody .ins-bar-t") || {}).textContent;
    // el Detalle va ANTES que todo lo demás
    const lbls = Array.prototype.map.call(document.querySelectorAll("#insBody .ins-nvl"), function (e) { return e.textContent.split("—")[0].trim(); });
    out.ordenCampos = lbls.join(" | ");   // "Detalle | Elegí la categoría | Cantidad | Unidad"
    // "Sin categoría clara" es una opción más
    out.haySinCatClara = /Sin categoría clara/.test(document.getElementById("insBody").textContent);
    // unidades que ya usamos en otros lados (Bolsas/MC/Cajas, no sólo Uni/Paquetes/Kg)
    const uniTxt = Array.prototype.map.call(document.querySelectorAll("#insBody .ins-uchip"), function (e) { return e.textContent.trim(); });
    out.uniOfrecidas = ["Uni", "Kg", "Bolsas", "Paquetes", "MC", "Cajas"].every(function (u) { return uniTxt.indexOf(u) >= 0; });
    // elegir categoría propone su unidad sola
    insNuevoPick("cat", "plastico");
    out.altaUniAuto = _ins.nuevo.uni;                                       // "Bolsas"
    document.getElementById("insNvQty").value = "7";
    document.getElementById("insNvDet").value = "Bolsa gris sin etiqueta";
    insNuevoOk();
    const nue = _ins.items.filter(function (it) { return /BOLSA GRIS/.test(it.cod); })[0];
    out.altaCod = nue ? nue.cod : null;                                     // "NUEVO·BOLSA GRIS SIN ETIQUETA"
    out.altaCat = nue ? nue.cat : null;                                     // "plastico"
    out.altaUni = nue ? nue.unidad : null;                                  // "Bolsas"
    out.altaQty = nue ? nue.qty : null;                                     // 7 (ya cargado)
    out.altaNombre = nue ? nue.nombre : null;                               // el detalle textual
    out.altaPosteoCat = (posted[0] || {}).categoria;                        // "plastico"
    out.altaCierraPantalla = _ins.nuevo === null;
    out.altaVaASuCat = _ins.cat === "plastico";

    // 8b) Sin detalle y sin código no deja crear; "Sin categoría clara" cae en el ❓
    let alerts = 0; const _al = window.alert; window.alert = function () { alerts++; };
    insNuevoOpen("");
    insNuevoOk();
    out.altaExigeDetalle = alerts === 1 && _ins.nuevo !== null;
    document.getElementById("insNvDet").value = "Cosa rara sin nombre";
    insNuevoOk();
    const nue2 = _ins.items.filter(function (it) { return /COSA RARA/.test(it.cod); })[0];
    out.altaSinCat = nue2 ? nue2.cat : "(no se creó)";                      // "" → chip ❓
    out.altaSinQtyAbrePopup = !!document.querySelector("#insBody .ins-qov");  // sin cantidad, pide
    insCloseQty();
    // ya no hay campo de código: el operario no tiene por qué saberlo
    out.altaSinCampoCod = !document.getElementById("insNvCod");
    // categoría sin unidad fija: con cantidad y sin unidad no deja agregar
    insNuevoOpen("importados");
    document.getElementById("insNvDet").value = "Cosa importada rara";
    document.getElementById("insNvQty").value = "5";
    out.impSinDefault = _ins.nuevo.uni === "";
    insNuevoOk();
    out.altaExigeUnidad = _ins.nuevo !== null && alerts === 2;
    insNuevoPick("uni", "MC");
    insNuevoOk();
    out.altaConUnidadOk = _ins.nuevo === null;
    window.alert = _al;
    insBack();

    // 8d) Sin unidad NO se manda: iría como "Uni" y partiría el saldo (lo que pasó con PP)
    let alerts2 = 0; const _al2 = window.alert; window.alert = function () { alerts2++; };
    let movBloq = null; const _sm0 = window.stockMove; window.stockMove = function (r) { movBloq = r; };
    byCod["2955"].qty = 4;                       // importados: unidad vacía
    insConfirmar();
    out.confirmBloqueaSinUni = movBloq === null && alerts2 === 1;
    out.confirmAbreElQueFalta = _ins.qty === _ins.items.indexOf(byCod["2955"]);
    insSetUnidad(_ins.items.indexOf(byCod["2955"]), "MC");
    insCloseQty();
    byCod["2955"].qty = 0;                       // lo saco: no es parte del envío que mido abajo
    window.stockMove = _sm0; window.alert = _al2;

    // 9) El movimiento lleva la UBICACIÓN física y la unidad del ítem
    let mov = null;
    const _sm = window.stockMove; window.stockMove = function (rows) { mov = rows; };
    window.alert = function () {};
    insConfirmar();
    window.stockMove = _sm;
    out.movN = mov ? mov.length : 0;                                        // 3 (22 · bolsa gris · cosa importada)
    out.movNuevo = (mov || []).filter(function (m) { return /BOLSA GRIS/.test(m.cod_art); })[0] || null;
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
    r.uni2745 === "Kg" && r.uniPP === "Bolsas" && r.uni2955 === "" &&
    r.nFleje === 3 && r.ordenFleje === "5,22,2745" && r.hayAtras === true &&
    /Fleje/.test(r.tituloFleje || "") && r.ubicEnBoton === true && r.hayBotonAgregar === true &&
    r.popupAbierto === true && r.popupCod === "22" && r.popupStock === true && r.qtyTrasChg === 3 &&
    r.popupCerrado === true && r.botonMarcado === true && r.finHabilitado === true && r.finCuenta === true &&
    r.volvioAP1 === true && r.flejeMarcada === true && r.catCargados === true && r.qtySobrevive === 3 &&
    r.rowsBusca === 2 && r.buscaTraeDep === true &&
    r.avisoDep === true && r.nDep === 1 && r.sinAgregarEnDep === true &&
    r.hayMasEnP1 === true && r.altaAbre === true && /Insumo nuevo/.test(r.altaTitulo || "") &&
    r.haySinCatClara === true && r.uniOfrecidas === true && r.altaUniAuto === "Bolsas" &&
    r.altaCod === "NUEVO·BOLSA GRIS SIN ETIQUETA" && r.altaCat === "plastico" && r.altaUni === "Bolsas" &&
    r.altaQty === 7 && r.altaNombre === "Bolsa gris sin etiqueta" && r.altaPosteoCat === "plastico" &&
    r.altaCierraPantalla === true && r.altaVaASuCat === true &&
    r.altaExigeDetalle === true && r.altaSinCat === "" && r.altaSinQtyAbrePopup === true &&
    r.altaSinCampoCod === true && r.impSinDefault === true && r.altaExigeUnidad === true && r.altaConUnidadOk === true &&
    /^Detalle \| Elegí la categoría \| Cantidad \| Unidad$/.test(r.ordenCampos || "") &&
    r.movN === 3 && r.confirmBloqueaSinUni === true && r.confirmAbreElQueFalta === true && r.movUbic === "V2 Ad" && r.movUni === "kg" && r.movDelta === -3 &&
    r.movNuevo && r.movNuevo.delta === -7 && r.movNuevo.unidad === "Bolsas" &&
    r.overflow === 0 &&
    errs.length === 0;
  console.log("ins-categorias:", JSON.stringify(r));
  console.log("  pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit(pass ? 0 : 1);
})();
