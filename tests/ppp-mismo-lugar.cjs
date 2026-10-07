// v28.34 (Luis, D6): aviso "mismo cliente + misma dirección en días distintos" en Programación y Resumen.
// Extrae las funciones de index.html y las corre con datos de prueba.
const fs = require("fs");
const src = fs.readFileSync(__dirname + "/../index.html", "latin1");
const ini = src.indexOf("const PPP_MLUG_TTL_MS");
const fin = src.indexOf("function pppResumenHtml(prog) {");
let fallas = 0;
function ok(c, m) { if (!c) { fallas++; console.error("✗ " + m); } else console.log("✓ " + m); }
ok(ini > 0 && fin > ini, "bloque del aviso antes de pppResumenHtml");
const bloque = Buffer.from(src.slice(ini, fin), "latin1").toString("utf8");
const escapeHtml = (s) => String(s == null ? "" : s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/"/g, "&quot;");
const _pppNpKey = (np) => String(np || "").toUpperCase().replace(/\s+/g, " ").trim();
const ctx = new Function("escapeHtml", "_pppNpKey", "SUPABASE_URL", "SUPABASE_KEY", "fetch",
  bloque + "; return { set: (r, e) => { _pppMLug = r; _pppMLugErr = !!e; }, nota: _pppMismoLugarNota, chip: _pppMismoLugarChip };")
  (escapeHtml, _pppNpKey, "x", "y", () => new Promise(() => {}));
ctx.set([
  { empresa: "lk", cod: "2316", razon_social: "Cliente X", dir_key: "k1", direccion: "Calle 1", barrio: "B", np: "LK 0358", tanda: "F48G", dia: "2026-10-15" },
  { empresa: "lk", cod: "2316", razon_social: "Cliente X", dir_key: "k1", direccion: "Calle 1", barrio: "B", np: "LK 0357", tanda: "F48H", dia: "2026-10-16" }
]);
const n = ctx.nota();
ok(/mismo lugar en días distintos/.test(n) && /LK 0358 15\/10 F48G/.test(n) && /LK 0357 16\/10/.test(n), "la nota lista las dos NP con día y tanda");
ok(/mismo lugar otro día/.test(ctx.chip("LK 0358")) && /LK 0357 16\/10/.test(ctx.chip("LK 0358")), "chip en la NP nombra la otra");
ok(ctx.chip("LK 9999") === "", "NP sin caso: sin chip");
ctx.set([]); ok(ctx.nota() === "", "sin casos: sin cartel");
ctx.set(null, true); ok(/No se pudo leer/.test(ctx.nota()), "lectura rota: lo dice, no calla");
ok(/pppMismoLugarNeed\(\); html \+= _pppMismoLugarNota\(\)/.test(src), "Programación dibuja el aviso");
ok(/head \+= _pppMismoLugarNota\(\)/.test(src), "Resumen dibuja el aviso");
ok(/_pppMismoLugarChip\(r\.np\)/.test(src), "chip en la fila de la NP");
process.exit(fallas ? 1 : 0);
