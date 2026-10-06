/* v27.12 (Luis, 06/10) — Comentarios por recepción en el módulo de Pendientes (recepcion.js).
   Candado ESTÁTICO: un hilo append-only en GV_Recepcion_Comentarios, botón redondo en cada
   tarjeta y el MISMO "quién escribe" que Recibido (chips de GV_Recepcion_Receptores). Sale 1
   si falla. No puede ser un test de pantalla: las funciones de recepcion.js son de módulo
   (no viven en window), así que se vigila el fuente. */
const fs = require("fs");
const path = require("path");
const src = fs.readFileSync(path.join(__dirname, "..", "recepcion.js"), "utf8");

const checks = [
  ["el botón redondo se agrega al encabezado de la tarjeta",
    /head\.appendChild\(pendComentBtn\(id,\s*r\)\)/.test(src)],
  ["existe pendComentBtn", /function pendComentBtn\(/.test(src)],
  ["existe pendComentariosAbrir", /function pendComentariosAbrir\(/.test(src)],
  ["se LEE el hilo (select sobre GV_Recepcion_Comentarios)",
    /from\("GV_Recepcion_Comentarios"\)\s*\.select/.test(src)],
  ["se INSERTA el comentario (recepcion_id, autor, texto)",
    /from\("GV_Recepcion_Comentarios"\)\s*\.insert\(\{\s*recepcion_id:[^}]*autor:[^}]*texto:/.test(src)],
  ["NO se edita ni borra ese hilo (append-only)",
    !/from\("GV_Recepcion_Comentarios"\)\s*\.(update|delete)\b/.test(src)],
  ["mismo 'quién escribe' que Recibido: reusa pendReceptoresLista",
    /pendReceptoresLista\(\)\.concat\(\["__otro"\]\)/.test(src) &&
    /function pendComentariosAbrir[\s\S]*?pendReceptoresLista\(\)/.test(src)],
  ["guarda el nombre nuevo como opción (pendReceptorGuardar)",
    /function pendComentariosAbrir[\s\S]*?pendReceptorGuardar\(q\)/.test(src)],
  ["el badge se pinta en batch al abrir Pendientes (pendComentConteos)",
    /pendComentConteos\(rows\)/.test(src) && /function pendComentConteos\(/.test(src)],
];

let fail = 0;
checks.forEach(function (c) {
  if (c[1]) console.log("  ok · " + c[0]);
  else { console.error("  ✗ FALLA · " + c[0]); fail++; }
});

if (fail) { console.error("rcp-comentarios: " + fail + " en rojo"); process.exit(1); }
console.log("rcp-comentarios: OK");
