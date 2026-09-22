/* Regresion v20.95 (Luis, 22/09/2026) — "838E NO APARECE en la vista de stocks".

   La tabla de Stock esconde, a proposito, las filas que estan en 0 en TODOS los sectores
   y sin pedidos: son ruido cuando uno mira la tabla entera. Pero ese mismo filtro se
   aplicaba TAMBIEN cuando se buscaba un codigo, asi que tipear el codigo entero no traia
   nada y era indistinguible de "ese codigo no existe". Eran 46 codigos, 21 con proyeccion
   viva (838E: capacidad 35, proy 34,17 caj/mes).

   Chequea las dos mitades, porque una sin la otra no sirve:
   - SIN buscar  -> el codigo en 0 sigue OCULTO (no vuelve el ruido).
   - BUSCANDOLO  -> aparece, con sus ceros.
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
    const cero = { cod: "838E", descripcion: "Rallador Cilindrico Mini", linea: "CH", terminado: 0,
      excedente: 0, separar_pedidos: 0, a_facturar: 0, a_guardar: 0, racks: 0, racks_ch: 0,
      para_envasar: 0, insumos_dep: 0, stock_total: 0, cajas_pedidas: 0 };
    const conStock = Object.assign({}, cero, { cod: "839", descripcion: "Rallador Chocolate/Limon 14Cm", terminado: 2, stock_total: 2 });
    const armar = function (filtro) {
      _stk = { movs: [], viewRows: [cero, conStock], cutoff: 0, dem: { "839": 16 }, cap: [], fcs: {},
               gConf: [], filtro: filtro, openArt: null, soloNeg: false };
      return stkBodyStocks();
    };
    const ve = function (html, cod) { return html.indexOf('data-stk-cod="' + cod + '"') >= 0; };
    const sinBuscar = armar(""), buscando = armar("838"), porDesc = armar("rallador cilindrico");
    return {
      ocultoSinBuscar: !ve(sinBuscar, "838E"),   // el ruido no vuelve
      veElQueTieneStock: ve(sinBuscar, "839"),
      apareceAlBuscarCod: ve(buscando, "838E"),  // lo que pidio Luis
      apareceAlBuscarDesc: ve(porDesc, "838E")
    };
  });
  const pass = r.ocultoSinBuscar && r.veElQueTieneStock && r.apareceAlBuscarCod && r.apareceAlBuscarDesc && errs.length === 0;
  console.log("stk-buscar-cero:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
