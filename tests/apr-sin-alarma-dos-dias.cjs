/* v23.58 (Luis, 28/09) — "mismo cliente, mismo día" está DEROGADA (v21.87): la alarma
   «cliente con entregas en días distintos» NO se carga ni se dibuja en A Programar.
   Candado estático sobre el código (sin comentarios). Sale 1 si vuelve la puerta. */
const fs = require("fs"), path = require("path");
const src = fs.readFileSync(path.join(__dirname, "..", "index.html"), "latin1")
  .split("\n").map((l) => l.replace(/^\s*\/\/.*$/, "")).join("\n");
const fallos = [];
if (/h\s*\+=\s*aprDosDiasHtml\(\)/.test(src)) fallos.push("A Programar vuelve a dibujar aprDosDiasHtml()");
if (/[^.\w]aprDosDiasCargar\(\)\s*;/.test(src.replace(/async function aprDosDiasCargar\(\)/, ""))) fallos.push("A Programar vuelve a llamar aprDosDiasCargar()");
if (fallos.length) { console.error("FALLA:\n - " + fallos.join("\n - ")); process.exit(1); }
console.log("OK: la alarma de cliente en dos días no tiene puerta");
