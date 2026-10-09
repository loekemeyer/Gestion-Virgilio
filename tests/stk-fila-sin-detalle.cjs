/* v25.56 (Luis, 01/10): "que se expanda el detalle de una fila no va. Solo salen los popups
   para consultar movimientos en sectores especificos" · "el detalle de movimientos ordenado de
   mas reciente (arriba) a mas antiguo (abajo)". Reemplaza a stk-detalle-cero-adelante (v20.02),
   que medía el detalle inline que ya no existe.
   Candado estático + corrida de _stkMovsBlock:
   (A) la fila de Stocks no tiene onclick a stockToggleArt ni dibuja stk-detrow;
   (B) _stkMovsBlock muestra el movimiento más reciente ARRIBA, y el saldo de cada fila es el
       acumulado hasta ese momento (el de arriba = saldo final). Sale 1 si falla. */
const fs = require("fs"), path = require("path");
const src = fs.readFileSync(path.join(__dirname, "..", "index.html")).toString("utf8");
let ok = true; const fail = (m) => { ok = false; console.error("✗ " + m); };
const i = src.indexOf("shown.forEach(function (a) {"), j = src.indexOf('h += "</tbody></table></div>";', i);
const fila = src.slice(i, j);
if (i < 0 || j < 0) fail("no encontré el render de la tabla de Stocks");
if (/stockToggleArt\(/.test(fila)) fail("(A) la fila de Stocks sigue expandiéndose (stockToggleArt)");
if (/stk-detrow/.test(fila)) fail("(A) la fila de Stocks sigue dibujando el detalle inline");
// (B)
const a = src.indexOf("function _stkMovsBlock() {"), b = src.indexOf("\n}\n", a);
const fn = src.slice(a, b + 2);
const movs = [
  { id: 1, cod_art: "026", deposito: "terminado", tipo: "recepcion", delta: 10, ref: "R1", ts: "2026-09-01T10:00:00Z" },
  { id: 2, cod_art: "026", deposito: "terminado", tipo: "picking", delta: -3, ref: "E01A", ts: "2026-09-10T10:00:00Z" },
  { id: 3, cod_art: "026", deposito: "terminado", tipo: "guardado", delta: 5, ref: "G", ts: "2026-09-20T10:00:00Z" }
];
const ctx = {
  _stkPop: { dep: "terminado", codN: "26", emp: "", kind: "movsArt", desde: "", hasta: "", cod: "026", titulo: "Góndola", _freshMovs: movs },
  _stk: { movs: [] },
  _stkMovMatch: () => true, _stkWin: () => true, escapeHtml: (x) => String(x), codBase: (x) => x,
  stockFmtTs: (t) => String(t).slice(0, 10), _padCod: (x) => String(x), _stkQuienChip: () => "", _stkRtoDetail: () => ""
};
let html = "";
try { html = new Function(...Object.keys(ctx), fn + "\nreturn _stkMovsBlock();")(...Object.values(ctx)); }
catch (e) { fail("(B) _stkMovsBlock tiró: " + e.message); }
const fechas = [...html.matchAll(/class="mva-ts">([^<]+)</g)].map((m) => m[1]);
const saldos = [...html.matchAll(/class="mva-sal">([^<]+)</g)].map((m) => m[1]);
if (fechas.join(",") !== "2026-09-20,2026-09-10,2026-09-01") fail("(B) orden esperado del más reciente al más viejo, dio " + fechas.join(","));
if (saldos.join(",") !== "12,7,10") fail("(B) saldos acumulados esperados 12,7,10, dio " + saldos.join(","));
console.log("stk-fila-sin-detalle: " + (ok ? "✓ OK" : "✗ FAIL"));
process.exit(ok ? 0 : 1);
