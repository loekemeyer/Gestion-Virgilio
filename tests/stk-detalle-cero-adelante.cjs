/* Regresión v20.02 — al tocar una fila de Stocks, el detalle inline decía "sin movimientos
   contados" en códigos que SÍ tienen movimientos. Lo reportó Thomas el 18/09 con una foto del
   055, que muestra 21 cajas en góndola y abajo el cartel de que no hay nada contado.

   Causa: la fila expandida matcheaba el código CRUDO (`String(mv.cod_art) === a.cod`) mientras
   que las dos puntas se escriben distinto —
     · la fila viene de la vista sin el cero adelante ("55", "35E"), Movimientos_Stock lo guarda
       con cero ("055", "035E");
     · la fila de un dual viene con sufijo de empresa ("809E LK"), el movimiento guarda el código
       bare ("809E") + la columna `empresa`.
   Medido el 18/09: 31 de las 367 filas de stocks_carga_rapida no matcheaban literal (23 con cero
   adelante — 830 cajas el 031, 306 el 066 — y los 8 duales partidos, 349 cajas el 809E LK).

   Es exactamente el bug que la v14.58 arregló en los POP-UPS con _stkMovMatch; el detalle inline
   había quedado con la comparación vieja.

   Chequea:
   - abrir el "55" (movs "055") muestra los movimientos, no el cartel;
   - abrir el "35E" (movs "035E") idem;
   - abrir "809E LK" trae SÓLO los movimientos de LK, y "809E CH" sólo los de CH;
   - un código sin ningún movimiento sigue diciendo "sin movimientos contados" (que el arreglo no
     se haya vuelto un pasamanos que muestra los movimientos de otro).
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
    const ts = "2026-09-10T10:00:00Z";
    const viewRows = [
      { cod: "55",      descripcion: "Codigo con cero adelante",  terminado: 21, excedente: 0, separar_pedidos: 0, a_facturar: 0, a_guardar: 0, racks: 0, racks_ch: 0, para_envasar: 0, insumos_dep: 0 },
      { cod: "35E",     descripcion: "Cernidor de Harina",        terminado: 42, excedente: 0, separar_pedidos: 2, a_facturar: 0, a_guardar: 0, racks: 0, racks_ch: 0, para_envasar: 0, insumos_dep: 0 },
      { cod: "809E LK", descripcion: "Dual lado Loekemeyer",      terminado: 30, excedente: 0, separar_pedidos: 0, a_facturar: 0, a_guardar: 0, racks: 0, racks_ch: 0, para_envasar: 0, insumos_dep: 0 },
      { cod: "809E CH", descripcion: "Dual lado Chef",            terminado: 10, excedente: 0, separar_pedidos: 0, a_facturar: 0, a_guardar: 0, racks: 0, racks_ch: 0, para_envasar: 0, insumos_dep: 0 },
      { cod: "706",     descripcion: "Sin movimientos de verdad", terminado: 7,  excedente: 0, separar_pedidos: 0, a_facturar: 0, a_guardar: 0, racks: 0, racks_ch: 0, para_envasar: 0, insumos_dep: 0 }
    ];
    const movs = [
      { cod_art: "055",  deposito: "terminado", delta: 21, tipo: "inicial", ts: ts, descripcion: "Codigo con cero adelante", ref: "MOV055" },
      { cod_art: "035E", deposito: "terminado", delta: 42, tipo: "inicial", ts: ts, descripcion: "Cernidor de Harina",       ref: "MOV035E" },
      { cod_art: "809E", empresa: "LK", deposito: "terminado", delta: 30, tipo: "inicial", ts: ts, descripcion: "Dual", ref: "MOVLK" },
      { cod_art: "809E", empresa: "CH", deposito: "terminado", delta: 10, tipo: "inicial", ts: ts, descripcion: "Dual", ref: "MOVCH" }
    ];
    const abrir = function (cod) {
      _stk = { movs: movs, viewRows: viewRows, cutoff: 0, dem: {}, cap: [], fcs: {}, gConf: [],
               filtro: "", openArt: cod, soloNeg: false };
      const h = stkBodyStocks();
      const i = h.indexOf('data-stk-cod="' + String(cod).toUpperCase() + '"');
      return i < 0 ? "" : h.slice(i, i + 9000);   // la fila + su detrow
    };
    const out = {};
    const h55 = abrir("55"), h35 = abrir("35E"), hLK = abrir("809E LK"), hCH = abrir("809E CH"), h706 = abrir("706");
    out.cod55 = h55.indexOf("sin movimientos contados") < 0 && h55.indexOf("MOV055") >= 0;
    out.cod35E = h35.indexOf("sin movimientos contados") < 0 && h35.indexOf("MOV035E") >= 0;
    out.dualLK = hLK.indexOf("MOVLK") >= 0 && hLK.indexOf("MOVCH") < 0;
    out.dualCH = hCH.indexOf("MOVCH") >= 0 && hCH.indexOf("MOVLK") < 0;
    out.sinMovsSigueAvisando = h706.indexOf("sin movimientos contados") >= 0;
    return out;
  });
  const pass = r.cod55 && r.cod35E && r.dualLK && r.dualCH && r.sinMovsSigueAvisando && errs.length === 0;
  console.log("stk-detalle-cero-adelante:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
