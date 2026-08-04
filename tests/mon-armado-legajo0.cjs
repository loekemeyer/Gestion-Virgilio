/* Regresión v7.36 — fetchMonitorEvents() (monitor del supervisor) IGNORA legajo 0/1
   (pruebas) al calcular quién empezó picking/armado. Un AP de prueba (legajo 0) NO debe
   hacer figurar una tanda "armada por 0".

   Caso real: D06C pickeada+armada... la pickeó legajo 122 (EP/TP) y después un AP fantasma
   de legajo 0 la mostraba "armado en curso por 0" en el monitor. Chequea:
   - D06C: separado = null y sepLegajo = null (el AP de legajo 0 se ignora); picking sigue
     "done" con pickLegajo = "122".
   - REAL (AP legajo 122): separado = "curso", sepLegajo = "122".
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
    function J(data) { return Promise.resolve({ ok: true, status: 200, headers: { get: function () { return null; } }, json: function () { return Promise.resolve(data); } }); }
    // dataB / dataC salen por supaFetchAll → los vaciamos; getHistoricMap → vacío.
    window.supaFetchAll = async function () { return []; };
    window.getHistoricMap = async function () { return new Map(); };
    window.fetch = function (url) {
      url = String(url);
      // Query A del monitor: opcion=in.(EP,TP,AP,TAP) + texto=in.(...)
      if (url.indexOf("opcion=in.(EP,TP,AP,TAP)") >= 0 && url.indexOf("texto=in.(") >= 0) {
        return J([
          { opcion: "EP", texto: "D06C", ts_cliente: "2026-08-04T15:03:00Z", legajo: "122" },
          { opcion: "TP", texto: "D06C", ts_cliente: "2026-08-04T16:01:00Z", legajo: "122" },
          { opcion: "AP", texto: "D06C", ts_cliente: "2026-08-04T16:50:00Z", legajo: "0" },   // PRUEBA → ignorar
          { opcion: "EP", texto: "REAL", ts_cliente: "2026-08-04T15:00:00Z", legajo: "122" },
          { opcion: "AP", texto: "REAL", ts_cliente: "2026-08-04T15:30:00Z", legajo: "122" }   // real → curso
        ]);
      }
      return J([]);   // fichadas (query D) y cualquier otra
    };
    const sheetMap = new Map([["D06C", { m3: 1 }], ["REAL", { m3: 1 }]]);
    const res = await fetchMonitorEvents(["D06C", "REAL"], sheetMap);
    const d06c = res.statusMap.get("D06C") || {};
    const real = res.statusMap.get("REAL") || {};
    return {
      d06cSeparado: d06c.separado,
      d06cSepLegajo: d06c.sepLegajo,
      d06cPicking: d06c.picking,
      d06cPickLegajo: d06c.pickLegajo,
      realSeparado: real.separado,
      realSepLegajo: real.sepLegajo
    };
  });
  const pass = r.d06cSeparado === null && (r.d06cSepLegajo === null || r.d06cSepLegajo === undefined) &&
    r.d06cPicking === "done" && r.d06cPickLegajo === "122" &&
    r.realSeparado === "curso" && r.realSepLegajo === "122" && errs.length === 0;
  console.log("mon-armado-legajo0:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
