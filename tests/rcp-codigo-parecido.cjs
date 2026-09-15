/* Regresión v18.31 — al recibir, si el operario tipea un código que NO está en la lista de
   activos pero existe uno que sólo difiere en LETRAS al final (582 vs 582E), la pantalla
   pregunta "¿quisiste decir 582E?" antes de darlo por artículo nuevo.

   Por qué existe: el 15/09 aparecieron 7 recepciones cargadas con el código sin la E
   (582, 583, 584, 599, 727, 943, 948) cuando el artículo real era el importado. El
   operario tipea el número de memoria y se come la letra; el sistema lo tomaba como alta
   de artículo nuevo, le mandaba el WhatsApp a Thomas, y la entrega quedaba con un código
   que no existe — así que después no cruza con ninguna OC.

   Chequea `arCatalogoParecidos`, que es la que decide:
   - 582 → sugiere 582E (le falta una letra)
   - 582E → sugiere 582 (le sobra)
   - 438EL → sugiere 438E
   - 583 NO sugiere 584 ni 593: un dígito distinto es OTRO artículo, nunca se sugiere
   - un código que sí está en la lista no se sugiere a sí mismo
   - sin catálogo cargado devuelve vacío (no se traba a nadie)
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
    // se evalúan sólo las dos funciones que importan, con un catálogo de laboratorio
    const _ocgNorm = window._ocgNorm;
    let _arCatalogo = null;
    const fn = new Function("_ocgNorm", "getCat", código.match(
      /function arCatalogoParecidos\(cod\) \{[\s\S]*?\n\}/)[0].split("_arCatalogo").join("getCat()") + "; return arCatalogoParecidos;");
    const cat = [
      { cod: "582E", desc: "Salero 90 ml" },
      { cod: "584E", desc: "Aceitera 400 ml" },
      { cod: "593",  desc: "Otro articulo" },
      { cod: "438E", desc: "Importado" },
      { cod: "31",   desc: "Filtro De Cafe" }
    ];
    const parecidos = fn(_ocgNorm, function () { return cat; });
    const cods = function (x) { return parecidos(x).map(function (a) { return a.cod; }); };
    const out = {};
    out.faltaLetra  = cods("582").join(",");             // 582E
    out.sobraLetra  = cods("582E").join(",");            // (582 no esta en el catalogo) → ""
    out.dosLetras   = cods("438EL").join(",");           // 438E
    out.noOtroDigito = cods("583").join(",");            // "" — 584E y 593 son otros articulos
    out.noASiMismo  = cods("593").join(",");             // ""
    out.sinCatalogo = (function () {
      const f2 = new Function("_ocgNorm", "getCat", código.match(
        /function arCatalogoParecidos\(cod\) \{[\s\S]*?\n\}/)[0].split("_arCatalogo").join("getCat()") + "; return arCatalogoParecidos;");
      return f2(_ocgNorm, function () { return null; })("582").length;
    })();
    return out;
  }, src);
  const pass =
    r.faltaLetra === "582E" && r.sobraLetra === "" && r.dosLetras === "438E" &&
    r.noOtroDigito === "" && r.noASiMismo === "" && r.sinCatalogo === 0 &&
    errs.length === 0;
  console.log("rcp-codigo-parecido:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
