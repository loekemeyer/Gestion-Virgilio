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
  { cod_art: "66", clave: "66", empresa: "Mixto", terminado: 7 }
];

const ch = gondAcumPorCod(SALDOS, "CH", norm);
const lk = gondAcumPorCod(SALDOS, "LK", norm);
const sin = gondAcumPorCod(SALDOS, null, norm);

// el umbral del aviso: (gondola + cajas) > capacidad * 1,20. Capacidad del 809E = 388 → 465,6
const avisa = (g, cajas, cap) => (g + cajas) > cap * 1.20;

const checks = [
  ["dual + linea CH → 120 (la gondola de Chef), no 148",              ch["809E"] === 120],
  ["dual + linea LK → 28 (la gondola de Loeke)",                      lk["809E"] === 28],
  ["dual sin linea → 0 (no se adivina de que empresa es)",            sin["809E"] === 0],
  ["comun → suma TODAS las filas (2719), con o sin linea",            ch["505"] === 2719 && lk["505"] === 2719 && sin["505"] === 2719],
  ["codigo con cero adelante: se normaliza y no se pierde",           ch["66"] === 7],
  ["400 cajas de 809E por CH → AVISA exceso (120+400 > 465,6)",       avisa(ch["809E"], 400, 388) === true],
  ["las mismas 400 por LK → NO avisa (28+400 < 465,6)",               avisa(lk["809E"], 400, 388) === false],
  ["y sin el fix (gondola 0) NO avisaba: ese era el bug",              avisa(0, 400, 388) === false],
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
if (bad) console.log("  detalle:", JSON.stringify({ ch: ch, lk: lk, sin: sin }));
console.log(bad ? "gond-exceso-dual: " + bad + " FALLA(S)" : "gond-exceso-dual: OK (" + checks.length + " chequeos)");
process.exit(bad ? 1 : 0);
