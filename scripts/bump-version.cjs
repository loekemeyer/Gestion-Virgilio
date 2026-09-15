#!/usr/bin/env node
/* Mueve TODOS los tokens de versión de una sola vez.
 *
 * Uso:  node scripts/bump-version.cjs 16.70
 *       node scripts/bump-version.cjs --patch     (16.69 -> 16.70)
 *
 * POR QUÉ EXISTE: el bump de este repo es manual y son CUATRO lugares que tienen que
 * quedar en el mismo número — APP_VERSION (index.html), SW_VERSION (sw.js), el ?v=
 * de recepcion.js (index.html) y `version.json`. El 13/09 se desalinearon dos veces la
 * misma noche (v16.64 y v16.67) y main quedó en rojo las dos. Cuando pasa, el celular
 * del operario sigue corriendo el JS viejo cacheado y nadie se entera.
 *
 * ⚠ v18.28 — `version.json` se sumó acá porque es EL que dispara el aviso "🔄 Actualizar"
 * de la app (checkForUpdate, v11.97): el front lo pide fresco cada 5 min y compara contra
 * APP_VERSION. Nadie lo estaba moviendo, así que quedó clavado en v12.77 mientras la app
 * iba por v18.27: como el banner sólo sale si version.json es MÁS NUEVO, el aviso no salía
 * NUNCA desde hace cinco versiones mayores. De ahí que todos anduvieran pidiendo Ctrl+F5.
 *
 * OJO: index.html tiene un byte NUL adentro (separador de claves de _pppGeoCod), así
 * que se lee y se escribe en latin1 para que el archivo vuelva byte a byte igual
 * salvo lo que se cambia a propósito. NUNCA editarlo con una herramienta que trate
 * el archivo como texto "limpio": se come el NUL.
 *
 * Al terminar corre los dos tests de versión. */
const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");

const root = path.join(__dirname, "..");
const IDX = path.join(root, "index.html");
const SW = path.join(root, "sw.js");
const VJSON = path.join(root, "version.json");

// los ?v= del index que se versionan CON la app (tiene que coincidir con
// SIGUEN_APP_VERSION de tests/version-tokens.cjs)
const SIGUEN_APP_VERSION = ["recepcion.js"];

function salir(msg) { console.error("bump-version: " + msg); process.exit(1); }

let arg = process.argv[2];
if (!arg) salir("falta la versión.  Uso: node scripts/bump-version.cjs 16.70  |  --patch");

const idx = fs.readFileSync(IDX, "latin1");
const mApp = idx.match(/(APP_VERSION\s*=\s*["'])v?([0-9][0-9.]*)(["'])/);
if (!mApp) salir("no encontré APP_VERSION en index.html");
const actual = mApp[2];

let nueva;
if (arg === "--patch") {
  const p = actual.split(".");
  p[p.length - 1] = String(Number(p[p.length - 1]) + 1);
  nueva = p.join(".");
} else {
  nueva = arg.replace(/^v/, "");
}
if (!/^[0-9]+(\.[0-9]+)*$/.test(nueva)) salir('versión inválida: "' + arg + '" (esperaba algo como 16.70)');
if (nueva === actual) salir("la versión ya es " + actual + " — no hay nada que bumpear");

// ---- v18.67 — NUNCA para atrás respecto de main (problema 290) ----
// El 15/09 seis sesiones pusheaban a main en paralelo y tres commits dejaron la versión MÁS BAJA
// que la que main ya tenía (v18.35 → v18.30, v18.36 → v18.31): el aviso "Actualizar" sólo sale si
// version.json es MÁS NUEVO que el cargado, así que se apagó un rato. Acá se mira lo que main tiene
// de verdad (no la copia local, que puede estar vieja) y se corta si el número no lo supera.
// Si no hay red o no hay origin, avisa y sigue: no bloquea el trabajo offline.
const num = (v) => { const m = String(v || "").match(/^v?(\d+)\.(\d+)$/); return m ? +m[1] * 1000 + +m[2] : -1; };
try {
  execFileSync("git", ["fetch", "-q", "origin", "main"], { cwd: root, stdio: "ignore", timeout: 15000 });
  const remota = (JSON.parse(execFileSync("git", ["show", "origin/main:version.json"], { cwd: root, encoding: "utf8" })) || {}).version;
  if (remota && num(remota) >= num(nueva) && !process.env.BUMP_FORZAR) {
    salir("main YA está en " + remota + " y pediste v" + nueva + " — otra sesión se te adelantó. " +
          "Traé main (git merge origin/main) y bumpeá a un número mayor. (BUMP_FORZAR=1 para saltear)");
  }
  if (remota && num(remota) > num(actual)) {
    console.log("bump-version: ojo, tu copia local dice v" + actual + " pero main ya va por " + remota + " — mergeá main antes de commitear.");
  }
} catch (_e) {
  console.log("bump-version: no pude leer version.json de origin/main (sin red u origin) — no se chequea que no vaya para atrás.");
}

// ---- index.html: APP_VERSION + los ?v= que siguen a la app ----
let nuevoIdx = idx.replace(/(APP_VERSION\s*=\s*["'])v?([0-9][0-9.]*)(["'])/, "$1v" + nueva + "$3");
const tocados = [];
for (const archivo of SIGUEN_APP_VERSION) {
  const re = new RegExp("(" + archivo.replace(/\./g, "\\.") + "\\?v=)([^\"']+)", "g");
  let n = 0;
  nuevoIdx = nuevoIdx.replace(re, (_, pre) => { n++; return pre + nueva; });
  if (n === 0) salir(archivo + " no aparece con ?v= en index.html — revisalo a mano antes de seguir");
  tocados.push(archivo + " x" + n);
}

// ---- sw.js: SW_VERSION, conservando el sufijo (-vir) ----
const sw = fs.readFileSync(SW, "latin1");
const mSw = sw.match(/(SW_VERSION\s*=\s*["'])v?([0-9][0-9.]*)(-[^"']*)?(["'])/);
if (!mSw) salir("no encontré SW_VERSION en sw.js");
const sufijo = mSw[3] || "";
const nuevoSw = sw.replace(/(SW_VERSION\s*=\s*["'])v?([0-9][0-9.]*)(-[^"']*)?(["'])/,
  "$1v" + nueva + sufijo + "$4");

// ---- version.json: lo que dispara el aviso "🔄 Actualizar" en la app ya abierta ----
let vjAntes = "(no existía)";
try { vjAntes = (JSON.parse(fs.readFileSync(VJSON, "utf8")) || {}).version || "(sin campo)"; } catch (_e) {}

fs.writeFileSync(IDX, nuevoIdx, "latin1");
fs.writeFileSync(SW, nuevoSw, "latin1");
fs.writeFileSync(VJSON, '{ "version": "v' + nueva + '" }\n', "utf8");

console.log("bump-version: v" + actual + " -> v" + nueva);
console.log("  index.html   APP_VERSION = v" + nueva);
console.log("  index.html   ?v= : " + tocados.join(", "));
console.log("  sw.js        SW_VERSION = v" + nueva + sufijo);
console.log("  version.json " + vjAntes + " -> v" + nueva + "   (el aviso 'Actualizar' de la app)");

console.log("");
for (const t of ["version-sync.cjs", "version-tokens.cjs"]) {
  try {
    console.log(execFileSync("node", [path.join(root, "tests", t)], { encoding: "utf8" }).trim());
  } catch (e) {
    console.log((e.stdout || "").trim());
    salir("el test " + t + " falló después del bump — revisalo antes de commitear");
  }
}
