/* Los ?v= de los .js propios del index vs APP_VERSION.
 *
 * POR QUÉ EXISTE: el 13/09 main quedó en rojo DOS VECES la misma noche (v16.64 y
 * v16.67) porque se bumpeó APP_VERSION y se olvidaron el ?v= de recepcion.js. Cuando
 * eso pasa nadie se entera: el celular del operario sigue corriendo el JS viejo
 * cacheado y la app "no cambia".
 *
 * QUÉ VIGILA, y por qué no vigila todo:
 *   - SIGUEN_APP_VERSION: los .js que se versionan CON la app. TODAS sus apariciones
 *     en el index tienen que llevar el número de APP_VERSION — no sólo la primera.
 *   - VERSION_PROPIA: los que tienen numeración independiente a propósito. Exigirles
 *     APP_VERSION los marcaría en rojo el día uno, así que sólo se los lista.
 *   - Un .js propio con ?v= que no esté en ninguna de las dos listas FALLA: obliga a
 *     decidir a qué grupo pertenece en vez de que entre sin que nadie lo mire.
 *
 * Sale con código 1 si algo no cierra. */
const fs = require("fs");
const path = require("path");
const root = path.join(__dirname, "..");

// leído como latin1 para no romperse con el byte NUL que vive adentro del index
// (separador de claves de _pppGeoCod); los patrones que buscamos son ASCII.
const html = fs.readFileSync(path.join(root, "index.html"), "latin1");

const SIGUEN_APP_VERSION = ["recepcion.js"];
const VERSION_PROPIA = ["planimetria.js", "pasaje-papeles.js", "supabase-config.js"];

const mApp = html.match(/APP_VERSION\s*=\s*["']v?([0-9][0-9.]*)["']/);
if (!mApp) { console.log("version-tokens: no encontré APP_VERSION en index.html"); process.exit(1); }
const appNum = mApp[1];

// todos los src="algo.js?v=N" que NO son de un CDN
const encontrados = [];
const re = /src\s*=\s*["']([^"'?]+\.js)\?v=([^"']+)["']/g;
let m;
while ((m = re.exec(html)) !== null) {
  const src = m[1];
  if (/^https?:\/\//i.test(src) || src.startsWith("//")) continue;
  encontrados.push({ archivo: path.basename(src), token: m[2], idx: m.index });
}

const errores = [];

for (const nombre of SIGUEN_APP_VERSION) {
  const míos = encontrados.filter((e) => e.archivo === nombre);
  if (míos.length === 0) {
    errores.push(nombre + ": no aparece con ?v= en index.html (¿se borró el token de caché?)");
    continue;
  }
  for (const e of míos) {
    if (e.token !== appNum) {
      const linea = html.slice(0, e.idx).split("\n").length;
      errores.push(
        nombre + "?v=" + e.token + " (línea " + linea + ") quedó atrás de APP_VERSION=" + appNum +
        " — el celular sigue con el JS viejo cacheado"
      );
    }
  }
}

for (const e of encontrados) {
  if (SIGUEN_APP_VERSION.includes(e.archivo) || VERSION_PROPIA.includes(e.archivo)) continue;
  const linea = html.slice(0, e.idx).split("\n").length;
  errores.push(
    e.archivo + "?v=" + e.token + " (línea " + linea + ") no está en ninguna lista de este test. " +
    "Decidí en tests/version-tokens.cjs si se versiona con la app (SIGUEN_APP_VERSION) " +
    "o tiene numeración propia (VERSION_PROPIA)."
  );
}

if (errores.length) {
  console.log("version-tokens: FALLA");
  for (const e of errores) console.log("  - " + e);
  console.log("  Arreglo: node scripts/bump-version.cjs <version>  (mueve los tres tokens juntos)");
  process.exit(1);
}

const detalle = encontrados.map((e) => e.archivo + "?v=" + e.token).join(", ");
console.log("version-tokens: OK — APP_VERSION=" + appNum + "; " + encontrados.length + " tokens: " + detalle);
process.exit(0);
