/* Regresión idea 9799 — abastCompute (Abastecimiento vs Venta).
   ⚠ El módulo Abastecimiento del supervisor ya NO usa esta función (v10.10 lo movió a
   `vista_abastecimiento`, server-side), pero abastCompute SIGUE VIVA: la usa el módulo de
   Compras/OCs (`_oc.abast`, index.html ~10648) para el contexto de cada artículo. Por eso
   se testea el contrato de cálculo, que es puro.

   Cubre: agrupación por código+mes de recepciones y ventas · promedio de 3 meses que
   promedia SOLO sobre los meses CON dato (n = meses presentes, no 3 fijo) · balance último
   y balance promedio (recepción − venta) · proveedores del último mes ordenados por cajas
   desc · nProv = proveedores DISTINTOS activos en los 3 meses · exclusión de importados
   (código con "E") contándolos en nImport · saldos y depósitos de `sp` · `falta` =
   max(0, pedidos − stock) SOLO si hay pedidos (un stock negativo sin demanda no es
   necesidad) · meses fuera de la ventana de 3 no entran al promedio.
   Los meses se derivan con los mismos helpers (_abastMonthsInfo/_mesAdd) para no depender
   de la fecha de corrida. Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const out = {};
    const M0 = _abastMonthsInfo().ultimo;          // último mes COMPLETO
    const M1 = _mesAdd(M0, -1), M2 = _mesAdd(M0, -2), M3 = _mesAdd(M0, -3);   // M3 queda FUERA de la ventana

    const recep = [
      // 100: recibe en los 3 meses (30/20/10) → avg 20; último 30
      { cod: "100", mes: M0, cajas: 20, proveedor: "Lucho" },
      { cod: "100", mes: M0, cajas: 10, proveedor: "Garcia" },   // mismo mes, 2 proveedores → suma 30
      { cod: "100", mes: M1, cajas: 20, proveedor: "Lucho" },
      { cod: "100", mes: M2, cajas: 10, proveedor: "Rafael" },
      { cod: "100", mes: M3, cajas: 999, proveedor: "Viejo" },   // fuera de la ventana de 3
      // 200: recibe SOLO en el último mes → avg = 12/1 = 12 (no 12/3)
      { cod: "200", mes: M0, cajas: 12, proveedor: "Lucho" },
      // 300E: importado → excluido de rows, contado en nImport
      { cod: "300E", mes: M0, cajas: 50, proveedor: "China" }
    ];
    const venta = [
      { cod: "100", mes: M0, cajas: 40 },
      { cod: "100", mes: M1, cajas: 20 },
      { cod: "100", mes: M2, cajas: 30 },
      { cod: "200", mes: M0, cajas: 5 }
    ];
    const sp = [
      { cod: "100", stock_total: 15, pedidos_ped: 40, nps_ped: 3, terminado: 10, excedente: 5, racks: 0 },
      { cod: "200", stock_total: 8,  pedidos_ped: 0,  nps_ped: 0 },     // sin pedidos → falta 0
      { cod: "400", stock_total: -7, pedidos_ped: 0,  nps_ped: 0 }      // negativo SIN demanda → falta 0 (inconsistencia, no necesidad)
    ];

    const res = abastCompute(recep, venta, sp);
    const by = {}; res.rows.forEach(function (x) { by[x.cod] = x; });

    // ---- ventana de meses ----
    out.ventana = res.ultimo === M0 && res.tres.join(",") === [M0, M1, M2].join(",");

    // ---- 100: sumas por mes, promedios y balances ----
    out.recUlt = by["100"].recUlt === 30;                       // 20 + 10 del mismo mes
    out.venUlt = by["100"].venUlt === 40;
    out.recAvg = Math.abs(by["100"].recAvg - 20) < 1e-9;        // (30+20+10)/3, M3 NO entra
    out.venAvg = Math.abs(by["100"].venAvg - 30) < 1e-9;        // (40+20+30)/3
    out.balUlt = by["100"].balUlt === -10;                      // 30 − 40
    out.balAvg = Math.abs(by["100"].balAvg - (-10)) < 1e-9;     // 20 − 30

    // ---- promedio sobre meses CON dato (no dividir siempre por 3) ----
    out.avgSoloMesesConDato = Math.abs(by["200"].recAvg - 12) < 1e-9 && by["200"].recUlt === 12;

    // ---- proveedores del último mes: ordenados por cajas desc; nProv = distintos en 3 meses ----
    out.provsOrden = by["100"].provs.length === 2 && by["100"].provs[0].nombre === "Lucho" &&
      by["100"].provs[0].cajas === 20 && by["100"].provs[1].nombre === "Garcia";
    out.nProv = by["100"].nProv === 3;                          // Lucho, Garcia, Rafael (Viejo es de M3)

    // ---- importados fuera de rows, contados aparte ----
    out.importadoExcluido = !by["300E"] && res.nImport === 1;

    // ---- saldos/depósitos y "falta" ----
    out.stockPedidos = by["100"].stock === 15 && by["100"].pedidos === 40 && by["100"].npsPed === 3 && by["100"].tieneSp === true;
    out.deps = by["100"].dep.terminado === 10 && by["100"].dep.excedente === 5 && by["100"].dep.racks === 0;
    out.falta = by["100"].falta === 25;                         // 40 pedidos − 15 stock
    out.faltaSinPedidos = by["200"].falta === 0;
    out.negativoSinDemanda = by["400"].falta === 0 && by["400"].stock === -7;

    return out;
  });
  const keys = Object.keys(r); const bad = keys.filter(function (k) { return r[k] !== true; });
  const pass = bad.length === 0 && errs.length === 0;
  console.log("abast-compute:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL " + bad.join(","));
  await b.close(); process.exit(pass ? 0 : 1);
})();
