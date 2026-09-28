/* v22.96 — ninguna función de nivel superior se declara DOS veces en index.html.
   Por qué: en un <script> clásico la SEGUNDA declaración gana sin avisar. El 26/09 la cuenta corriente de
   Cobranzas (v22.93) declaró otra `ccRender` y pisó la de Carga Camión: al operario no se le dibujaba la lista
   para cargar el camión, sin un solo error en la consola. Este test lo caza estático, antes de pushear.
   Sólo mira declaraciones en la columna 0 (las helpers locales, indentadas, pueden repetirse). */
const fs = require("fs");
const path = require("path");
const html = fs.readFileSync(path.join(__dirname, "..", "index.html"), "utf8");
const vistos = {};
html.split("\n").forEach(function (ln, i) {
  const m = ln.match(/^(?:async\s+)?function\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*\(/);
  if (!m) return;
  (vistos[m[1]] = vistos[m[1]] || []).push(i + 1);
});
const dup = Object.keys(vistos).filter(function (k) { return vistos[k].length > 1; });
if (dup.length) {
  console.error("✗ fn-duplicadas: " + dup.map(function (k) { return k + " (líneas " + vistos[k].join(", ") + ")"; }).join(" · "));
  process.exit(1);
}
console.log("✓ fn-duplicadas: " + Object.keys(vistos).length + " funciones de nivel superior, ninguna repetida");
