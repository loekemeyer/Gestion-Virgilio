/* Regresión v7.48 — tilde "🔴 Negativos" en la solapa Stocks. Al activarlo, la tabla deja SÓLO
   los artículos con saldo negativo en algún depósito. Chequea:
   - Apagado: se ven el negativo (700, góndola -5) y el positivo (800, góndola +10); el botón
     muestra el contador (1) y el estado ☐.
   - Encendido: se ve 700 pero NO 800; el botón queda ☑.
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
    const movs = [
      { cod_art: "700", deposito: "terminado", delta: -5, tipo: "ajuste",  ts: "2026-08-01T10:00:00Z" }, // negativo
      { cod_art: "800", deposito: "terminado", delta: 10, tipo: "inicial", ts: "2026-08-01T10:00:00Z" }  // positivo
    ];
    _stk = { movs: movs, viewRows: viewRowsDeMovs(movs), cutoff: 0, dem: {}, cap: [], fcs: {}, gConf: [], filtro: "", openArt: null, soloNeg: false };

    // ---- APAGADO: se ven los dos + botón con contador ----
    const off = stkBodyStocks();
    out.off_ve700 = off.indexOf('stk-cod">700') >= 0;
    out.off_ve800 = off.indexOf('stk-cod">800') >= 0;
    out.off_botonOff = off.indexOf("☐ 🔴 Negativos") >= 0;
    out.off_contador = off.indexOf("🔴 Negativos (1)") >= 0;

    // ---- ENCENDIDO: sólo el negativo ----
    _stk.soloNeg = true;
    const on = stkBodyStocks();
    out.on_ve700 = on.indexOf('stk-cod">700') >= 0;
    out.on_oculta800 = on.indexOf('stk-cod">800') < 0;
    out.on_botonOn = on.indexOf("☑ 🔴 Negativos") >= 0;
    return out;
  });
  const pass = r.off_ve700 && r.off_ve800 && r.off_botonOff && r.off_contador &&
    r.on_ve700 && r.on_oculta800 && r.on_botonOn && errs.length === 0;
  console.log("stk-solo-negativos:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
