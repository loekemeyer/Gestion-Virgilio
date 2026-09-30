// v24.75 (Thomas) — alerta ⛔ del artículo que QUIEBRA antes de que llegue la importación:
// stock real (sin lo en camino) < 4 meses y se termina antes de la fecha de llegada.
const fs = require("fs");
const src = fs.readFileSync(__dirname + "/../importacion.js", "utf8");
let ok = true; const fail = (m) => { ok = false; console.error("✗ " + m); };
const i0 = src.indexOf("function _pedImpQuiebre("), i1 = src.indexOf("function _pedImpQuiebreChip");
const ddmm = src.match(/function _pedImpDdmm\(f\) \{[^\n]*\}/)[0];
const Q = new Function("_PEDIMP_MESES_ALERTA", ddmm + "\n" + src.slice(i0, i1) + "; return _pedImpQuiebre;")(4);
const hoy = Date.parse("2026-10-01");
// 601E: stock 0, llega 15/11 → quiebra hoy
let q = Q({ proyUni: 600, stockUni: 0, enCurso: 3600, reingresoEst: "2026-11-15" }, hoy);
if (!q || q.llega !== "2026-11-15" || !(q.dias > 40)) fail("stock 0 con llegada 15/11 tiene que alertar: " + JSON.stringify(q));
// 2 meses de stock, llega en 1 mes → no quiebra
if (Q({ proyUni: 100, stockUni: 200, enCurso: 500, reingresoEst: "2026-11-01" }, hoy)) fail("llega antes de quebrar: no alerta");
// 2 meses, llega en 3 → alerta
if (!Q({ proyUni: 100, stockUni: 200, enCurso: 500, reingresoEst: "2027-01-01" }, hoy)) fail("quiebra antes de llegar: alerta");
// stock real 5 meses → no alerta aunque llegue tarde
if (Q({ proyUni: 100, stockUni: 500, enCurso: 500, reingresoEst: "2027-06-01" }, hoy)) fail("con 5 meses reales no alerta");
// nada en camino con 1 mes → alerta sinCamino
q = Q({ proyUni: 100, stockUni: 100, enCurso: 0 }, hoy);
if (!q || !q.sinCamino) fail("sin importación en camino y < 4 meses: alerta");
// sin proyección → null
if (Q({ proyUni: 0, stockUni: 0 }, hoy) !== null) fail("sin proyección no alerta");
if (!/<\/span>' \+ _pedImpQuiebreChip\(it\) \+ '<\/td>/.test(src)) fail("el chip tiene que ir en la celda de la descripción");
if (!/_pedImpQuiebreBadge\(arr\.filter/.test(src)) fail("falta el contador ⛔ en el proveedor");
if (ok) console.log("pedimp-quiebre · ✓ OK"); else process.exitCode = 1;
