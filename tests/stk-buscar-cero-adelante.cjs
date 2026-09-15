/* Regresión v18.20 — el buscador de Stocks tiene que encontrar aunque se tipee el código CON
   el cero adelante. La tabla muestra el código canónico ("031"), pero en la base vive
   normalizado ("31"), y el filtro comparaba el texto tipeado contra el valor crudo: tipear
   "031" no devolvía nada y tipear "31" sí. O sea, la pantalla enseñaba un código que después
   ella misma no encontraba. Lo reportó Thomas el 15/09 con una foto.

   Es la cara "BUSCAR" de la regla del dueño del 12/09 (ver tests/cod-cero-adelante.cjs):
   al escribir, el cero va siempre; al buscar, tiene que dar igual.

   v18.25 — segunda vuelta, mismo día: "arreglado que pueda buscar, pero busca 31, no 031.
   Solo debería mostrar lo que corresponde a la coincidencia de esos 3 dígitos". Un término
   que es un CÓDIGO deja de buscar por pedazo: "031" trae el 031 y sus variantes de letra
   (031E, "031 LK", que son el mismo artículo) y NO los ocho que lo contienen — 231, 311,
   312, 315, 531, 631, 731, 931E. Un término que no arranca con dígito sigue siendo texto
   libre.

   Chequea, sobre las mismas filas:
   - "031", "31" y "0031" encuentran el 031 (los tres, es el mismo código).
   - ninguno de los tres trae el 231, el 311 ni el 931E.
   - "31E" trae la variante importada, porque lo que sigue al código es una letra.
   - buscar por descripción sigue andando ("café").
   - un código que no existe no trae nada (que el filtro no se haya vuelto un pasamanos).
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const ts = "2026-08-01T10:00:00Z";
    const filas = [
      { cod: "31",   descripcion: "Filtro De Café 10cm" },
      { cod: "31E",  descripcion: "Filtro De Café Importado" },
      { cod: "231",  descripcion: "Palo Amasar 30cm" },
      { cod: "311",  descripcion: "Cuchillo De Torta Ac. Inox" },
      { cod: "931E", descripcion: "Espátula Lisa Nylon Mgo Mad" },
      { cod: "706",  descripcion: "Abrelatas Uña Blanco" }
    ];
    const viewRows = filas.map(function (f) {
      return { cod: f.cod, descripcion: f.descripcion, terminado: 100, excedente: 0, separar_pedidos: 0,
               a_facturar: 0, a_guardar: 0, racks: 0, racks_ch: 0, para_envasar: 0, insumos_dep: 0 };
    });
    const movs = filas.map(function (f) {
      return { cod_art: f.cod, deposito: "terminado", delta: 100, tipo: "inicial", ts: ts, descripcion: f.descripcion };
    });
    const conFiltro = function (q) {
      _stk = { movs: movs, viewRows: viewRows, cutoff: 0, dem: {}, cap: [], fcs: {}, gConf: [],
               filtro: q, openArt: null, soloNeg: false };
      return stkBodyStocks();
    };
    const ve = function (html, cod) { return html.indexOf('data-stk-cod="' + cod + '"') >= 0; };
    const out = {};
    const h031 = conFiltro("031"), h31 = conFiltro("31"), h0031 = conFiltro("0031");
    out.busca031 = ve(h031, "31");            // ← el bug de la v18.20: esto daba false
    out.busca31 = ve(h31, "31");
    out.busca0031 = ve(h0031, "31");
    // v18.25 — y ninguno de los tres trae a los que sólo CONTIENEN esos dígitos
    out.sinVecinos = ["231", "311", "931E"].every(function (c) {
      return !ve(h031, c) && !ve(h31, c) && !ve(h0031, c);
    });
    // la variante de letra sí es el mismo artículo
    out.traeVariante = ve(h031, "31E") && ve(h31, "31E");
    out.busca31E = ve(conFiltro("31E"), "31E") && !ve(conFiltro("31E"), "931E");
    out.buscaDesc = ve(conFiltro("café"), "31");
    const hNada = conFiltro("099999");
    out.nadaNoTrae = !ve(hNada, "31") && !ve(hNada, "231") && !ve(hNada, "706");
    return out;
  });
  const pass = r.busca031 && r.busca31 && r.busca0031 && r.sinVecinos && r.traeVariante &&
    r.busca31E && r.buscaDesc && r.nadaNoTrae && errs.length === 0;
  console.log("stk-buscar-cero-adelante:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
