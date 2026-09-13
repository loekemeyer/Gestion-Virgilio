/* Regresión v16.30 (tramo 4 de docs/PLAN-SACAR-SUFIJO-EMPRESA.md) — el aviso de "no devolver
   a góndola" de la Recepción mira la góndola de LA EMPRESA de la recepción.

   El 809E son DOS productos: en la góndola de Loeke (J13-J14) es un Corta Pizza y en la de
   Chef (M13-M15) un Corta Queso. `vista_saldos_stock` devuelve una fila por empresa, así que
   sumarlas no significa nada. Hasta la v16.29 el filtro iba por `clave` contra códigos
   PELADOS: para un dual no matcheaba ninguna fila, la góndola daba 0 y el aviso NUNCA saltaba.

   `recepcion.js` es `type="module"` y NO carga por file://, así que no se puede levantar en
   Playwright. Por eso la lógica se extrajo a `gondAcumPorCod`, que es pura: este test la
   aísla del fuente y la corre en Node de verdad (no es un test de regex sobre el código).
   Sale 1 si falla. */
const fs = require("fs");
const path = require("path");

const src = fs.readFileSync(path.join(__dirname, "..", "recepcion.js"), "utf8");
const idx = src.indexOf("function gondAcumPorCod(");
if (idx < 0) { console.log("  FALLA · no existe gondAcumPorCod en recepcion.js"); console.log("gond-exceso-dual: 1 FALLA(S)"); process.exit(1); }
// recorta desde la firma hasta su llave de cierre, contando llaves
let depth = 0, end = -1;
for (let i = src.indexOf("{", idx); i < src.length; i++) {
  if (src[i] === "{") depth++;
  else if (src[i] === "}") { depth--; if (depth === 0) { end = i + 1; break; } }
}
const cuerpo = src.slice(idx, end);
const gondAcumPorCod = new Function(cuerpo + "; return gondAcumPorCod;")();

// v16.51 — las otras dos funciones puras, aisladas igual que la de arriba
function aislar(nombre) {
  const i = src.indexOf("function " + nombre + "(");
  if (i < 0) { console.log("  FALLA \u00b7 no existe " + nombre + " en recepcion.js"); console.log("gond-exceso-dual: 1 FALLA(S)"); process.exit(1); }
  let d = 0, e = -1;
  for (let j = src.indexOf("{", i); j < src.length; j++) {
    if (src[j] === "{") d++;
    else if (src[j] === "}") { d--; if (d === 0) { e = j + 1; break; } }
  }
  return new Function(src.slice(i, e) + "; return " + nombre + ";")();
}
const gondDualesDe = aislar("gondDualesDe");
const gondCapPorCod = aislar("gondCapPorCod");

// normalizador equivalente al _ocgNorm de la app (mayúsculas + sin ceros a la izquierda)
const norm = (c) => String(c == null ? "" : c).trim().toUpperCase().replace(/^0+(?=.)/, "");

const SALDOS = [
  // DUAL: la vista lo delata porque clave !== cod_art
  { cod_art: "809E", clave: "809E CH", empresa: "CH",    terminado: 120 },
  { cod_art: "809E", clave: "809E LK", empresa: "LK",    terminado: 28 },
  { cod_art: "809E", clave: "809E",    empresa: "Mixto", terminado: 0 },
  // COMÚN: clave === cod_art, tres filas que SE SUMAN → 2000 + 700 + 19 = 2719
  { cod_art: "505", clave: "505", empresa: "Mixto", terminado: 2000 },
  { cod_art: "505", clave: "505", empresa: "LK",    terminado: 700 },
  { cod_art: "505", clave: "505", empresa: "CH",    terminado: 19 },
  // con cero adelante: la clave de la vista es la grafía CRUDA ("66"), el código normaliza igual
  { cod_art: "66", clave: "66", empresa: "Mixto", terminado: 7 },
  // otro dual, para el caso "LOKE" de la capacidad
  { cod_art: "439E", clave: "439E LK", empresa: "LK", terminado: 16 },
  { cod_art: "439E", clave: "439E CH", empresa: "CH", terminado: 16 }
];

// Capacidad real de Capacidad_Sector al 13/09: el 809E tiene 100 cajas en la gondola de Loeke
// (J13-J14) y 288 en la de Chef (M13-M15); el 505, 3340 repartidas en celdas de una sola empresa.
const CAPS = [
  { cod: "809E", cajas_max: 60,  empresa: "LK" },
  { cod: "809E", cajas_max: 40,  empresa: "LK" },
  { cod: "809E", cajas_max: 96,  empresa: "CH" },
  { cod: "809E", cajas_max: 96,  empresa: "CH" },
  { cod: "809E", cajas_max: 96,  empresa: "CH" },
  { cod: "505",  cajas_max: 3000, empresa: "LK" },
  { cod: "505",  cajas_max: 340,  empresa: "LK" },
  // el 439E esta cargado como "LOKE" en Ñ53-Ñ54: cuenta como LK
  { cod: "439E", cajas_max: 30, empresa: "LK" },
  { cod: "439E", cajas_max: 36, empresa: "LOKE" }
];

const ch = gondAcumPorCod(SALDOS, "CH", norm);
const lk = gondAcumPorCod(SALDOS, "LK", norm);
const sin = gondAcumPorCod(SALDOS, null, norm);

const duales = gondDualesDe(SALDOS, norm);
const capLk = gondCapPorCod(CAPS, duales, "LK", norm);
const capCh = gondCapPorCod(CAPS, duales, "CH", norm);
const capSin = gondCapPorCod(CAPS, duales, null, norm);

// el umbral del aviso: (gondola + cajas) > capacidad * 1,20. Capacidad del 809E = 388 → 465,6
const avisa = (g, cajas, cap) => (g + cajas) > cap * 1.20;

const checks = [
  ["dual + linea CH → 120 (la gondola de Chef), no 148",              ch["809E"] === 120],
  ["dual + linea LK → 28 (la gondola de Loeke)",                      lk["809E"] === 28],
  ["dual sin linea → 0 (no se adivina de que empresa es)",            sin["809E"] === 0],
  ["comun → suma TODAS las filas (2719), con o sin linea",            ch["505"] === 2719 && lk["505"] === 2719 && sin["505"] === 2719],
  ["codigo con cero adelante: se normaliza y no se pierde",           ch["66"] === 7],
  ["y sin el fix de la v16.30 (gondola 0) NO avisaba: ese era el bug", avisa(0, 400, 388) === false],
  // ---- v16.51: la CAPACIDAD tambien es la de SU gondola, no la suma de las dos ----
  ["cap dual por LK → 100 (J13-J14), no 388",                         capLk["809E"] === 100],
  ["cap dual por CH → 288 (M13-M15), no 388",                         capCh["809E"] === 288],
  ["cap sin linea → 0 (no se adivina de que gondola es)",             (capSin["809E"] || 0) === 0],
  ["cap de un comun → suma todas, igual con LK que con CH (3340)",    capLk["505"] === 3340 && capCh["505"] === 3340 && capSin["505"] === 3340],
  ["LOKE cuenta como LK: el 439E da 66 por LK y 0 por CH",            capLk["439E"] === 66 && (capCh["439E"] || 0) === 0],
  ["400 de 809E por CH → AVISA (120+400 > 288×1,20 = 345,6)",         avisa(ch["809E"], 400, capCh["809E"]) === true],
  ["400 de 809E por LK → AVISA (28+400 > 100×1,20 = 120)",            avisa(lk["809E"], 400, capLk["809E"]) === true],
  ["y con la capacidad SUMADA (388) por LK NO avisaba: ese es el bug de la v16.50",
    avisa(lk["809E"], 400, 388) === false],
  ["el fetch de capacidad trae la empresa",
    /Capacidad_Sector"\)\.select\("cod,cajas_max,empresa"\)/.test(src)],
  ["la consulta trae cod_art, clave y empresa",
    /vista_saldos_stock"\)\.select\("cod_art,clave,empresa,terminado"\)/.test(src)],
  ["y filtra por cod_art (pelado), no por clave",
    /\.in\("cod_art", cods\)/.test(src) && !/\.in\("clave", cods\)/.test(src)],
  ["la linea sale de opState.linea", /gondAcumPorCod\([\s\S]{0,80}opState\.linea/.test(src)],
  ["el ?v= de recepcion.js acompana la version del index",
    (function () {
      const h = fs.readFileSync(path.join(__dirname, "..", "index.html"), "utf8");
      const v = (h.match(/const APP_VERSION = "v([0-9.]+)"/) || [])[1];
      return !!v && h.indexOf("recepcion.js?v=" + v) >= 0;
    })()]
];

let bad = 0;
for (const [n, ok] of checks) { console.log((ok ? "  ok   " : "  FALLA") + " · " + n); if (!ok) bad++; }
if (bad) console.log("  detalle:", JSON.stringify({ ch: ch, lk: lk, sin: sin, capLk: capLk, capCh: capCh, capSin: capSin }));
console.log(bad ? "gond-exceso-dual: " + bad + " FALLA(S)" : "gond-exceso-dual: OK (" + checks.length + " chequeos)");
process.exit(bad ? 1 : 0);
