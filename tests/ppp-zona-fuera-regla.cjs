// v28.40 (Luis, 07/10): cartel de tanda con pedidos de zonas que no van en el mismo camión
// (gv_ppp_tanda_zona_fuera_regla) en Programación y Resumen. Corre la función con datos de prueba.
const fs = require("fs");
const src = fs.readFileSync(__dirname + "/../index.html", "latin1");
const ini = src.indexOf("let _pppZFR = null");
const fin = src.indexOf("function pppResumenHtml(prog) {");
let fallas = 0;
function ok(c, m) { if (!c) { fallas++; console.error("✗ " + m); } else console.log("✓ " + m); }
ok(ini > 0 && fin > ini, "bloque del cartel antes de pppResumenHtml");
const bloque = Buffer.from(src.slice(ini, fin), "latin1").toString("utf8");
const escapeHtml = (s) => String(s == null ? "" : s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/"/g, "&quot;");
const gvDiaTxt = (s) => String(s || "").slice(8, 10) + "/" + String(s || "").slice(5, 7);
const ctx = new Function("escapeHtml", "gvDiaTxt", "SUPABASE_URL", "SUPABASE_KEY", "fetch", "PPP_MLUG_TTL_MS",
  bloque + "; return { set: (r, e) => { _pppZFR = r; _pppZFRErr = !!e; }, nota: _pppZonaFueraNota };")
  (escapeHtml, gvDiaTxt, "x", "y", () => new Promise(() => {}), 60000);
ctx.set([{ fecha: "2026-10-09", tanda: "F48D", motivo: "camiones distintos", camiones: "Capital Sur + GBA Norte", zonas: "Zona 1 - CABA Sur + Zona 6 - GBA Norte", detalle: "LK 0341 Zona 6 - GBA Norte" }]);
const n = ctx.nota();
ok(/F48D/.test(n) && /09\/10/.test(n) && /Capital Sur \+ GBA Norte/.test(n) && /LK 0341/.test(n), "el cartel nombra tanda, día, camiones y NP");
ctx.set([]); ok(ctx.nota() === "", "sin casos: sin cartel");
ctx.set(null, true); ok(/No se pudo leer/.test(ctx.nota()), "lectura rota: lo dice, no calla");
ok(/pppZonaFueraNeed\(\); html \+= _pppZonaFueraNota\(\)/.test(src), "Programación dibuja el cartel");
ok(/head \+= _pppZonaFueraNota\(\)/.test(src), "Resumen dibuja el cartel");
process.exit(fallas ? 1 : 0);
