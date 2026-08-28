/* Regresión v7.36 → v10.26 — el monitor del supervisor y el estado por tanda.

   El caso que originó el test: D06C la pickeó el legajo 122 (EP/TP) y después un AP
   fantasma de legajo 0 (pruebas) la mostraba "armado en curso por 0". El filtro de
   los legajos de prueba lo hacía fetchMonitorEvents en el navegador.

   ⚠ v10.26 — eso se fue al backend: la query A del monitor pasó a leer la vista
   `vista_tanda_status`, que ya resuelve por tanda el último EP/TP y AP/TAP con su
   legajo y su ts, y descarta los legajos de prueba con `es_legajo_test(legajo)`
   (verificado contra la base: es_legajo_test('0') y ('1') dan true, y la vista no
   devuelve ninguna fila con arm_legajo/pick_legajo 0 ó 1). El front solo mapea.

   Así que este test verifica el CONTRATO que quedó del lado del navegador:
   - last_pick_op/last_arm_op → picking/separado: TP y TAP son "done", EP y AP "curso",
     y sin evento queda null (no "pendiente", null),
   - legajo y ts de arranque se pasan tal cual a pickLegajo/sepLegajo/…StartTs,
   - una tanda que la vista NO devuelve (porque su único armado era de un legajo de
     prueba) queda sin armador: separado null y sepLegajo null.
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
      // Query A del monitor (v10.26): vista_tanda_status por tanda.
      if (url.indexOf("vista_tanda_status") >= 0) {
        return J([
          // D06C: pickeada y cerrada por 122. El AP de legajo 0 NO llega: la vista lo
          // descartó, así que la fila viene sin nada de armado.
          { tanda: "D06C", last_pick_op: "TP", pick_legajo: "122", pick_start_ts: "2026-08-04T15:03:00Z",
            last_arm_op: null, arm_legajo: null, arm_start_ts: null },
          // REAL: armado en curso por un legajo de verdad.
          { tanda: "REAL", last_pick_op: "TP", pick_legajo: "122", pick_start_ts: "2026-08-04T15:00:00Z",
            last_arm_op: "AP", arm_legajo: "122", arm_start_ts: "2026-08-04T15:30:00Z" },
          // CERR: armado terminado (TAP) → "done".
          { tanda: "CERR", last_pick_op: "TP", pick_legajo: "55", pick_start_ts: "2026-08-04T14:00:00Z",
            last_arm_op: "TAP", arm_legajo: "55", arm_start_ts: "2026-08-04T14:40:00Z" }
        ]);
      }
      return J([]);   // fichadas (query D) y cualquier otra
    };
    const sheetMap = new Map([["D06C", { m3: 1 }], ["REAL", { m3: 1 }], ["CERR", { m3: 1 }]]);
    const res = await fetchMonitorEvents(["D06C", "REAL", "CERR"], sheetMap);
    const d06c = res.statusMap.get("D06C") || {};
    const real = res.statusMap.get("REAL") || {};
    const cerr = res.statusMap.get("CERR") || {};
    return {
      d06cSeparado: d06c.separado,
      d06cSepLegajo: d06c.sepLegajo,
      d06cPicking: d06c.picking,
      d06cPickLegajo: d06c.pickLegajo,
      realSeparado: real.separado,
      realSepLegajo: real.sepLegajo,
      realSepStartTs: real.sepStartTs,
      cerrSeparado: cerr.separado
    };
  });
  const pass = r.d06cSeparado === null && (r.d06cSepLegajo === null || r.d06cSepLegajo === undefined) &&
    r.d06cPicking === "done" && r.d06cPickLegajo === "122" &&
    r.realSeparado === "curso" && r.realSepLegajo === "122" &&
    r.realSepStartTs === "2026-08-04T15:30:00Z" && r.cerrSeparado === "done" && errs.length === 0;
  console.log("mon-armado-legajo0:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
