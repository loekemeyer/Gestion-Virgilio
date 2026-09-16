/* Regresión v18.80 (Luis, 2026-09-16) — Histórico de Recepción: fechas ordenadas y en UN formato.

   Por qué existe: `vista_historial_entregas.fecha` es TEXTO (las dos tablas de origen la guardan
   así) y convivían cuatro formatos — `2026-09-15`, `01/07/26`, `01-09` sin año, y una fila con
   `|||`. Eso rompía tres cosas juntas: la columna mezclaba `01/07/26` con `15/09`; el orden salía
   mal, porque comparar fechas como texto pone `0…` DESPUÉS de `2026-…`; y los filtros Desde/Hasta
   (`gte`/`lte` sobre ese texto) dejaban 121 filas afuera sin avisar.

   El arreglo de verdad está en el backend (`gv_fecha_recepcion_norm`, dentro de la vista). Acá se
   prueba la red de seguridad del front, que es la misma regla:
     - `histYmd` lleva los cuatro formatos a YYYY-MM-DD y devuelve "" para lo que no es fecha;
     - un `dd-mm` sin año que caería en el futuro es del año PASADO (un 28-12 leído en enero);
     - ordenando por ese valor las fechas quedan cronológicas (lo que el usuario reportó);
     - `histFechaTxt` muestra `dd/mm`, y `dd/mm/aa` en TODAS las filas si el resultado cruza de año.
   Sin navegador: se extrae el código de recepcion.js y se evalúa. Sale 1 si falla. */
const fs = require("fs"), path = require("path");

const src = fs.readFileSync(path.join(__dirname, "..", "recepcion.js"), "utf8");
function extraer(nombre) {
  const re = new RegExp("function " + nombre + "\\([\\s\\S]*?\\n\\}");
  const m = re.exec(src);
  if (!m) { console.error("FAIL rcp-hist-fecha: no encontré " + nombre + " en recepcion.js"); process.exit(1); }
  return m[0];
}
const histYmd = new Function(extraer("histYmd") + "; return histYmd;")();
const histFechaTxt = new Function(extraer("histFechaTxt") + "; return histFechaTxt;")();

const fail = [];
const eq = function (qué, dio, esperaba) {
  if (dio !== esperaba) fail.push(qué + ": dio " + JSON.stringify(dio) + ", esperaba " + JSON.stringify(esperaba));
};

// 1) los cuatro formatos que conviven en la base
eq("ymd tal cual", histYmd("2026-09-15"), "2026-09-15");
eq("timestamp", histYmd("2026-09-16T10:20:00Z"), "2026-09-16");
eq("dd/mm/aa", histYmd("01/07/26"), "2026-07-01");
eq("d/m/aa sin pad", histYmd("1/7/26"), "2026-07-01");
eq("dd/mm/aaaa", histYmd("01/07/2026"), "2026-07-01");
eq("dd-mm-aaaa", histYmd("01-07-2026"), "2026-07-01");
eq("basura", histYmd("|||"), "");
eq("vacío", histYmd(""), "");
eq("null", histYmd(null), "");

// 2) `dd-mm` sin año: el año en curso, salvo que caiga en el futuro
const hoy = new Date(), Y = hoy.getFullYear(), p2 = (x) => ("0" + x).slice(-2);
const ayer = new Date(hoy.getTime() - 86400000);
eq("dd-mm de ayer → año en curso",
   histYmd(p2(ayer.getDate()) + "-" + p2(ayer.getMonth() + 1)),
   ayer.getFullYear() + "-" + p2(ayer.getMonth() + 1) + "-" + p2(ayer.getDate()));
const lejos = new Date(hoy.getTime() + 60 * 86400000);   // +60 días: no puede ser una recepción
eq("dd-mm que caería en el futuro → año pasado",
   histYmd(p2(lejos.getDate()) + "-" + p2(lejos.getMonth() + 1)),
   (lejos.getFullYear() - 1) + "-" + p2(lejos.getMonth() + 1) + "-" + p2(lejos.getDate()));

// 3) el orden: es lo que reportó Luis. Con los formatos crudos el orden sale mal; con histYmd, bien.
const crudas = ["2026-09-15", "01/07/26", "2025-12-10", "31/07/26", "2026-08-25"];
const ordenBien = ["2026-09-15", "2026-08-25", "31/07/26", "01/07/26", "2025-12-10"];
const porYmd = crudas.slice().sort(function (a, b) {
  const A = histYmd(a), B = histYmd(b); return A === B ? 0 : (A < B ? 1 : -1);
});
eq("orden cronológico (más nueva primero)", porYmd.join(" "), ordenBien.join(" "));
const porTexto = crudas.slice().sort(function (a, b) { return a === b ? 0 : (a < b ? 1 : -1); });
if (porTexto.join(" ") === ordenBien.join(" ")) fail.push("el orden por texto crudo ya daba bien: el test no prueba nada");

// 4) la etiqueta: un solo formato por columna
eq("dd/mm dentro del mismo año", histFechaTxt("2026-09-15", false), "15/09");
eq("dd/mm/aa si cruza de año", histFechaTxt("2026-09-15", true), "15/09/26");
eq("dd/mm/aa del año anterior", histFechaTxt("2025-12-10", true), "10/12/25");
eq("sin fecha", histFechaTxt("", false), "—");
eq("fecha inválida", histFechaTxt("|||", true), "—");

if (fail.length) { console.error("FAIL rcp-hist-fecha:\n - " + fail.join("\n - ")); process.exit(1); }
console.log("OK rcp-hist-fecha — los 4 formatos a YYYY-MM-DD, orden cronológico y una sola forma de mostrar la fecha");
