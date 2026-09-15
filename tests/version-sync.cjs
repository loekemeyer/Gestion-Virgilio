/* APP_VERSION (index.html), SW_VERSION (sw.js) y version.json deben tener la MISMA base.
   Evita la regresión PWA clásica: si al bumpear se olvidan de uno, el service
   worker sigue sirviendo la app vieja y "no se ve el cambio" en producción —
   un bug difícil de diagnosticar. Sale con código 1 si están desincronizados.

   ⚠ v18.28 — `version.json` entró acá porque es el que dispara el aviso "🔄 Actualizar"
   (checkForUpdate, v11.97): la app lo pide fresco cada 5 min y saca el banner sólo si es
   MÁS NUEVO que el APP_VERSION cargado. Nadie lo movía desde la v12.77, así que con la app
   en v18.27 el aviso no salía nunca y todo el mundo se quedaba con la versión vieja hasta
   que alguien le decía "hacé Ctrl+F5". Si este test se pone en rojo, eso es lo que vuelve. */
const fs = require("fs");
const path = require("path");
const root = path.join(__dirname, "..");
const html = fs.readFileSync(path.join(root, "index.html"), "utf8");
const sw = fs.readFileSync(path.join(root, "sw.js"), "utf8");
let vjson = null;
try { vjson = JSON.parse(fs.readFileSync(path.join(root, "version.json"), "utf8")); } catch (_e) {}

const mApp = html.match(/APP_VERSION\s*=\s*["']([^"']+)["']/);
const mSw = sw.match(/SW_VERSION\s*=\s*["']([^"']+)["']/);

if (!mApp) { console.log("version-sync: no encontré APP_VERSION en index.html"); process.exit(1); }
if (!mSw)  { console.log("version-sync: no encontré SW_VERSION en sw.js"); process.exit(1); }

const app = mApp[1].trim();
const swv = mSw[1].trim();
const swBase = swv.replace(/-.*$/, ""); // saca el sufijo "-vir" (u otro) del SW_VERSION

if (app !== swBase) {
  console.log("version-sync: DESYNC — APP_VERSION=" + app + " vs SW_VERSION=" + swv + " (base " + swBase + ")");
  console.log("  Al bumpear la versión hay que tocar LOS DOS (index.html y sw.js); si no, el SW cachea la app vieja.");
  process.exit(1);
}
if (!vjson || !vjson.version) {
  console.log("version-sync: version.json no existe o no tiene el campo `version`");
  process.exit(1);
}
const vj = String(vjson.version).trim();
if (app !== vj) {
  console.log("version-sync: DESYNC — APP_VERSION=" + app + " vs version.json=" + vj);
  console.log("  version.json es el que dispara el aviso 'Actualizar' de la app: si queda atrás,");
  console.log("  el banner NO sale nunca y los celulares se quedan con la versión vieja.");
  console.log("  Bumpeá con `node scripts/bump-version.cjs <ver>`, que mueve los cuatro lugares.");
  process.exit(1);
}
console.log("version-sync: OK — APP_VERSION=" + app + " == SW_VERSION base (" + swv + ") == version.json (" + vj + ")");
process.exit(0);
