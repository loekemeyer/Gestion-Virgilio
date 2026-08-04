/* Regresión v7.05 — getActivityStatus() IGNORA legajo 0/1 (pruebas). Un EP de prueba
   (legajo 0) NO debe dejar una tanda "iniciada / en curso" en el monitor.

   Caso real: D05B tenía un solo evento, un EP con legajo 0 (03-08), y el tablero la
   mostraba "en picking hace 17 h" (fantasma). Chequea:
   - D05B (solo EP legajo 0): NO está en pickingStarted ni en pickingEnCursoBy.
   - REAL (EP legajo 122): SÍ está en pickingStarted y en pickingEnCursoBy = "122".
   - TEST1 (AP legajo 1): NO está en armadoStarted.
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
    window.fetch = function (url) {
      url = String(url);
      if (url.indexOf("opcion=in.(EP,TP,AP,TAP)") >= 0) {
        return J([
          { opcion: "EP", texto: "D05B",  ts_cliente: "2026-08-03T18:59:00Z", legajo: "0" },   // PRUEBA → NO
          { opcion: "EP", texto: "REAL",  ts_cliente: "2026-08-04T12:00:00Z", legajo: "122" }, // real → SÍ
          { opcion: "AP", texto: "TEST1", ts_cliente: "2026-08-04T12:00:00Z", legajo: "1" }    // PRUEBA → NO
        ]);
      }
      return J([]);
    };
    const s = await getActivityStatus(true);
    return {
      d05bStarted:  s.pickingStarted.has("D05B"),
      d05bEnCurso:  s.pickingEnCursoBy.has("D05B"),
      realStarted:  s.pickingStarted.has("REAL"),
      realEnCurso:  s.pickingEnCursoBy.get("REAL"),
      test1Started: s.armadoStarted.has("TEST1")
    };
  });
  const pass = r.d05bStarted === false && r.d05bEnCurso === false &&
    r.realStarted === true && r.realEnCurso === "122" && r.test1Started === false && errs.length === 0;
  console.log("act-legajo0:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
