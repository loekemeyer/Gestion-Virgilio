// v23.05 (problema 577): ninguna escritura VIVA de Stock_Config puede ir con la clave pública.
// Van por _scfgAuth() (JWT de la sesión de supervisor). La única que queda con la anon es
// stkGuardadoToggleRacks, que no tiene ningún llamador (código muerto).
const fs = require("fs");
const src = (fs.readFileSync(require("path").join(__dirname, "..", "index.html"), "latin1") + "\n" + fs.readFileSync(require("path").join(__dirname, "..", "importacion.js"), "latin1"));
const L = src.split("\n");
let fallas = 0, escrituras = 0;
for (let i = 0; i < L.length; i++) {
  if (!/rest\/v1\/Stock_Config\?(on_conflict|clave=eq)/.test(L[i])) continue;
  const bloque = L.slice(i, i + 4).join("\n");
  if (!/method:\s*"(POST|DELETE)"/.test(bloque)) continue;
  escrituras++;
  const fn = (L.slice(Math.max(0, i - 15), i).join("\n").match(/function\s+(\w+)\s*\(/g) || []).pop() || "?";
  if (/_scfgAuth\(\)/.test(bloque) || /stkGuardadoToggleRacks/.test(fn)) continue;
  console.log("FALLA línea " + (i + 1) + " (" + fn + "): escribe Stock_Config sin _scfgAuth()");
  fallas++;
}
if (!/async function _scfgAuth\(\)/.test(src)) { console.log("FALLA: falta _scfgAuth"); fallas++; }
if (escrituras < 9) { console.log("FALLA: se esperaban >= 9 escrituras, hay " + escrituras); fallas++; }
console.log(fallas ? "stock-config-supervisor: " + fallas + " falla(s)" : "stock-config-supervisor: OK — " + escrituras + " escrituras, todas con sesión");
process.exit(fallas ? 1 : 0);
