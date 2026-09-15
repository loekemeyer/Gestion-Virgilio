/* Regresión v18.41 — el buscador de códigos de la RECEPCIÓN encuentra igual con ceros
   adelante.

   Por qué existe: el catálogo de activos se guarda normalizado con `_ocgNorm` (que pela
   los ceros de adelante: "0582" → "582"), pero `arCatalogoBuscar` filtraba por lo tipeado
   TAL CUAL. O sea que un operario que escribía "0582" no veía NADA, y la única salida que
   le quedaba en pantalla era "➕ Cargar igual: 582 (le avisamos a Thomy)" — dando de alta
   un artículo que no existe, con el 582E ahí al lado y invisible. Es el mismo bug de los
   ceros que se arregló en Stocks en la v18.26.

   Chequea `arCatalogoBuscar`:
   - "0582" encuentra 582E (antes: nada)
   - "582"  lo sigue encontrando
   - buscar por descripción sigue andando
   - "0593" no arrastra de más: sólo el 593
   - vacío devuelve el catálogo entero
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const src = require("fs").readFileSync(path.join(__dirname, "..", "recepcion.js"), "utf8");
  const r = await p.evaluate(function (código) {
    const _ocgNorm = window._ocgNorm;
    const opNorm = function (s) {
      return (s || "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
    };
    const cuerpo = código.match(/function arCatalogoBuscar\(txt\) \{[\s\S]*?\n\}/)[0];
    const fn = new Function("_ocgNorm", "opNorm", "getCat",
      cuerpo.split("_arCatalogo").join("getCat()") + "; return arCatalogoBuscar;");
    const mk = function (cod, desc) {
      return { cod: cod, desc: desc, busq: opNorm(cod + " " + desc) };
    };
    const cat = [mk("582E", "Salero 90 ml"), mk("593", "Otro articulo"), mk("31", "Filtro De Cafe")];
    const buscar = fn(_ocgNorm, opNorm, function () { return cat; });
    const cods = function (x) { return buscar(x).map(function (a) { return a.cod; }).join(","); };
    return {
      conCero:   cods("0582"),      // 582E
      sinCero:   cods("582"),       // 582E
      porDesc:   cods("salero"),    // 582E
      ceroOtro:  cods("0593"),      // 593
      vacio:     buscar("").length  // 3
    };
  }, src);
  const pass =
    r.conCero === "582E" && r.sinCero === "582E" && r.porDesc === "582E" &&
    r.ceroOtro === "593" && r.vacio === 3 && errs.length === 0;
  console.log("rcp-buscar-cero-adelante:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
