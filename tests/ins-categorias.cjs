/* Regresión v7.29 / ideas 7917 + 5572 — Insumos (RI/EI): navegación por categorías.
   MISMA FORMA que la Recepción de Mercadería (recepcion.js): pantalla 1 = grilla de
   CATEGORÍAS en botones cuadrados → pantalla 2 = grilla de los INSUMOS de esa categoría
   → pop-up de cantidad. "‹ Atrás" vuelve. Este test fija el contrato:
     · pantalla 1 muestra una tarjeta por categoría con su conteo, sin listar insumos
     · lo que NO tiene categoría cae en la tarjeta ❓ (con aviso al entrar) y no cuenta
       como "en uso": «a depurar» dejó de existir como categoría
     · entrar a una categoría muestra SOLO sus insumos, y los flejes por MEDIDA
     · tocar un insumo abre el pop-up; cargar cantidad marca la tarjeta y la categoría
     · Atrás vuelve a las categorías conservando lo cargado (se manda todo junto)
     · buscar desde la pantalla 1 mira TODO (incluso lo a depurar)
     · la unidad por defecto sale de la categoría salvo que ya haya saldo en una sola
     · v29.55 (Luis, 13/10): el operario NO da de alta un insumo — ni en RI ni en EI.
       No hay "+ Agregar insumo" en ningún lado e insNuevoOpen se planta siempre.
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
      { cod: "505C·CUCHILLA CHINA", nombre: "CUCHILLA CHINA", sector: "505c", categoria: null, ubicacion: null }
    ];
    window.fetch = function (url, opt) {
      url = String(url);
      if (url.indexOf("/rpc/nuevo_insumo_tmp") >= 0) {
        try { posted.push(JSON.parse(opt.body)); } catch (_e) {}
        return J("TMP-000" + posted.length);
      }
      if (opt && String(opt.method || "").toUpperCase() === "POST" && url.indexOf("/Insumos") >= 0) {
        try { posted.push(JSON.parse(opt.body)); } catch (_e) {}
        return J({});
      }
      if (url.indexOf("Insumos_Categorias") >= 0) {
        return J([
          { clave: "plastico", nombre: "Plásticos", emoji: "🧪", unidades: ["Bolsas"], orden: 1 },
          { clave: "fleje", nombre: "Flejes y alambres", emoji: "🧵", unidades: ["Kg"], orden: 2 },
          { clave: "importados", nombre: "Importados", emoji: "🌎", unidades: [], orden: 3 },
          { clave: "partes_plasticas", nombre: "Partes plásticas", emoji: "🧩", unidades: [], orden: 4 },
          { clave: "cajas", nombre: "Cajas", emoji: "📦", unidades: ["Paquetes", "Uni"], orden: 5 }
        ]);
      }
      if (url.indexOf("Insumos_Unidades") >= 0) {
        return J(["Uni", "Kg", "Bolsas", "Paquetes", "MC", "Cajas"].map(function (n, i) { return { nombre: n, orden: i }; }));
      }
      // v22.80: el catálogo del operario sale de vista_insumos (ubicación resuelta contra el Mapa)
      if (url.indexOf("vista_insumos") >= 0) return J(CAT);
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
    out.nCats = nCats();                                                    // 3 (flejes, importados, ❓): v29.28 «Envío a otros» no ofrece bolsas
    out.sinItemsEnP1 = nItems() === 0;
    out.hayDep = out.cats.some(function (t) { return /Sin categoría/.test(t); });
    out.noHayDepurar = !/A depurar/.test(document.getElementById("insBody").innerHTML);
    out.enUso = /4 insumos en uso/.test(document.getElementById("insBody").textContent) &&
      /1 sin clasificar/.test(document.getElementById("insBody").textContent);
    out.finDisabled = document.querySelector("#insBody .ins-fin").disabled === true;

    // 2) Unidad por defecto POR CATEGORÍA; si ya hay saldo en UNA unidad, gana esa (7382)
    const byCod = {}; _ins.items.forEach(function (it) { byCod[it.cod] = it; });
    out.uni2745 = byCod["2745"].unidad;      // "Kg"  (fleje, sin saldo)
    out.ppFueraEnEI = !byCod["PP"];          // v29.28 (D9): las bolsas sólo salen por «Envío a inyectores»
    // "Importados" NO fija unidad: queda vacía a propósito, la elige el operario
    out.uni2955 = byCod["2955"].unidad;      // "" (importados, sin default)

    // 3) Entrar a "fleje": SOLO flejes, ordenados por MEDIDA (38 → 121 → 168) + Atrás
    insSetCat("fleje");
    out.nFleje = nItems();                                                  // 3
    out.ordenFleje = cods().join(",");                                      // "5,22,2745"
    out.hayAtras = !!document.querySelector("#insBody .ins-back");
    out.tituloFleje = (document.querySelector("#insBody .ins-bar-t") || {}).textContent;
    out.ubicEnBoton = /V2 Ad/.test(document.getElementById("insBody").innerHTML);
    out.sinAgregarEnEI = !document.querySelector("#insBody .ins-itbtn.add");

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
    out.buscaTraeDep = document.getElementById("insBody").innerHTML.indexOf("CUCHILLA CHINA") >= 0;   // buscar mira todo, incluso lo sin clasificar
    insBack();

    // 7) Entrar a ❓ Sin categoría muestra el aviso
    insSetCat("?");
    out.avisoDep = !!document.querySelector("#insBody .ins-depw");
    out.nDep = nItems();                                                    // 1
    insBack();

    // 8) En ENTREGA no hay "+" en ningún lado, y la función se planta aunque la
    //    llamen a mano.
    insBack();
    out.sinMasEnEI = !document.querySelector("#insBody .ins-catbtn.add");
    let alertEI = ""; const _alEI = window.alert; window.alert = function (m) { alertEI = String(m); };
    insNuevoOpen("");
    out.eiRechazaAlta = _ins.nuevo === null && /no se puede agregar un insumo/i.test(alertEI);
    window.alert = _alEI;

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
    out.movN = mov ? mov.length : 0;                                        // 1 (sólo el 22)
    out.movUbic = mov && mov[0] ? mov[0].ubicacion : null;                  // "V2 Ad"
    // "kg" en minúscula: el 22 ya tiene saldo en esa unidad y la idea 7382 manda sobre
    // el default de la categoría — no le cambiamos la unidad a un saldo que ya existe.
    out.movUni = mov && mov[0] ? mov[0].unidad : null;                      // "kg"
    out.movDelta = mov && mov[0] ? mov[0].delta : null;                     // -3 (EI)

    // 10) v29.55 (Luis, 13/10): el operario YA NO DA DE ALTA un insumo al RECIBIR.
    //     No hay "+ Agregar insumo" en la grilla de categorías ni dentro de una categoría,
    //     y si algún camino viejo llama a insNuevoOpen, se planta con el aviso.
    await showInsumoModal("RI", "104");
    const ppRI = _ins.items.filter(function (it) { return it.cod === "PP"; })[0];
    out.uniPP = ppRI ? ppRI.unidad : null;   // "Bolsas" (saldo en 1 sola unidad)
    out.riSinAltaP1 = !document.querySelector("#insBody .ins-catbtn.add");   // sin "+" en categorías
    insSetCat("fleje");
    out.riSinAltaEnCat = !document.querySelector("#insBody .ins-itbtn.add"); // sin "+" dentro de la categoría
    insBack();
    let alertRI = ""; let altas0 = posted.length;
    const _alRI = window.alert; window.alert = function (m) { alertRI = String(m); };
    insNuevoOpen("");
    out.riRechazaAlta = _ins.nuevo === null && /no se puede agregar un insumo/i.test(alertRI);
    insNuevoOpen("plastico");
    out.riRechazaAltaBolsa = _ins.nuevo === null;
    await new Promise(function (r) { setTimeout(r, 30); });
    out.riNoCreoNada = posted.length === altas0;   // no se posteó ningún insumo nuevo
    window.alert = _alRI;
    insBack();

    // 11) nada se sale del ancho del celular (390px)
    out.overflow = document.documentElement.scrollWidth - document.documentElement.clientWidth;
    return out;
  });

  const pass =
    r.nCats === 3 && r.ppFueraEnEI === true && r.sinItemsEnP1 === true && r.hayDep === true && r.enUso === true && r.finDisabled === true &&
    r.uni2745 === "Kg" && r.uniPP === "Bolsas" && r.uni2955 === "" &&
    r.nFleje === 3 && r.ordenFleje === "5,22,2745" && r.hayAtras === true &&
    /Fleje/.test(r.tituloFleje || "") && r.ubicEnBoton === true && r.sinAgregarEnEI === true && r.sinMasEnEI === true &&
    r.eiRechazaAlta === true &&
    r.popupAbierto === true && r.popupCod === "22" && r.popupStock === true && r.qtyTrasChg === 3 &&
    r.popupCerrado === true && r.botonMarcado === true && r.finHabilitado === true && r.finCuenta === true &&
    r.volvioAP1 === true && r.flejeMarcada === true && r.catCargados === true && r.qtySobrevive === 3 &&
    r.rowsBusca === 2 && r.buscaTraeDep === true &&
    r.avisoDep === true && r.nDep === 1 && r.noHayDepurar === true &&
    r.riSinAltaP1 === true && r.riSinAltaEnCat === true &&
    r.riRechazaAlta === true && r.riRechazaAltaBolsa === true && r.riNoCreoNada === true &&
    r.movN === 1 && r.confirmBloqueaSinUni === true && r.confirmAbreElQueFalta === true && r.movUbic === "V2 Ad" && r.movUni === "kg" && r.movDelta === -3 &&
    r.overflow === 0 &&
    errs.length === 0;
  console.log("ins-categorias:", JSON.stringify(r));
  console.log("  pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit(pass ? 0 : 1);
})();
