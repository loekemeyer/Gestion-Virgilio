#!/usr/bin/env node
/* Mueve TODOS los tokens de versión de una sola vez.
 *
 * Uso:  node scripts/bump-version.cjs 16.70
 *       node scripts/bump-version.cjs --patch     (16.69 -> 16.70)
 *
 * POR QUÉ EXISTE: el bump de este repo es manual y son TRES lugares que tienen que
 * quedar en el mismo número — APP_VERSION (index.html), SW_VERSION (sw.js) y el ?v=
 * de recepcion.js (index.html). El 13/09 se desalinearon dos veces la misma noche
 * (v16.64 y v16.67) y main quedó en rojo las dos. Cuando pasa, el celular del
 * operario sigue corriendo el JS viejo cacheado y nadie se entera.
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

fs.writeFileSync(IDX, nuevoIdx, "latin1");
fs.writeFileSync(SW, nuevoSw, "latin1");

console.log("bump-version: v" + actual + " -> v" + nueva);
console.log("  index.html  APP_VERSION = v" + nueva);
console.log("  index.html  ?v= : " + tocados.join(", "));
console.log("  sw.js       SW_VERSION = v" + nueva + sufijo);

console.log("");
for (const t of ["version-sync.cjs", "version-tokens.cjs"]) {
  try {
    console.log(execFileSync("node", [path.join(root, "tests", t)], { encoding: "utf8" }).trim());
  } catch (e) {
    console.log((e.stdout || "").trim());
    salir("el test " + t + " falló después del bump — revisalo antes de commitear");
  }
}
