/* Regresión v18.43 — la base de picking de los pedidos web SE PAGINA.
   `limit=20000` en la URL es ilusorio: PostgREST corta en 1000 filas (db-max-rows) y
   devuelve 200 sin avisar. PPP_Web_Base pasó las 1000 filas el 15/09 (1256) y el corte se
   comió las NP más nuevas — las que se están pickeando. El operario veía "No encontré
   artículos para la tanda" (E25A / LK 0097, E11C / LK 0092-0093) y terminaba arrancando
   otra tanda, dejando la primera abierta.
   Este test es de CÓDIGO (no necesita red): las dos consultas que alimentan el picking web
   tienen que ir por supaFetchAll (que pagina con Range) y con `order=` explícito, porque sin
   un orden estable las páginas repiten o saltean filas.
   Sale 1 si falla. */
const fs = require("fs");
const path = require("path");
const src = fs.readFileSync(path.join(__dirname, "..", "index.html"), "latin1");

function cuerpo(nombre) {
  const i = src.indexOf("async function " + nombre + "(");
  if (i < 0) return null;
  return src.slice(i, i + 1400);
}

const casos = [
  { fn: "mergePickingBasePppWeb", tabla: "PPP_Web_Base" },
  { fn: "mergeMonitorPppWeb",     tabla: "PPP_Web_Programacion" }
];

const fallas = [];
for (const c of casos) {
  const b = cuerpo(c.fn);
  if (!b) { fallas.push(c.fn + ": no existe"); continue; }
  if (!/supaFetchAll\s*\(/.test(b))            fallas.push(c.fn + ": no usa supaFetchAll (se corta en 1000 filas)");
  if (/await\s+fetch\s*\(/.test(b))            fallas.push(c.fn + ": quedó un fetch suelto");
  if (!/order=/.test(b))                        fallas.push(c.fn + ": pagina sin order= (las páginas pueden repetir/saltear)");
  if (new RegExp("/rest/v1/" + c.tabla).test(b) === false) fallas.push(c.fn + ": ya no consulta " + c.tabla);
}

if (fallas.length) {
  console.log("pweb-base-paginada: ✗ FAIL\n  - " + fallas.join("\n  - "));
  process.exit(1);
}
console.log("pweb-base-paginada: las 2 consultas del picking web paginan con order · ✓ OK");
