/* v21.78 — ESTE TEST MEDÍA UNA REGLA QUE LUIS DEROGÓ. Se actualiza, no se "arregla" el código.

   La v18.20/v18.25 pedía que "31" y "0031" encontraran al 031: el código vive normalizado en
   la base ("31") y la tabla lo muestra con el cero ("031"), así que se buscaba contra las dos
   grafías. La v21.09 lo dio vuelta, textual de Luis: "si busco 30 en la tabla aparece el 030 y
   es un error". Hoy el prefijo se mide SÓLO contra la grafía MOSTRADA.

   Lo que cambia, y es el costo que Luis aceptó: para el 031 se escribe "031" o "0", no "31".
   A cambio, "31" ya no arrastra al 031 cuando uno busca los 31x.

   Lo que NO cambió y sigue verificándose: "031" encuentra al 031 (el bug original de la
   v18.20, que era no encontrar lo que la propia pantalla muestra), no arrastra a los que sólo
   CONTIENEN esos dígitos, y la búsqueda por descripción sigue siendo por pedazo.

   Regresión v18.20 — el buscador de Stocks tiene que encontrar aunque se tipee el código CON
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
    // el bug original de la v18.20: la pantalla muestra "031" y no lo encontraba. Sigue vivo.
    out.busca031 = ve(h031, "31");
    // v21.09 (Luis): "31" NO trae el 031 — el prefijo se mide contra la grafía MOSTRADA
    out.el31NoTraeEl031 = !ve(h31, "31");
    out.el0031NoTraeNada = !ve(h0031, "31");
    // …pero "31" SÍ trae al 311, que EMPIEZA con 31. Eso es la regla, no un efecto colateral.
    out.el31TraeEl311 = ve(h31, "311");
    // "031" no arrastra a los que sólo CONTIENEN esos dígitos (v18.25, sigue valiendo)
    out.sinVecinos = ["231", "311", "931E"].every(function (c) { return !ve(h031, c); });
    // la variante de letra es el mismo artículo y entra por el prefijo de la grafía mostrada
    out.traeVariante = ve(h031, "31E");
    // y "31E" tampoco alcanza al 031E: se tipea como se muestra
    out.el31ENoTrae = !ve(conFiltro("31E"), "31E") && !ve(conFiltro("31E"), "931E");
    out.buscaDesc = ve(conFiltro("café"), "31");     // texto libre: sigue por pedazo
    const hNada = conFiltro("099999");
    out.nadaNoTrae = !ve(hNada, "31") && !ve(hNada, "231") && !ve(hNada, "706");
    return out;
  });
  const pass = r.busca031 && r.el31NoTraeEl031 && r.el0031NoTraeNada && r.el31TraeEl311 &&
    r.sinVecinos && r.traeVariante && r.el31ENoTrae && r.buscaDesc && r.nadaNoTrae && errs.length === 0;
  console.log("stk-buscar-cero-adelante:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
