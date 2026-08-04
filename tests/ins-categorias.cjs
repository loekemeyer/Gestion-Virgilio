/* Regresión v7.05 / idea 7917 — Insumos (RI/EI): botonera de categorías.
   El modal listaba los 108 códigos planos por código y la única forma de llegar a uno
   era el buscador de texto. Ahora `Insumos.categoria` alimenta chips arriba del
   buscador. Este test fija el contrato:
     · los chips se arman con los conteos reales y "Todos" NO cuenta los "a depurar"
     · el listado por defecto esconde "a depurar" (pero el chip existe, con su aviso)
     · chip y buscador son alternativos: buscar mira TODO (incluso lo a depurar)
     · la unidad por defecto sale de la categoría (Fleje ⇒ Kg, Plástico ⇒ Bolsas)
       salvo que el insumo ya tenga saldo en UNA sola unidad (idea 7382 manda)
     · los flejes se ordenan por MEDIDA, no por código
     · el alta nace con la categoría del chip activo
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
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(root, "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    const posted = [];
    function J(data) {
      return Promise.resolve({ ok: true, status: 200, headers: { get: function () { return null; } }, json: function () { return Promise.resolve(data); } });
    }
    // Catálogo chico pero con las 3 categorías que importan + un "a depurar".
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
    const rows = function () { return document.querySelectorAll("#insBody .ins-row").length; };
    const cods = function () { return Array.prototype.map.call(document.querySelectorAll("#insBody .ins-row .ins-cod"), function (e) { return e.textContent.trim().replace(/^📍\s*/, ""); }); };
    const chipByTxt = function (t) { return Array.prototype.filter.call(document.querySelectorAll("#insBody .ins-cchip"), function (e) { return e.textContent.indexOf(t) >= 0; })[0] || null; };

    // 1) Botonera armada, "Todos" = 5 (los 6 menos el 'depurar'), 'depurar' con su chip
    out.chips = Array.prototype.map.call(document.querySelectorAll("#insBody .ins-cchip"), function (e) { return e.textContent.replace(/\s+/g, " ").trim(); });
    out.todosCount = (chipByTxt("Todos") || {}).textContent.replace(/\D/g, "");     // "5"
    out.hayChipDep = !!chipByTxt("A depurar");
    out.rowsDefault = rows();                                                       // 5 (sin el depurar)
    out.depFueraDefault = cods().indexOf("505C·CUCHILLA CHINA") < 0 && cods().indexOf("505c") < 0;

    // 2) La modalidad EI pinta los chips en teal (clase del body), no en indigo
    out.bodyOut = /(^|\s)out(\s|$)/.test((document.getElementById("insBody") || {}).className || "");

    // 3) Unidad por defecto por CATEGORÍA: fleje sin saldo ⇒ Kg; plástico con saldo
    //    en UNA unidad ⇒ esa (Bolsas, idea 7382 manda sobre el default de categoría)
    const byCod = {}; _ins.items.forEach(function (it) { byCod[it.cod] = it; });
    out.uni2745 = byCod["2745"].unidad;      // "Kg"  (fleje, sin saldo)
    out.uniPP = byCod["PP"].unidad;          // "Bolsas" (saldo en 1 sola unidad)
    out.uni2955 = byCod["2955"].unidad;      // "Uni" (inox)
    // el chip de la unidad de la categoría existe aunque no esté en las guardadas
    const rowPP = Array.prototype.filter.call(document.querySelectorAll("#insBody .ins-row"), function (e) { return /POLIPROPILENO/.test(e.textContent); })[0];
    out.ppTieneChipBolsas = !!rowPP && Array.prototype.some.call(rowPP.querySelectorAll(".ins-uchip"), function (e) { return e.textContent.trim() === "Bolsas"; });

    // 4) Chip 'Fleje': solo flejes y ordenados por MEDIDA (38 → 121 → 168), no por código
    insSetCat("fleje");
    out.rowsFleje = rows();                                                          // 3
    out.ordenFleje = cods().join(",");                                               // "5,22,2745"
    out.ubicVisible = /V2 Ad/.test(document.getElementById("insBody").innerHTML);

    // 5) Buscar mira TODO (incluso lo 'a depurar') y desactiva el chip
    _ins.filtro = "cuchilla"; insRender();
    out.rowsBusca = rows();                                                          // 2 (2955 + el depurar)
    out.buscaTraeDep = document.getElementById("insBody").innerHTML.indexOf("CUCHILLA CHINA") >= 0;
    out.chipApagadoAlBuscar = !(chipByTxt("Fleje") || { classList: { contains: function () { return true; } } }).classList.contains("on");
    out.badgeCatAlBuscar = /A depurar/.test(document.getElementById("insBody").innerHTML);

    // 6) Chip 'A depurar': muestra el aviso y SOLO los viejos
    insSetCat("depurar");
    out.filtroLimpioAlChip = _ins.filtro === "";
    out.rowsDep = rows();                                                            // 1
    out.avisoDep = !!document.querySelector("#insBody .ins-depw");

    // 7) Re-tocar el chip activo deselecciona → vuelve al default
    insSetCat("depurar");
    out.rowsVuelta = rows();                                                         // 5

    // 8) El alta nace con la categoría del chip activo y su unidad
    insSetCat("plastico");
    document.getElementById("insNewId").value = "1234567";
    document.getElementById("insNewNom").value = "Nylon nuevo";
    await insCrear();
    const nue = _ins.items.filter(function (it) { return it.cod === "1234567"; })[0];
    out.altaCat = nue ? nue.cat : null;                                              // "plastico"
    out.altaUni = nue ? nue.unidad : null;                                           // "Bolsas"
    out.altaPosteoCat = (posted[0] || {}).categoria;                                 // "plastico"
    out.altaVisible = cods().indexOf("1234567") >= 0;                                // queda a la vista

    // 9) El movimiento lleva la UBICACIÓN física, no el sector
    byCod["22"].qty = 3;
    let mov = null;
    const _sm = window.stockMove; window.stockMove = function (rows) { mov = rows; };
    window.alert = function () {};
    insConfirmar();
    window.stockMove = _sm;
    out.movUbic = mov && mov[0] ? mov[0].ubicacion : null;                           // "V2 Ad"
    // "kg" en minúscula: el 22 ya tiene saldo en esa unidad y la idea 7382 manda sobre
    // el default de la categoría — no le cambiamos la unidad a un saldo que ya existe.
    out.movUni = mov && mov[0] ? mov[0].unidad : null;                               // "kg"
    out.movDelta = mov && mov[0] ? mov[0].delta : null;                              // -3 (EI)
    return out;
  });

  const pass =
    r.todosCount === "5" && r.hayChipDep === true && r.rowsDefault === 5 && r.depFueraDefault === true &&
    r.bodyOut === true &&
    r.uni2745 === "Kg" && r.uniPP === "Bolsas" && r.uni2955 === "Uni" && r.ppTieneChipBolsas === true &&
    r.rowsFleje === 3 && r.ordenFleje === "5,22,2745" && r.ubicVisible === true &&
    r.rowsBusca === 2 && r.buscaTraeDep === true && r.chipApagadoAlBuscar === true && r.badgeCatAlBuscar === true &&
    r.filtroLimpioAlChip === true && r.rowsDep === 1 && r.avisoDep === true &&
    r.rowsVuelta === 5 &&
    r.altaCat === "plastico" && r.altaUni === "Bolsas" && r.altaPosteoCat === "plastico" && r.altaVisible === true &&
    r.movUbic === "V2 Ad" && r.movUni === "kg" && r.movDelta === -3 &&
    errs.length === 0;
  console.log("ins-categorias:", JSON.stringify(r));
  console.log("  pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit(pass ? 0 : 1);
})();
