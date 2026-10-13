/* Candado v30.10 (Luis, 13/10/2026, D1 «sí»): el PAPEL de una recepción de mercadería va en el
   MOVIMIENTO de stock, no sólo en `ref`.

   Antes `ref` llevaba el número (remito o factura, sin decir cuál, `nroRemito || nroFactura`) y
   las FECHAS y el otro número se perdían: vivían en `Entregas Prov AT` / el recibo, no en el libro
   de stock. Ahora cada fila lleva `gv_doc` con {tipo, remito, fecha_remito, factura,
   fecha_factura, proveedor} — las mismas claves que escribe la recepción de insumos.

   Candado estático sobre recepcion.js (sin comentarios): el bloque que arma `stockRows` tiene que
   llevar gv_doc, y el objeto tiene que salir de opState (no de un literal inventado).
   Sale 1 si falla. */
const fs = require("fs"), path = require("path");
const src = fs.readFileSync(path.join(__dirname, "..", "recepcion.js"), "utf8")
  .replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/.*$/gm, "");

const i = src.indexOf("const stockRows = items.map");
const bloque = i >= 0 ? src.slice(Math.max(0, i - 900), i + 700) : "";
const malas = [];
if (i < 0) malas.push("no encontré el armado de stockRows");
if (!/gv_doc\s*:\s*_doc/.test(bloque)) malas.push("la fila de Movimientos_Stock no lleva gv_doc");
["tipoDoc", "nroRemito", "fechaRemito", "nroFactura", "fechaFactura"].forEach(function (k) {
  if (!new RegExp("opState\\." + k).test(bloque)) malas.push("el papel no toma opState." + k);
});
// y sigue yendo el ref de siempre (lo leen el dedup y la imputación de OC)
if (!/ref:\s*opState\.remito/.test(bloque)) malas.push("se perdió el ref: opState.remito");
// nada hardcodeado
if (/remito:\s*['"]\d/.test(bloque)) malas.push("hay un número de remito escrito a mano");

if (malas.length) {
  console.error("rcp-remito-en-movimiento: FALLA\n  - " + malas.join("\n  - "));
  process.exit(1);
}
console.log("rcp-remito-en-movimiento: OK — el remito, la factura y sus fechas viajan en gv_doc");
