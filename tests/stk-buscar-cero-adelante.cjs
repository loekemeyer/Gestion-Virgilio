/* Regresión v18.20 — el buscador de Stocks tiene que encontrar aunque se tipee el código CON
   el cero adelante. La tabla muestra el código canónico ("031"), pero en la base vive
   normalizado ("31"), y el filtro comparaba el texto tipeado contra el valor crudo: tipear
   "031" no devolvía nada y tipear "31" sí. O sea, la pantalla enseñaba un código que después
   ella misma no encontraba. Lo reportó Thomas el 15/09 con una foto.

   Es la cara "BUSCAR" de la regla del dueño del 12/09 (ver tests/cod-cero-adelante.cjs):
   al escribir, el cero va siempre; al buscar, tiene que dar igual.

   Chequea, sobre las mismas filas:
   - "031" y "31" encuentran los dos el 031 (y el "31" sigue trayendo los que lo contienen).
   - "0031" también, que es lo que pasa si alguien pega un código de un Excel.
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
      { cod: "31",  descripcion: "Filtro De Café 10cm" },
      { cod: "231", descripcion: "Palo Amasar 30cm" },
      { cod: "706", descripcion: "Abrelatas Uña Blanco" }
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
    out.busca031 = ve(h031, "31");            // ← el bug: esto daba false
    out.busca31 = ve(h31, "31");
    out.busca0031 = ve(h0031, "31");
    out.el31TraeEl231 = ve(h31, "231");       // indexOf, igual que antes: no se cambió el criterio
    out.el031TraeEl231 = ve(h031, "231");
    out.buscaDesc = ve(conFiltro("café"), "31");
    const hNada = conFiltro("099999");
    out.nadaNoTrae = !ve(hNada, "31") && !ve(hNada, "231") && !ve(hNada, "706");
    return out;
  });
  const pass = r.busca031 && r.busca31 && r.busca0031 && r.el31TraeEl231 && r.el031TraeEl231 &&
    r.buscaDesc && r.nadaNoTrae && errs.length === 0;
  console.log("stk-buscar-cero-adelante:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
