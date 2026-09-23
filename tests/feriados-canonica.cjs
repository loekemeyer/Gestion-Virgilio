/* v21.47 — LOS FERIADOS SALEN DE UNA SOLA TABLA.

   La lista estaba escrita TRES veces a mano (`FERIADOS_AR` en index.html, `FERIADOS` en
   monitor/tv.html y un CTE adentro de `gv_monitor_horas_operario_dia`) y las tres terminaban el
   2026-12-25: desde el 1.º de enero ninguna conocía un feriado. La canónica es la tabla
   `public."GV_Feriados"`.

   Candado ESTÁTICO, y va por los dos lados:
     · que cada front tenga su cargador y lo LLAME (un cargador que nadie invoca es código muerto —
       pasó con el fallback de la pestaña vieja del pipeline, v20.89);
     · que la lista hardcodeada SIGA estando: es el fallback, y borrarla deja al tablero sin ningún
       feriado el día que el fetch falle.

   El lado SQL no se puede probar desde acá (las sesiones no le pegan a Supabase): lo cubren
   `gv_reglas_perdidas` (patrón `GV_Feriados` sobre la función) y `gv_huellas_cambiadas`.

   Sale 1 si falla. */
const fs = require("fs");
const path = require("path");

const raiz = path.join(__dirname, "..");
const idx = fs.readFileSync(path.join(raiz, "index.html"), "utf8");
const tv  = fs.readFileSync(path.join(raiz, "monitor", "tv.html"), "utf8");

const mal = [];
const chk = (cond, msg) => { if (!cond) mal.push(msg); };

// ── index.html ──────────────────────────────────────────────────────────────
chk(/function ensureFeriadosAR\s*\(/.test(idx),
    "index.html: falta `ensureFeriadosAR` (el cargador de la canónica)");
chk(idx.indexOf('/rest/v1/GV_Feriados?select=fecha&tipo=eq.feriado') >= 0,
    "index.html: `ensureFeriadosAR` no pide GV_Feriados con tipo=eq.feriado (los puentes NO son feriado)");
/* ⚠ La llamada tiene que estar VIVA, no comentada: un regex pelado matchea igual adentro de un
   `// …` y el test da falso verde (pasó al escribirlo). Se mira línea por línea. */
chk(idx.split("\n").some(l => l.indexOf("await ensureFeriadosAR()") >= 0
                            && !/^\s*(\/\/|\*|\/\*)/.test(l)),
    "index.html: nadie LLAMA a `ensureFeriadosAR` (o quedó comentada) — el cargador estaría muerto");
chk(/const FERIADOS_AR = new Set\(\[/.test(idx),
    "index.html: se borró la lista `FERIADOS_AR`, que es el FALLBACK si el fetch falla");
chk(idx.indexOf("FERIADOS_AR.clear();") >= 0 && /if \(!Array\.isArray\(rows\) \|\| !rows\.length\) return false;/.test(idx),
    "index.html: `ensureFeriadosAR` tiene que salir ANTES del clear() si la respuesta vino vacía, o pisa el fallback con nada");

// ── monitor/tv.html ─────────────────────────────────────────────────────────
chk(/var cargarFeriados = cache\(/.test(tv),
    "tv.html: falta `cargarFeriados` (el cargador de la canónica)");
chk(tv.indexOf('get("GV_Feriados", "select=fecha&tipo=eq.feriado') >= 0,
    "tv.html: `cargarFeriados` no pide GV_Feriados con tipo=eq.feriado");
chk(/cargarHoras\(\),\s*cargarFeriados\(\)/.test(tv),
    "tv.html: `cargarFeriados()` no entró al Promise.all del ciclo — no se llamaría nunca");
chk(/var FERIADOS = \{ "2026-01-01":1/.test(tv),
    "tv.html: se borró la lista `FERIADOS`, que es el FALLBACK si el fetch falla");
chk(tv.indexOf("if (!filas || !filas.length) return FERIADOS;") >= 0,
    "tv.html: `cargarFeriados` pisa el fallback aunque la respuesta venga vacía");

// ── y que nadie haya vuelto a escribir una lista suelta ─────────────────────
const listasIdx = (idx.match(/new Set\(\[\s*"20\d\d-01-01"/g) || []).length;
chk(listasIdx <= 1, "index.html: hay más de una lista de feriados hardcodeada (" + listasIdx + ")");

if (mal.length) {
  console.log("feriados-canonica: FALLA");
  for (const m of mal) console.log("  - " + m);
  process.exit(1);
}
console.log("feriados-canonica: OK — los dos fronts bajan public.\"GV_Feriados\" y conservan su fallback");
