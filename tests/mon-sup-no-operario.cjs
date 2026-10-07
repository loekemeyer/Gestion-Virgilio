/* v27.80 (Luis, 07/10): el supervisor (legajo "sup:<mail>", el que firma desde el panel) NO figura
   como operario en ningún monitor. Caso: «Leg S. · libre 1:17» por 6 FSS de Recepción Remitos.
   Candado: en los monitores, todo filtro de legajo de prueba ("0") saca también los "sup:". */
const fs = require("fs");
let malos = [];
function revisar(path, soloFuncs) {
  const txt = fs.readFileSync(path, "latin1").split("\n");
  let fn = "";
  txt.forEach((l, i) => {
    const m = l.match(/^\s*(?:async )?function ([A-Za-z_]\w*)/); if (m) fn = m[1];
    if (soloFuncs && !soloFuncs.includes(fn)) return;
    if (/\b(leg|legStr) === "0"/.test(l) && !/\^sup:/.test(l)) malos.push(path + ":" + (i + 1) + " (" + fn + ")");
  });
}
revisar("monitor/tv.html");
revisar("monitor/admin.html");
revisar("index.html", ["showDayBreakdown", "fetchMonitorDayStats", "_monEnSilencio", "_monActividadActual", "fetchMonitorEvents"]);
if (malos.length) { console.error("FALLA: el supervisor entra como operario en:\n  " + malos.join("\n  ")); process.exit(1); }
console.log("OK — ningún monitor cuenta al supervisor (sup:) como operario");
