/* Regresión v7.71 — la tabla de Stock OCULTA la fila del código BASE de una familia empresa-split
   (ej. "438E") cuando no tiene stock propio y la familia sí tiene stock en LK/CH. El stock vive en
   "438E LK"/"438E CH"; sin esto quedaba una fila fantasma (base 0 stock + cajas pedidas). Un base
   CON stock propio (437E) NO se oculta.

   Chequea:
   - "438E" base (0 stock, demanda 37, familia 438E LK/CH con stock) → OCULTA.
   - "439E" base (0 stock, demanda 28, familia 439E LK con stock) → OCULTA.
   - "438E LK", "438E CH", "439E LK" → se ven.
   - "437E" base (stock propio 36) → se ve.
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
    const out = {};
    const ts = "2026-08-01T10:00:00Z";
    const movs = [
      { cod_art: "438E LK", deposito: "terminado", delta: 44, tipo: "inicial", ts: ts },
      { cod_art: "438E CH", deposito: "terminado", delta: 18, tipo: "inicial", ts: ts },
      { cod_art: "439E LK", deposito: "terminado", delta: 29, tipo: "inicial", ts: ts },
      { cod_art: "437E",    deposito: "terminado", delta: 36, tipo: "inicial", ts: ts },   // base CON stock propio
      { cod_art: "437E LK", deposito: "terminado", delta: 100, tipo: "inicial", ts: ts }
    ];
    // demanda sobre los códigos BASE (así entran a la tabla como fila con 0 stock)
    _stk = { movs: movs, viewRows: viewRowsDeMovs(movs), cutoff: 0, dem: { "438E": 37, "439E": 28, "437E": 22 }, cap: [], fcs: {}, gConf: [], filtro: "", openArt: null, soloNeg: false };
    const html = stkBodyStocks();

    /* v10.02 — la celda del código ya NO lleva el sufijo: muestra el código canónico
       (codBase + ceros a la izquierda) y la empresa se fue a su propia columna "Línea".
       Así que la fila se identifica por su `data-stk-cod`, que sí conserva el código
       completo ("438E LK"). Antes esto se buscaba como 'stk-cod">438E LK<'. */
    const veFila = function (cod) { return html.indexOf('data-stk-cod="' + cod + '"') >= 0; };
    out.veLK438 = veFila("438E LK");
    out.veCH438 = veFila("438E CH");
    out.veLK439 = veFila("439E LK");
    out.ocultaBase438 = !veFila("438E");   // base sin sufijo → oculto
    out.ocultaBase439 = !veFila("439E");
    out.ve437base = veFila("437E");        // base CON stock propio → se ve
    out.veLK437 = veFila("437E LK");
    return out;
  });
  const pass = r.veLK438 && r.veCH438 && r.veLK439 && r.ocultaBase438 && r.ocultaBase439 &&
    r.ve437base && r.veLK437 && errs.length === 0;
  console.log("stk-base-split-oculta:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
