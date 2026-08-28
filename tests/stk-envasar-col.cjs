/* Regresión v7.03 — la tabla de Stock muestra los depósitos `para_envasar` y `racks_ch`.
   Antes no estaban en SECT/SECTKEYS: las cajas de "p/ envasar" (ej. 035E = 44) y de
   "racks CH" no aparecían en NINGUNA columna, no sumaban al Total Stock, y un artículo
   que estaba SOLO en esos depósitos (439E, 809E) no aparecía en la tabla.

   Chequea, con un _stk de laboratorio (sin red):
   - 035E: Total Stock incluye p/envasar (31 góndola + 2 pickeados + 44 envasar = 77),
     hay columna "P/ envasar" con 44.
   - 439E (solo p/envasar 84): aparece en la tabla (antes se filtraba por todo-cero).
   - Cuando NINGÚN artículo tiene p/envasar ni racks_ch, esas columnas NO se dibujan.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }

const MOVS = [
  // 035E: 31 góndola + 2 pickeados + 44 para_envasar
  { cod_art: "035E", descripcion: "Cernidor Harina", deposito: "terminado", tipo: "inicial", delta: 31, ts: "2026-08-01T16:00:00Z" },
  { cod_art: "035E", deposito: "separar_pedidos", tipo: "picking", delta: 2, ts: "2026-08-02T12:00:00Z", ref: "X1" },
  { cod_art: "035E", deposito: "para_envasar", tipo: "guardado", delta: 44, ts: "2026-08-02T13:00:00Z" },
  // 439E: SOLO para_envasar 84 (nada en los depósitos "clásicos")
  { cod_art: "439E", descripcion: "Art solo envasar", deposito: "para_envasar", tipo: "guardado", delta: 84, ts: "2026-08-02T13:00:00Z" },
  // 712: SOLO racks_ch 444
  { cod_art: "712E", descripcion: "Art solo racks CH", deposito: "racks_ch", tipo: "guardado", delta: 444, ts: "2026-08-02T13:00:00Z" }
];
// Set de movs SIN envasar/racks_ch → las columnas extra NO deben dibujarse.
const MOVS_SIN = [
  { cod_art: "100", descripcion: "Normal", deposito: "terminado", tipo: "inicial", delta: 10, ts: "2026-08-01T16:00:00Z" }
];

(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(function (fix) {
    /* v10.00 — stkBodyStocks dejó de sumar los movimientos en el navegador: en modo
       normal lee los saldos ya calculados en `_stk.viewRows` (espejo de la vista
       stocks_carga_rapida) y solo recalcula desde `_stk.movs` en modo As-Of. Estos
       tests arman movimientos de laboratorio, así que los plegamos al formato de la
       vista. Sin esto la tabla salía vacía y el test fallaba desde v10.00. */
    function viewRowsDeMovs(movs) {
      var m = {};
      (movs || []).forEach(function (mv) {
        var k = String(mv.cod_art || "").trim(); if (!k) return;
        if (!m[k]) m[k] = { cod: k, descripcion: "", terminado: 0, excedente: 0, separar_pedidos: 0,
                            a_facturar: 0, a_guardar: 0, racks: 0, racks_ch: 0, para_envasar: 0, insumos_dep: 0 };
        if (mv.descripcion) m[k].descripcion = mv.descripcion;
        if (Object.prototype.hasOwnProperty.call(m[k], mv.deposito)) m[k][mv.deposito] += Number(mv.delta) || 0;
      });
      return Object.keys(m).map(function (k) { return m[k]; });
    }
    function render(movs) {
      _stk = { movs: movs, viewRows: viewRowsDeMovs(movs), cutoff: null, asOf: null, dem: {}, cap: [], fcs: { porArt: {}, pend: {} }, filtro: "", gConf: [] };
      return stkBodyStocks();
    }
    const out = {};
    const html = render(fix.MOVS);
    // Fila 035E: Total Stock 77 y una celda con 44.
    out.tieneColEnvasar = html.indexOf("P/<br>envasar") >= 0;   // header "P/ envasar" → "P/<br>envasar"
    // v7.54: racks_ch se fusionó en la columna "Racks" → NO hay columna separada "Racks CH".
    out.noSepRacksCh = html.indexOf("Racks<br>CH") < 0;
    out.muestra035E = html.indexOf("035E") >= 0;
    out.muestra439E = html.indexOf("439E") >= 0;      // antes NO aparecía (solo envasar)
    out.muestra712E = html.indexOf("712E") >= 0;      // v7.71: art SOLO en racks_ch vuelve a aparecer
    out.racks712E = html.indexOf(">444<") >= 0;       // v7.54/v7.71: su racks_ch (444) va en la columna "Racks"
    out.total77 = html.indexOf(">77<") >= 0;          // Total Stock de 035E = 31+2+44
    out.tieneTira = html.indexOf("P/ envasar") >= 0 || html.indexOf("P/<br>envasar") >= 0;
    // Sin envasar/racks_ch → columnas extra ausentes.
    const html2 = render(fix.MOVS_SIN);
    out.sinColEnvasar = html2.indexOf("P/<br>envasar") < 0;
    out.sinColRacksCh = html2.indexOf("Racks<br>CH") < 0;
    out.muestra100 = html2.indexOf(">100<") >= 0 || html2.indexOf("100") >= 0;
    return out;
  }, { MOVS: MOVS, MOVS_SIN: MOVS_SIN });

  const pass = r.tieneColEnvasar && r.noSepRacksCh && r.muestra035E && r.muestra439E &&
    r.muestra712E && r.racks712E && r.total77 && r.sinColEnvasar && r.sinColRacksCh && errs.length === 0;
  console.log("stk-envasar-col:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
